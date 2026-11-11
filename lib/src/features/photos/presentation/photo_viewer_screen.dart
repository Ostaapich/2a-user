import '../../../core/network/api_client.dart';
import '../../../core/media/browser_media_export.dart';
import 'photo_viewer_share_draft.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../../../core/media/media_file_transfer.dart';
import '../../../core/media/media_file_metadata.dart';
import 'package:twoalogisticcabineuser/src/core/media/authenticated_media.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/utils/locale_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

import '../../../core/network/api_config.dart';
import '../../../core/branding/company_branding_provider.dart';
import '../../../core/ui/blurred_media_backdrop.dart';
import '../../../core/ui/media_image_viewport.dart';
import '../../../core/ui/media_loading_indicator.dart';
import '../../../core/ui/app_colors.dart';
import '../domain/photo_item.dart';
import '../../../core/ui/app_cached_media_image.dart';
import 'photo_report_video_player.dart';

void _showStyledSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  AppToast.showFromSnackBar(
    context,
    SnackBar(
      content: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: AppToast.hide,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? const Color(0xFFE53935) : context.brandPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 15),
      duration: const Duration(seconds: 3),
    ),
  );
}

class PhotoViewerScreen extends ConsumerStatefulWidget {
  final PhotoItem item;
  final List<PhotoItem>? allPhotos;
  final int? initialIndex;

  const PhotoViewerScreen({
    super.key,
    required this.item,
    this.allPhotos,
    this.initialIndex,
  });

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  bool _isDownloading = false;
  bool _isSharing = false;
  final _browserShareDraft = PhotoViewerShareDraft(clearPreparedBrowserMedia);
  String? get _preparedBrowserShareId => _browserShareDraft.preparedId;
  String? _browserOperationId;
  CancelToken? _transferCancel;
  double? _transferProgress;
  bool get _transferBusy => _isDownloading || _isSharing;

  void _onTransferProgress(int received, int total) {
    if (mounted) {
      setState(() => _transferProgress = total > 0 ? received / total : null);
    }
  }

  double _swipeDy = 0;
  bool _galleryGestureBlocked = false;
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex ?? 0;
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precacheAdjacentImages();
    });
  }

  @override
  void dispose() {
    if (!kIsWeb) _transferCancel?.cancel('viewer_closed');
    _browserShareDraft.reset();
    _pageController.dispose();
    super.dispose();
  }

  PhotoItem get _currentItem {
    if (widget.allPhotos != null && widget.allPhotos!.isNotEmpty) {
      return widget.allPhotos![_currentIndex];
    }
    return widget.item;
  }

  void _precacheAdjacentImages() {
    final items = widget.allPhotos != null && widget.allPhotos!.isNotEmpty
        ? widget.allPhotos!
        : <PhotoItem>[widget.item];
    if (items.length < 2) return;

    for (final index in <int>{_currentIndex - 1, _currentIndex + 1}) {
      if (index < 0 || index >= items.length) continue;
      final item = items[index];
      if (item.isVideo) continue;

      final fullUrl = ApiConfig.getMediaThumbnailUrl(
        item.url,
        size: 720,
        preserveAspectRatio: true,
      );
      if (fullUrl.isEmpty) continue;

      unawaited(
        precacheImage(
          ResizeImage(
            authenticatedImageProvider(context, fullUrl),
            width: 720,
            height: 720,
            policy: ResizeImagePolicy.fit,
          ),
          context,
        ).catchError((_) {}),
      );
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _swipeDy += details.delta.dy;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    // Если свайп был больше 100 пикселей вверх или вниз
    if (_swipeDy.abs() > 100) {
      Navigator.of(context).pop();
    }
    // Возвращаем в исходное состояние
    setState(() {
      _swipeDy = 0;
    });
  }

  Future<BrowserMediaExportResult> _exportInBrowser(
    PhotoItem item, {
    bool share = false,
  }) async {
    final api = ref.read(apiClientProvider);
    final url = ApiConfig.getMediaUrl(item.url);
    final path = authenticatedMediaPath(url);
    String fingerprint(String value) =>
        sha256.convert(utf8.encode(value)).toString();
    final identity = fingerprint(await api.getMediaCacheIdentity());
    final token = path == null ? null : await api.getToken();
    if (identity != fingerprint(await api.getMediaCacheIdentity())) {
      throw const BrowserMediaExportException('session_changed');
    }
    final id = const Uuid().v4();
    _browserOperationId = id;
    return beginBrowserMediaExport(
      BrowserMediaExportRequest(
        operationId: id,
        url: path == null
            ? url
            : '${api.activeBaseUrl.replaceFirst(RegExp(r'/$'), '')}$path',
        name: mediaFileName(item.url, isVideo: item.isVideo),
        apiBase: api.activeBaseUrl,
        token: token,
        identity: identity,
        getIdentity: () async => fingerprint(await api.getMediaCacheIdentity()),
        share: share,
        onProgress: _onTransferProgress,
      ),
    );
  }

  void _browserExportMessage(BrowserMediaExportException error) {
    if (!mounted) return;
    final message = switch (error.code) {
      'cancelled' => tr(context, ru: 'Загрузка отменена', zh: '下载已取消'),
      'session_changed' => tr(
        context,
        ru: 'Аккаунт изменился. Загрузка отменена.',
        zh: '账号已变更，下载已取消。',
      ),
      'streaming_unavailable' => tr(
        context,
        ru: 'Браузер не смог начать загрузку. Обновите его или откройте файл в приложении.',
        zh: '浏览器无法开始下载，请更新浏览器或在应用中打开文件。',
      ),
      'media_denied' => tr(
        context,
        ru: 'Файл недоступен. Проверьте доступ и повторите попытку.',
        zh: '文件不可用，请检查权限后重试。',
      ),
      'share_expired' => tr(
        context,
        ru: 'Подготовьте файл для отправки ещё раз',
        zh: '请重新准备要分享的文件',
      ),
      'busy' => tr(
        context,
        ru: 'Дождитесь завершения предыдущей загрузки',
        zh: '请等待上一项下载完成',
      ),
      _ => tr(
        context,
        ru: 'Загрузка прервалась. Повторите попытку.',
        zh: '下载中断，请重试。',
      ),
    };
    _showStyledSnackBar(context, message, isError: error.code != 'cancelled');
  }

  Future<void> _downloadMedia() async {
    if (_transferBusy) return;
    _transferCancel = CancelToken();
    setState(() {
      _isDownloading = true;
      _transferProgress = null;
    });
    final api = ref.read(apiClientProvider);
    final companyName = ref.read(companyNameProvider);
    String? temporaryPath;
    try {
      final currentItem = _currentItem;

      if (kIsWeb) {
        _browserShareDraft.reset();
        await _exportInBrowser(currentItem);
        if (!mounted) return;
        _showStyledSnackBar(
          context,
          tr(
            context,
            ru: 'Файл передан браузеру. Проверьте загрузки.',
            zh: '文件已交给浏览器，请查看下载。',
          ),
        );
        return;
      }

      // Запрашиваем разрешение на сохранение в галерею
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!mounted) return;
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!mounted) return;
        if (!granted) {
          if (mounted) {
            _showStyledSnackBar(
              context,
              'Нет разрешения на сохранение в галерею',
              isError: true,
            );
          }
          return;
        }
      }

      String savePath;
      final fullUrl = ApiConfig.getMediaUrl(currentItem.url);

      final tempDir = await getTemporaryDirectory();
      savePath =
          '${tempDir.path}/${DateTime.now().microsecondsSinceEpoch}_${mediaFileName(currentItem.url, isVideo: currentItem.isVideo)}';
      temporaryPath = savePath;
      await transferMediaToFile(
        api,
        fullUrl,
        File(savePath),
        cancelToken: _transferCancel!,
        onProgress: _onTransferProgress,
      );
      if (!mounted) return;

      // Сохраняем в галерею
      if (currentItem.isVideo) {
        await Gal.putVideo(savePath, album: companyName);
      } else {
        await Gal.putImage(savePath, album: companyName);
      }

      if (mounted) {
        _showStyledSnackBar(context, 'Сохранено в галерею');
      }
    } on BrowserMediaExportException catch (error) {
      _browserExportMessage(error);
    } on DioException catch (e) {
      if (mounted) {
        String message = 'Ошибка загрузки';
        if (e.response?.statusCode == 403) {
          message = 'Нет доступа к файлу';
        } else if (e.response?.statusCode == 404) {
          message = 'Файл не найден';
        }
        _showStyledSnackBar(context, message, isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showStyledSnackBar(context, 'Не удалось сохранить', isError: true);
      }
    } finally {
      if (temporaryPath != null) {
        try {
          await File(temporaryPath).delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _browserOperationId = null;
        });
      }
    }
  }

  Future<void> _shareMedia(BuildContext context) async {
    if (_transferBusy) return;
    final shareRevision = _browserShareDraft.revision;
    _transferCancel = CancelToken();
    setState(() {
      _isSharing = true;
      _transferProgress = null;
    });
    String? temporaryPath;
    final api = ref.read(apiClientProvider);
    try {
      final currentItem = _currentItem;
      final fullUrl = ApiConfig.getMediaUrl(currentItem.url);

      // Получаем box ДО async операций
      final box = context.findRenderObject() as RenderBox?;

      final XFile shareFile;
      if (kIsWeb) {
        final prepared = _preparedBrowserShareId;
        final result = prepared == null
            ? await _exportInBrowser(currentItem, share: true)
            : await sharePreparedBrowserMedia(prepared);
        if (!mounted || !context.mounted) {
          if (result.preparedId != null) {
            clearPreparedBrowserMedia(result.preparedId!);
          }
          return;
        }
        if (!_browserShareDraft.accept(shareRevision, result.preparedId)) {
          return;
        }
        setState(() {});
        if (result.kind == BrowserMediaExportKind.shareReady) {
          _showStyledSnackBar(
            context,
            tr(
              context,
              ru: 'Файл готов. Нажмите «Отправить файл», чтобы выбрать приложение.',
              zh: '文件已准备好，请点击“发送文件”选择应用。',
            ),
          );
        } else if (result.kind == BrowserMediaExportKind.downloaded) {
          _showStyledSnackBar(
            context,
            tr(
              context,
              ru: 'Файл передан в загрузки. Отправьте его из приложения «Файлы» или папки загрузок.',
              zh: '文件已交给下载，请从“文件”应用或下载文件夹中分享。',
            ),
          );
        }
        return;
      } else {
        final tempDir = await getTemporaryDirectory();
        temporaryPath =
            '${tempDir.path}/${DateTime.now().microsecondsSinceEpoch}_${mediaFileName(currentItem.url, isVideo: currentItem.isVideo)}';
        await transferMediaToFile(
          api,
          fullUrl,
          File(temporaryPath),
          cancelToken: _transferCancel!,
          onProgress: _onTransferProgress,
        );
        shareFile = XFile(
          temporaryPath,
          mimeType: mediaMimeType(
            currentItem.url,
            isVideo: currentItem.isVideo,
          ),
        );
      }
      if (!mounted) return;

      // Шарим файл (sharePositionOrigin нужен для iPad)
      await Share.shareXFiles(
        [shareFile],
        text: currentItem.trackingNumber != null
            ? 'Трек: ${currentItem.trackingNumber}'
            : null,
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : const Rect.fromLTWH(0, 0, 100, 100),
      );
    } on BrowserMediaExportException catch (error) {
      if (mounted && shareRevision == _browserShareDraft.revision) {
        setState(_browserShareDraft.reset);
      }
      _browserExportMessage(error);
    } on DioException catch (e) {
      if (!context.mounted) return;
      String message = 'Ошибка';
      if (e.response?.statusCode == 403) {
        message = 'Нет доступа к файлу';
      } else if (e.response?.statusCode == 404) {
        message = 'Файл не найден';
      }
      _showStyledSnackBar(context, message, isError: true);
    } catch (e) {
      if (!context.mounted) return;
      _showStyledSnackBar(context, 'Не удалось поделиться', isError: true);
    } finally {
      if (temporaryPath != null) {
        try {
          await File(temporaryPath).delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isSharing = false;
          _browserOperationId = null;
        });
      }
    }
  }

  Widget _mediaPage(PhotoItem item, int index) {
    final imageUrl = ApiConfig.getMediaUrl(item.url);
    if (item.isVideo) {
      return GestureDetector(
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Transform.translate(
          offset: Offset(0, _swipeDy),
          child: Center(
            child: PhotoReportVideoPlayer(
              key: ValueKey('video-$index-${item.url}'),
              url: imageUrl,
              active: index == _currentIndex,
            ),
          ),
        ),
      );
    }
    return MediaImageViewport(
      key: ValueKey('photo-$index-${item.url}'),
      imageKey: item.url,
      active: index == _currentIndex,
      onInteractionBlockedChanged: (blocked) {
        if (mounted &&
            index == _currentIndex &&
            _galleryGestureBlocked != blocked) {
          setState(() => _galleryGestureBlocked = blocked);
        }
      },
      onDismiss: () => Navigator.of(context).pop(),
      child: AuthenticatedCachedImage(
        imageUrl: index == _currentIndex
            ? imageUrl
            : ApiConfig.getMediaThumbnailUrl(
                item.url,
                size: 720,
                preserveAspectRatio: true,
              ),
        fit: BoxFit.contain,
        memCacheWidth: index == _currentIndex ? 3072 : 720,
        memCacheHeight: index == _currentIndex ? 3072 : 720,
        progressIndicatorBuilder: (context, _, progress) => Stack(
          fit: StackFit.expand,
          children: [
            AppCachedMediaImage(
              url: item.url,
              thumbnailSize: 720,
              fit: BoxFit.contain,
              memCacheWidth: 720,
              memCacheHeight: 720,
            ),
            Center(child: MediaLoadingIndicator(progress: progress)),
          ],
        ),
        placeholder: (_, _) => AppCachedMediaImage(
          url: item.url,
          thumbnailSize: 720,
          fit: BoxFit.contain,
          memCacheWidth: 720,
          memCacheHeight: 720,
        ),
        errorWidget: (_, _, _) => const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.white70,
            size: 48,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiplePhotos =
        widget.allPhotos != null && widget.allPhotos!.length > 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        body: BlurredMediaBackdrop(
          imageUrl: _currentItem.isVideo
              ? null
              : ApiConfig.getMediaUrl(_currentItem.url),
          child: Stack(
            children: [
              Positioned.fill(
                child: hasMultiplePhotos
                    ? PageView.builder(
                        controller: _pageController,
                        physics: _galleryGestureBlocked
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        itemCount: widget.allPhotos!.length,
                        onPageChanged: (index) {
                          setState(() {
                            _browserShareDraft.reset();
                            _currentIndex = index;
                            _galleryGestureBlocked = false;
                            _swipeDy = 0;
                          });
                          _precacheAdjacentImages();
                        },
                        itemBuilder: (context, index) {
                          final item = widget.allPhotos![index];
                          return _mediaPage(item, index);
                        },
                      )
                    : _mediaPage(widget.item, 0),
              ),
              // Top bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 8,
                    right: 8,
                    bottom: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: tr(
                          context,
                          ru: 'Закрыть просмотр',
                          zh: '关闭预览',
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.3),
                        ),
                      ),
                      const Spacer(),
                      if (hasMultiplePhotos)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${_currentIndex + 1} / ${widget.allPhotos!.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (hasMultiplePhotos) const Spacer(),
                      IconButton(
                        tooltip: tr(context, ru: 'Сохранить файл', zh: '保存文件'),
                        onPressed: _transferBusy ? null : _downloadMedia,
                        icon: _isDownloading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.download_rounded,
                                color: Colors.white,
                              ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: tr(
                          context,
                          ru: _preparedBrowserShareId == null
                              ? 'Поделиться файлом'
                              : 'Отправить файл',
                          zh: _preparedBrowserShareId == null ? '分享文件' : '发送文件',
                        ),
                        onPressed: _transferBusy
                            ? null
                            : () => _shareMedia(context),
                        icon: const Icon(
                          Icons.share_rounded,
                          color: Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_transferBusy)
                Positioned(
                  left: 16,
                  right: 16,
                  top: MediaQuery.paddingOf(context).top + 82,
                  child: Material(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LinearProgressIndicator(
                            value: _transferProgress,
                            semanticsLabel: tr(
                              context,
                              ru: 'Загрузка файла',
                              zh: '正在下载文件',
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              if (kIsWeb && _browserOperationId != null) {
                                cancelBrowserMediaExport(_browserOperationId!);
                              } else {
                                _transferCancel?.cancel('user_cancelled');
                              }
                            },
                            child: Text(
                              tr(context, ru: 'Отменить загрузку', zh: '取消下载'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_preparedBrowserShareId != null && !_transferBusy)
                Positioned(
                  left: 16,
                  right: 16,
                  top: MediaQuery.paddingOf(context).top + 82,
                  child: FilledButton.icon(
                    onPressed: () => _shareMedia(context),
                    icon: const Icon(Icons.ios_share),
                    label: Text(tr(context, ru: 'Отправить файл', zh: '发送文件')),
                  ),
                ),
              // Bottom info
              if (widget.item.trackingNumber != null ||
                  widget.item.assemblyNumber != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: MediaQuery.of(context).padding.bottom + 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.item.trackingNumber != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.local_shipping_outlined,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Трек: ${widget.item.trackingNumber}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (widget.item.assemblyNumber != null)
                          Row(
                            children: [
                              const Icon(
                                Icons.inventory_2_outlined,
                                color: Colors.white70,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'ID сборки: ${widget.item.assemblyNumber}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

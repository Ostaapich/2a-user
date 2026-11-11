// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phone_form_field/phone_form_field.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';
import '../../../core/network/api_config.dart';
import '../../../core/ui/app_cached_media_image.dart';
import '../../../core/ui/sheet_handle.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/ui/app_input_decoration.dart';
import '../../../core/ui/app_search_field.dart';
import '../../../core/ui/phone_input_field.dart';

import '../../../core/ui/app_layout.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/unsaved_changes_guard.dart';
import '../../../core/ui/status_pill.dart';
import '../../../core/ui/status_timeline_sheet.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/clipboard_helper.dart';
import '../../../core/utils/image_compressor.dart';
import '../../../core/utils/locale_text.dart';
import '../../clients/application/client_codes_controller.dart';
import '../../auth/data/auth_provider.dart';
import '../../carriers/presentation/client_carrier_tracking_panel.dart';
import '../../assembly_scan_sessions/presentation/assembly_scan_sessions_section.dart';
import '../../assembly_scan_sessions/presentation/assembly_scan_track_video_link.dart';
import '../data/tracks_provider.dart';
import '../../training/presentation/training_target.dart';
import '../data/assemblies_provider.dart';
import '../domain/track_item.dart';
import '../domain/assembly_form_draft.dart';
import '../domain/product_info_completeness.dart';
import '../domain/photo_report_options.dart';
import 'widgets/photo_report_selection_sheet.dart';
import '../../loyalty/data/client_loyalty_provider.dart';
import '../../loyalty/presentation/client_loyalty_section.dart';
import 'widgets/track_sheet_surface.dart';
import 'widgets/photo_report_summary.dart';
import '../../assemblies/domain/box.dart';
import '../../photos/presentation/photo_viewer_screen.dart';
import '../../photos/domain/photo_item.dart';
import '../../../core/ui/tutorial_card.dart';
import 'add_tracks_dialog.dart';
import 'widgets/client_track_compact_card.dart';
import 'track_warehouse_delivery_panel.dart';

// Alias для authStateProvider
final authStateProvider = authProvider;

const _unknownTrackQuestionType = 'unknown_track_check';
const _clientCodeTransferQuestionType = 'client_code_transfer';
const _unknownTrackQuestionText =
    'Не знаю что это за трек номер, могли бы проверить и код клиента и трек номер';

String _completeProductInfoMessage(BuildContext context, bool needsDetails) =>
    needsDetails
    ? tr(
        context,
        ru: 'Для выбранного тарифа у каждого товара нужны название, количество больше нуля и фотография. Заполните данные во всех выбранных треках.',
        zh: '此运价要求每件商品填写名称、正数数量并上传商品照片。请完善所有已选运单的商品资料。',
      )
    : tr(
        context,
        ru: 'Для выбранного тарифа обязательна фотография каждого товара. Загрузите и сохраните фото в данных товара каждого выбранного трека.',
        zh: '此运价要求每件商品提供照片。请在每个已选运单的商品资料中上传并保存照片。',
      );

bool _canSelectTrackForAssembly(
  TrackItem track,
  Set<String> locallyRequestedReturns,
) =>
    track.isAvailableForAssemblySelection &&
    !locallyRequestedReturns.contains(track.code) &&
    track.statusCode != 'return_requested';

String? _assemblySelectionHint(
  BuildContext context,
  TrackItem track,
  Set<String> locallyRequestedReturns,
) {
  if (locallyRequestedReturns.contains(track.code) ||
      track.statusCode == 'return_requested') {
    return 'По треку запрошен возврат';
  }
  return switch (track.assemblyBlockReason) {
    'photo_request_pending' => tr(
      context,
      ru: 'По треку есть незавершённый фотоотчёт. Дождитесь выполнения или отмените запрос.',
      zh: '此运单有未完成的拍照申请，请等待完成或取消申请。',
    ),
    'photo_request_cooldown' => tr(
      context,
      ru: 'Фотоотчёт выполнен или отменён сегодня. Добавить в сборку можно завтра по времени склада (Китай).',
      zh: '拍照申请今天已完成或取消，按中国仓库时间明天起可加入打包。',
    ),
    _ => track.assemblySelectionHint,
  };
}

@visibleForTesting
bool shouldAutofillGroupedTracksViewport({
  required bool isGroupedMode,
  required bool hasMore,
  required bool isLoading,
  required bool hasError,
  required bool hasScrollClients,
  required double maxScrollExtent,
}) {
  return isGroupedMode &&
      hasMore &&
      !isLoading &&
      !hasError &&
      hasScrollClients &&
      maxScrollExtent <= 1;
}

/// Парсит HEX цвет из строки (например "#FF5733" или "FF5733")
Color? parseHexColor(String? hexString) {
  if (hexString == null || hexString.isEmpty) return null;
  try {
    String hex = hexString.replaceAll('#', '');
    if (hex.length == 6) {
      hex = 'FF$hex'; // Добавляем альфа-канал
    }
    return Color(int.parse(hex, radix: 16));
  } catch (_) {
    return null;
  }
}

String _fileNameWithExtension(String fileName, String extension) {
  final cleanExtension = extension.startsWith('.')
      ? extension.substring(1)
      : extension;
  if (cleanExtension.isEmpty) return fileName;

  final dotIndex = fileName.lastIndexOf('.');
  final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  return '$baseName.$cleanExtension';
}

class _ClientCodeOption {
  final int id;
  final String code;

  const _ClientCodeOption({required this.id, required this.code});
}

class _PackagingBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _PackagingBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

Future<void> _copyTrackCode(
  BuildContext context,
  String code, {
  bool compactToast = false,
}) async {
  final copied = await AppClipboard.copyText(code);
  if (!context.mounted) return;
  if (!copied) {
    _showStyledSnackBar(context, 'Не удалось скопировать', isError: true);
    return;
  }

  HapticFeedback.lightImpact();
  if (compactToast) {
    AppToast.showFromSnackBar(
      context,
      const SnackBar(
        content: Text('Трек скопирован'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  _showStyledSnackBar(context, 'Трек скопирован');
}

/// Форматирует число, убирая лишние нули: 3.5 → "3.5", 5.0 → "5", 5.70 → "5.7"
String _formatDecimal(double value) {
  if (value == value.truncateToDouble()) {
    return value.toInt().toString();
  }
  final s = value.toStringAsFixed(2);
  // Убираем trailing zeros после точки
  if (s.endsWith('0')) return s.substring(0, s.length - 1);
  return s;
}

class TracksScreen extends ConsumerStatefulWidget {
  final int? initialTrackId;
  final String? initialTrackCode;
  final int? initialAssemblyId;
  final String? initialClientCode;
  final ViewMode? initialViewMode;
  final List<TrackItem>? embeddedTracks;
  final bool embeddedAsAssembly;
  final VoidCallback? onEmbeddedChanged;

  const TracksScreen({
    super.key,
    this.initialTrackId,
    this.initialTrackCode,
    this.initialAssemblyId,
    this.initialClientCode,
    this.initialViewMode,
  }) : embeddedTracks = null,
       embeddedAsAssembly = false,
       onEmbeddedChanged = null;

  const TracksScreen.embedded({
    super.key,
    required List<TrackItem> tracks,
    bool asAssembly = false,
    this.onEmbeddedChanged,
  }) : initialTrackId = null,
       initialTrackCode = null,
       initialAssemblyId = null,
       initialClientCode = null,
       initialViewMode = null,
       embeddedTracks = tracks,
       embeddedAsAssembly = asAssembly;

  @override
  ConsumerState<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends ConsumerState<TracksScreen> {
  final ScrollController _scrollController = ScrollController();

  // Local tracking for photo report requests and their notes
  final Set<String> _requestedPhotoReports = <String>{};
  final Map<String, String> _photoRequestNotes = <String, String>{};
  final Map<String, DateTime> _photoRequestCreatedAt = <String, DateTime>{};
  final Map<String, DateTime> _photoRequestUpdatedAt = <String, DateTime>{};

  // Фильтры - теперь используем код статуса из БД
  String? _statusCode; // null = Все
  String? _photoRequestStatusCode;
  String? _questionStatusCode;
  ViewMode _viewMode = ViewMode.singles;
  ProductInfoMode _productInfoMode = ProductInfoMode.all;
  DeliveryInfoMode _deliveryInfoMode = DeliveryInfoMode.all;
  TrackSortMode _sortMode = TrackSortMode.createdAt;
  String _query = '';
  Timer? _searchDebounce;

  // Текущий notifier для отслеживания изменений состояния
  PaginatedTracksNotifier? _currentNotifier;

  final GlobalKey _tracksListKey = GlobalKey();
  final GlobalKey _fabKey = GlobalKey();
  final GlobalKey _filtersKey = GlobalKey();
  final GlobalKey _trackDetailKey = GlobalKey();
  final GlobalKey _actionsRowKey = GlobalKey();
  final GlobalKey _assemblyKey = GlobalKey();

  // Выбранные треки
  final Set<String> _selectedTracks = <String>{};
  String? _selectedStatus;
  String? _assemblyDraftScope;
  AssemblyFormDraft? _assemblyDraft;
  final Set<String> _selectableStatuses = const {
    'На складе',
    'Отправлен',
    'Прибыл на терминал',
    'Сформирован к выдаче',
  };

  // Return request local state
  final Set<String> _returnRequestedTracks = <String>{};

  // Local data stores
  final Map<String, String> _askedQuestions = <String, String>{};
  final Map<String, String> _questionStatus =
      <String, String>{}; // Новый, В работе, Завершен
  final Map<String, String> _questionAnswers = <String, String>{};
  final Map<String, DateTime> _questionCreatedAt = <String, DateTime>{};
  final Map<String, DateTime> _questionUpdatedAt = <String, DateTime>{};
  final Map<String, String> _overrideComments = <String, String>{};
  final Map<String, _ProductInfo> _productInfos = <String, _ProductInfo>{};
  final Map<String, String> _groupComments = <String, String>{};
  final Map<String, String> _groupQuestions = <String, String>{};
  final Map<String, DateTime> _groupQuestionCreatedAt = <String, DateTime>{};
  final Map<String, DateTime> _groupQuestionUpdatedAt = <String, DateTime>{};

  bool _isRefreshing = false;
  DateTime? _lastLoadMoreTime;
  bool _groupedViewportAutofillScheduled = false;
  String? _handledInitialTargetKey;
  String? _initialClientSwitchTarget;
  String? _filtersInitializedForClientCode;
  bool _loadingInitialTargetIntoList = false;
  String? _highlightedGroupKey;
  Timer? _highlightTimer;
  final Map<String, GlobalKey> _targetGroupKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _viewMode = widget.initialViewMode ?? ViewMode.singles;
    if (widget.initialAssemblyId != null) {
      _viewMode = ViewMode.groups;
    }
  }

  @override
  void didUpdateWidget(covariant TracksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialViewMode != widget.initialViewMode &&
        widget.initialViewMode != null) {
      _viewMode = widget.initialViewMode!;
    }
    if (oldWidget.initialTrackId != widget.initialTrackId ||
        oldWidget.initialTrackCode != widget.initialTrackCode ||
        oldWidget.initialAssemblyId != widget.initialAssemblyId ||
        oldWidget.initialClientCode != widget.initialClientCode) {
      _handledInitialTargetKey = null;
      _initialClientSwitchTarget = null;
      if (widget.initialAssemblyId != null) {
        _viewMode = ViewMode.groups;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _highlightTimer?.cancel();
    _currentNotifier?.removeListener(_onNotifierStateChanged);
    super.dispose();
  }

  void _disposeAfterBottomSheetClose(Iterable<VoidCallback> disposers) {
    // showBlurredModalBottomSheet completes when the route is popped, while the sheet
    // subtree can still rebuild during the closing animation. Disposing field
    // controllers immediately may make TextField rebuild with an already
    // disposed controller.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 500)).then((_) {
        for (final dispose in disposers) {
          dispose();
        }
      }),
    );
  }

  void _onNotifierStateChanged() {
    if (mounted) {
      final tracks = _currentNotifier?.state.tracks ?? const <TrackItem>[];
      _syncMapsWithServerData(tracks);
      setState(() {});
    }
  }

  void _updateNotifierListener(PaginatedTracksNotifier newNotifier) {
    if (_currentNotifier != newNotifier) {
      _currentNotifier?.removeListener(_onNotifierStateChanged);
      _currentNotifier = newNotifier;
      _currentNotifier?.addListener(_onNotifierStateChanged);
    }
  }

  void _scheduleGroupedViewportAutofill({
    required String clientCode,
    required PaginatedTracksState tracksState,
    required TracksFilterParams currentFilters,
  }) {
    if (_groupedViewportAutofillScheduled ||
        _viewMode != ViewMode.groups ||
        tracksState.filters != currentFilters ||
        tracksState.isLoading ||
        !tracksState.hasMore ||
        tracksState.error != null) {
      return;
    }

    _groupedViewportAutofillScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _groupedViewportAutofillScheduled = false;
      if (!mounted) return;

      final notifier = ref.read(paginatedTracksProvider(clientCode));
      final latestState = notifier.state;
      final latestFilters = _getFilterParams(clientCode);
      final hasScrollClients = _scrollController.hasClients;
      final maxScrollExtent = hasScrollClients
          ? _scrollController.position.maxScrollExtent
          : double.infinity;

      if (!identical(_currentNotifier, notifier) ||
          latestState.filters != latestFilters) {
        return;
      }

      if (shouldAutofillGroupedTracksViewport(
        isGroupedMode: _viewMode == ViewMode.groups,
        hasMore: latestState.hasMore,
        isLoading: latestState.isLoading,
        hasError: latestState.error != null,
        hasScrollClients: hasScrollClients,
        maxScrollExtent: maxScrollExtent,
      )) {
        unawaited(notifier.loadMore());
      }
    });
  }

  /// Метод для обновления списка треков
  void _refreshTracks() {
    final clientCode = ref.read(activeClientCodeProvider);
    if (clientCode != null) {
      // Обновляем с актуальными фильтрами из UI
      final filterParams = _getFilterParams(clientCode);
      ref.read(paginatedTracksProvider(clientCode)).updateFilters(filterParams);
    }
    widget.onEmbeddedChanged?.call();
  }

  /// Очищает оптимистичные Map-записи для треков, у которых сервер
  /// уже подтвердил данные после pull-to-refresh или silent refresh.
  bool _syncMapsWithServerData(List<TrackItem> serverTracks) {
    bool changed = false;
    for (final track in serverTracks) {
      // Если сервер вернул photo request — оптимистика больше не нужна
      if (track.photoRequests.isNotEmpty &&
          _requestedPhotoReports.contains(track.code)) {
        _requestedPhotoReports.remove(track.code);
        _photoRequestNotes.remove(track.code);
        _photoRequestCreatedAt.remove(track.code);
        _photoRequestUpdatedAt.remove(track.code);
        changed = true;
      }
      // Если сервер вернул вопрос — оптимистика больше не нужна
      if (track.questions.isNotEmpty &&
          _askedQuestions.containsKey(track.code)) {
        _askedQuestions.remove(track.code);
        _questionStatus.remove(track.code);
        _questionAnswers.remove(track.code);
        _questionCreatedAt.remove(track.code);
        _questionUpdatedAt.remove(track.code);
        changed = true;
      }
      // Если сервер вернул productInfo — оптимистика больше не нужна
      if (track.productInfo != null && _productInfos.containsKey(track.code)) {
        _productInfos.remove(track.code);
        changed = true;
      }
    }
    return changed;
  }

  Future<bool> _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    String? cancelLabel,
    String? confirmLabel,
    bool destructive = false,
  }) async {
    final res = await showBlurredModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: Text(
                          cancelLabel ?? tr(context, ru: 'Нет', zh: '取消'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        style: destructive
                            ? FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                foregroundColor: Colors.white,
                              )
                            : null,
                        child: Text(
                          confirmLabel ?? tr(context, ru: 'Да', zh: '确认'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return res ?? false;
  }

  Future<void> _showPhotoRequestSheet(
    BuildContext context,
    TrackItem track,
  ) async {
    await _requestPhotoInline(context, track, '');
  }

  Future<PhotoReportSelection?> _selectPhotoReport(
    BuildContext context,
    TrackItem track, {
    PhotoRequest? existing,
  }) {
    return showBlurredModalBottomSheet<PhotoReportSelection>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PhotoReportSelectionSheet(
        trackNumber: track.code,
        loadOptions: ref.read(tracksApiServiceProvider).photoReportOptions,
        loadLoyalty: existing == null
            ? ref.read(clientLoyaltyApiProvider).load
            : null,
        initialType: existing?.reportType,
        initialWish: existing?.wishes,
        savedPriceUsd: existing?.priceUsd,
        allowTypeChange: track.isPending,
      ),
    );
  }

  Future<void> _showAskQuestionSheet(
    BuildContext context,
    TrackItem track,
  ) async {
    final result = await showBlurredModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) {
        return _TrackSheetSurface(
          icon: Icons.help_rounded,
          title: 'Вопрос складу',
          subtitle: 'Проверим трек ${track.code} и код клиента',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TrackSheetMetaCard(
                icon: Icons.lock_outline_rounded,
                title: 'Текст задачи',
                value: _unknownTrackQuestionText,
                valueMaxLines: 4,
              ),
              const SizedBox(height: 12),
              _TrackSheetNoticeCard(
                icon: Icons.task_alt_rounded,
                text: 'Склад получит задачу и ответит прямо в карточке трека.',
                color: Colors.green.shade700,
              ),
              const SizedBox(height: 14),
              _TrackSheetPrimaryButton(
                label: 'Отправить на склад',
                icon: Icons.send_rounded,
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
            ],
          ),
        );
      },
    );
    if (result == true) {
      if (!context.mounted) return;
      final now = DateTime.now();
      const question = _unknownTrackQuestionText;

      // Получаем данные для API
      final auth = ref.read(authStateProvider);
      final clientId = auth.clientId;
      // Берём clientCodeId из самого трека (правильный код), fallback на первый код клиента
      int? clientCodeId = track.clientCodeId;
      if (clientCodeId == null) {
        final codes = auth.clientData?['codes'] as List<dynamic>?;
        if (codes != null && codes.isNotEmpty) {
          final firstCode = codes.first;
          if (firstCode is Map<String, dynamic>) {
            clientCodeId = firstCode['id'] as int?;
          }
        }
      }

      if (track.id == null || clientId == null) {
        _showStyledSnackBar(
          context,
          'Ошибка: нет данных для запроса',
          isError: true,
        );
        return;
      }

      // Оптимистичное обновление UI
      final wasEmpty = (_askedQuestions[track.code] ?? '').trim().isEmpty;
      setState(() {
        _askedQuestions[track.code] = question;
        if (wasEmpty) {
          _questionCreatedAt[track.code] = now;
        }
        _questionUpdatedAt[track.code] = now;
      });

      // Отправляем запрос в API
      final apiService = ref.read(tracksApiServiceProvider);
      if (track.id == null) return;
      final success = await apiService.createTrackQuestion(
        clientId: clientId,
        clientCodeId: clientCodeId,
        trackId: track.id!,
        trackNumber: track.code,
        question: question,
        questionType: _unknownTrackQuestionType,
      );

      if (success) {
        if (!context.mounted) return;
        _showStyledSnackBar(context, 'Вопрос отправлен');
        // Обновляем список треков
        _refreshTracks();
      } else {
        // Откатываем изменения при ошибке
        if (!context.mounted) return;
        setState(() {
          if (wasEmpty) {
            _askedQuestions.remove(track.code);
            _questionCreatedAt.remove(track.code);
          }
          _questionUpdatedAt.remove(track.code);
        });
        _showStyledSnackBar(context, 'Ошибка отправки вопроса', isError: true);
      }
    }
  }

  List<_ClientCodeOption> _clientCodeOptionsFromAuth() {
    final auth = ref.read(authStateProvider);
    final rawCodes = auth.clientData?['codes'] as List<dynamic>?;
    if (rawCodes == null) return const [];

    return rawCodes
        .whereType<Map<String, dynamic>>()
        .map((json) {
          final id = json['id'];
          final code = json['code']?.toString();
          final parsedId = id is int ? id : int.tryParse(id?.toString() ?? '');
          if (parsedId == null || code == null || code.trim().isEmpty) {
            return null;
          }
          return _ClientCodeOption(id: parsedId, code: code.trim());
        })
        .whereType<_ClientCodeOption>()
        .toList(growable: false);
  }

  Future<void> _showClientCodeTransferSheet(
    BuildContext context,
    TrackItem track,
  ) async {
    final trackId = track.id;
    if (trackId == null) {
      _showStyledSnackBar(context, 'Ошибка: трек не найден', isError: true);
      return;
    }

    final options = _clientCodeOptionsFromAuth()
        .where((code) => code.id != track.clientCodeId)
        .toList(growable: false);
    if (options.isEmpty) {
      _showStyledSnackBar(
        context,
        'Нет другого кода клиента для переноса',
        isError: true,
      );
      return;
    }

    var selected = options.first;
    final confirmed = await showBlurredModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final codeListHeight = (options.length * 78.0)
                .clamp(78.0, MediaQuery.sizeOf(sheetContext).height * 0.38)
                .toDouble();

            return _TrackSheetSurface(
              icon: Icons.switch_account_rounded,
              title: 'Перенос кода',
              subtitle:
                  'Склад переложит трек ${track.code} после выполнения задачи',
              footer: _TrackSheetPrimaryButton(
                label: 'Создать задачу складу',
                icon: Icons.task_alt_rounded,
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TrackSheetMetaCard(
                    icon: Icons.qr_code_rounded,
                    title: 'Текущий трек',
                    value: track.code,
                  ),
                  const SizedBox(height: 12),
                  _TrackFilterSectionCard(
                    icon: Icons.badge_rounded,
                    title: 'Новый код клиента',
                    child: SizedBox(
                      height: codeListHeight,
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: options.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          return _SheetOptionTile(
                            icon: Icons.badge_outlined,
                            title: options[i].code,
                            subtitle: 'Создать задачу на перенос',
                            selected: selected.id == options[i].id,
                            onTap: () =>
                                setSheetState(() => selected = options[i]),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final apiService = ref.read(tracksApiServiceProvider);
    final success = await apiService.requestClientCodeTransfer(
      trackId: trackId,
      targetClientCodeId: selected.id,
    );
    if (!context.mounted) return;

    if (success) {
      _showStyledSnackBar(context, 'Задача на перенос создана');
      _refreshTracks();
    } else {
      _showStyledSnackBar(
        context,
        'Не удалось создать задачу на перенос',
        isError: true,
      );
    }
  }

  Future<void> _cancelPhotoRequest(TrackItem track) async {
    if (track.activePhotoRequest?.canChange == false) return;

    final confirmed = await _confirmAction(
      context,
      title: tr(context, ru: 'Отменить запрос фотоотчёта?', zh: '取消拍照申请？'),
      message: tr(
        context,
        ru: 'Запрос фотоотчёта будет отменён. Добавить трек в сборку можно будет завтра по времени склада (Китай).',
        zh: '拍照申请将被取消，按中国仓库时间明天起可将运单加入打包。',
      ),
    );

    if (!confirmed) return;
    if (!mounted) return;

    // Если есть активный запрос из API
    final activeRequest = track.activePhotoRequest;
    if (activeRequest != null) {
      final apiService = ref.read(tracksApiServiceProvider);
      final success = await apiService.cancelPhotoRequest(activeRequest.id);

      if (success) {
        if (!mounted) return;
        setState(() {
          _requestedPhotoReports.remove(track.code);
          _photoRequestNotes.remove(track.code);
          _photoRequestCreatedAt.remove(track.code);
          _photoRequestUpdatedAt.remove(track.code);
        });
        _refreshTracks();
        _showStyledSnackBar(
          context,
          tr(
            context,
            ru: 'Запрос отменён. Добавить трек в сборку можно завтра по времени склада (Китай).',
            zh: '申请已取消，按中国仓库时间明天起可加入打包。',
          ),
        );
      } else {
        if (!mounted) return;
        _showStyledSnackBar(context, 'Ошибка отмены запроса', isError: true);
      }
    } else {
      if (!mounted) return;
      setState(() {
        _requestedPhotoReports.remove(track.code);
        _photoRequestNotes.remove(track.code);
        _photoRequestCreatedAt.remove(track.code);
        _photoRequestUpdatedAt.remove(track.code);
      });
      _showStyledSnackBar(context, 'Запрос фотоотчёта отменён');
    }
  }

  Future<void> _showEditPhotoWishSheet(
    BuildContext context,
    TrackItem track,
  ) async {
    await _updatePhotoWishInline(context, track, '');
  }

  Future<bool> _updatePhotoWishInline(
    BuildContext context,
    TrackItem track,
    String wish,
  ) async {
    final request = track.activePhotoRequest;
    if (request == null ||
        !request.canChange ||
        (!track.isPending && request.reportType != 'custom')) {
      return false;
    }
    final selection = await _selectPhotoReport(
      context,
      track,
      existing: request,
    );
    if (!mounted || !context.mounted || selection == null) return false;
    final api = ref.read(tracksApiServiceProvider);
    final success = await api.updatePhotoWish(
      request.id,
      selection.wish ?? '',
      reportType: selection.reportType,
      expectedPriceUsd: selection.expectedPriceUsd,
    );
    if (!mounted || !context.mounted) return success;
    if (success) {
      setState(() => _photoRequestNotes[track.code] = selection.wish ?? '');
      _refreshTracks();
    }
    _showStyledSnackBar(
      context,
      success
          ? tr(context, ru: 'Фотоотчёт обновлён', zh: '拍照申请已更新')
          : _photoRequestError(context, api.lastPhotoRequestErrorCode),
      isError: !success,
    );
    return success;
  }

  String _photoRequestError(BuildContext context, String? code) =>
      isLoyaltyErrorCode(code)
      ? loyaltyErrorText(context, code)
      : code == 'photo_report_price_changed'
      ? tr(
          context,
          ru: 'Стоимость изменилась. Откройте выбор фотоотчёта заново и подтвердите новую цену.',
          zh: '价格已变更，请重新选择拍照报告并确认新价格。',
        )
      : tr(
          context,
          ru: 'Не удалось сохранить фотоотчёт. Обновите список и повторите.',
          zh: '无法保存拍照申请，请刷新列表后重试。',
        );

  Future<void> _cancelQuestion(TrackItem track) async {
    final confirmed = await _confirmAction(
      context,
      title: 'Отменить вопрос?',
      message: 'Вопрос будет отменён.',
    );

    if (!confirmed) return;
    if (!mounted) return;

    // Если есть активный вопрос из API
    final activeQuestion = track.activeQuestion;
    if (activeQuestion != null) {
      final apiService = ref.read(tracksApiServiceProvider);
      final success = await apiService.cancelTrackQuestion(activeQuestion.id);

      if (success) {
        if (!mounted) return;
        setState(() {
          _askedQuestions.remove(track.code);
          _questionStatus.remove(track.code);
          _questionAnswers.remove(track.code);
          _questionCreatedAt.remove(track.code);
          _questionUpdatedAt.remove(track.code);
        });
        _showStyledSnackBar(context, 'Вопрос отменён');
      } else {
        if (!mounted) return;
        _showStyledSnackBar(context, 'Ошибка отмены вопроса', isError: true);
      }
    } else {
      if (!mounted) return;
      // Удаляем из локального state
      setState(() {
        _askedQuestions.remove(track.code);
        _questionStatus.remove(track.code);
        _questionAnswers.remove(track.code);
        _questionCreatedAt.remove(track.code);
        _questionUpdatedAt.remove(track.code);
      });
      _showStyledSnackBar(context, 'Вопрос отменён');
    }
  }

  Future<void> _deleteTrack(TrackItem track) async {
    final confirmed = await _confirmAction(
      context,
      title: 'Удалить трек?',
      message: 'Трек ${track.code} будет удалён. Это действие нельзя отменить.',
    );
    if (!confirmed || !mounted) return;

    final apiService = ref.read(tracksApiServiceProvider);
    final trackId = track.id;
    if (trackId == null) return;

    final success = await apiService.deleteTrack(trackId);
    if (!mounted) return;

    if (success) {
      // Оптимистично убираем из UI сразу, не ждём перезагрузки
      final clientCode = ref.read(activeClientCodeProvider);
      if (clientCode != null) {
        ref
            .read(paginatedTracksProvider(clientCode))
            .removeTrackOptimistically(trackId);
      }
      _refreshTracks();
      _showStyledSnackBar(context, 'Трек ${track.code} удалён');
    } else {
      _showStyledSnackBar(context, 'Ошибка удаления трека', isError: true);
    }
  }

  Future<void> _showReturnSheet(BuildContext context, TrackItem track) async {
    final returnCodeController = TextEditingController();
    try {
      final result = await showBlurredModalBottomSheet<bool>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.22),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              final canSubmit = returnCodeController.text.trim().isNotEmpty;

              return _TrackSheetSurface(
                icon: Icons.assignment_return_rounded,
                title: 'Возврат товара',
                subtitle: 'Оформим возврат по треку ${track.code}',
                keyboardAware: true,
                footer: _TrackSheetPrimaryButton(
                  label: 'Оформить возврат',
                  icon: Icons.assignment_return_rounded,
                  onTap: canSubmit
                      ? () => Navigator.of(sheetContext).pop(true)
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TrackSheetNoticeCard(
                      icon: Icons.schedule_rounded,
                      text:
                          'Возврат можно оформить в окно с 13:00 до 15:00 по Китаю. Склад получит задачу и код возврата.',
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(height: 12),
                    _TrackFilterSectionCard(
                      icon: Icons.qr_code_2_rounded,
                      title: 'Код возврата',
                      child: AppGradientInputFrame(
                        child: TextField(
                          controller: returnCodeController,
                          textCapitalization: TextCapitalization.characters,
                          onChanged: (_) => setSheetState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'Введите код возврата…',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF999999),
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _TrackSheetMetaCard(
                      icon: Icons.storefront_rounded,
                      title: 'Где взять код',
                      value:
                          'Код возврата можно найти в приложении продавца: Taobao, 1688 или другом магазине.',
                      valueMaxLines: 3,
                    ),
                  ],
                ),
              );
            },
          );
        },
      );

      if (result != true || !context.mounted) return;

      final returnCode = returnCodeController.text.trim();
      if (returnCode.isEmpty) {
        _showStyledSnackBar(context, 'Введите код возврата', isError: true);
        return;
      }

      final trackId = track.id;
      if (trackId == null) return;

      setState(() {
        _returnRequestedTracks.add(track.code);
        _selectedTracks.remove(track.code);
        if (_selectedTracks.isEmpty) _selectedStatus = null;
      });

      final apiService = ref.read(tracksApiServiceProvider);
      final success = await apiService.createTrackReturn(
        trackId: trackId,
        returnCode: returnCode,
      );

      if (!context.mounted) return;

      if (success) {
        _refreshTracks();
        _showStyledSnackBar(
          context,
          'Возврат оформлен. Склад получит уведомление.',
        );
      } else {
        setState(() => _returnRequestedTracks.remove(track.code));
        _showStyledSnackBar(
          context,
          'Ошибка оформления возврата',
          isError: true,
        );
      }
    } finally {
      _disposeAfterBottomSheetClose([returnCodeController.dispose]);
    }
  }

  Future<void> _showCommentSheet(BuildContext context, TrackItem track) async {
    final existing = _overrideComments[track.code] ?? track.comment ?? '';
    final controller = TextEditingController(text: existing);
    var saving = false;
    await showBlurredModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return _TrackSheetSurface(
            icon: Icons.sticky_note_2_rounded,
            title: 'Заметка',
            subtitle: 'Личный комментарий к треку ${track.code}',
            keyboardAware: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TrackFilterSectionCard(
                  icon: Icons.edit_note_rounded,
                  title: 'Текст заметки',
                  child: AppGradientInputFrame(
                    child: TextField(
                      controller: controller,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Добавьте или отредактируйте заметку…',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF999999),
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _TrackSheetPrimaryButton(
                  label: saving
                      ? tr(context, ru: 'Сохраняем…', zh: '正在保存…')
                      : tr(context, ru: 'Сохранить заметку', zh: '保存备注'),
                  icon: Icons.check_rounded,
                  onTap: saving
                      ? null
                      : () async {
                          setSheetState(() => saving = true);
                          final saved = await _saveTrackComment(
                            context,
                            track,
                            controller.text.trim(),
                          );
                          if (!sheetContext.mounted) return;
                          if (saved) {
                            Navigator.of(sheetContext).pop();
                          } else {
                            setSheetState(() => saving = false);
                          }
                        },
                ),
              ],
            ),
          );
        },
      ),
    );
    _disposeAfterBottomSheetClose([controller.dispose]);
  }

  int? _clientCodeIdForTrack(TrackItem track, dynamic auth) {
    if (track.clientCodeId != null) return track.clientCodeId;
    final codes = auth.clientData?['codes'] as List<dynamic>?;
    if (codes == null || codes.isEmpty) return null;
    final firstCode = codes.first;
    return firstCode is Map<String, dynamic> ? firstCode['id'] as int? : null;
  }

  Future<bool> _requestPhotoInline(
    BuildContext context,
    TrackItem track,
    String wish,
  ) async {
    if (!track.isPending) return false;
    final selection = await _selectPhotoReport(context, track);
    if (!mounted || !context.mounted || selection == null) return false;
    wish = selection.wish ?? '';
    final auth = ref.read(authStateProvider);
    final clientId = auth.clientId;
    final clientCodeId = _clientCodeIdForTrack(track, auth);
    if (track.id == null || clientId == null) {
      if (context.mounted) {
        _showStyledSnackBar(
          context,
          'Ошибка: нет данных для запроса',
          isError: true,
        );
      }
      return false;
    }
    final now = DateTime.now();
    setState(() {
      _requestedPhotoReports.add(track.code);
      _photoRequestNotes[track.code] = wish;
      _photoRequestCreatedAt[track.code] = now;
      _photoRequestUpdatedAt[track.code] = now;
    });
    final success = await ref
        .read(tracksApiServiceProvider)
        .createPhotoRequest(
          clientId: clientId,
          clientCodeId: clientCodeId,
          trackId: track.id!,
          trackNumber: track.code,
          wish: wish.isEmpty ? null : wish,
          reportType: selection.reportType,
          expectedPriceUsd: selection.expectedPriceUsd,
          loyaltyRewardType: selection.loyaltyRewardType,
        );
    if (!context.mounted) return success;
    if (success) {
      _showStyledSnackBar(context, 'Запрос фотоотчёта отправлен');
      _refreshTracks();
    } else {
      setState(() {
        _requestedPhotoReports.remove(track.code);
        _photoRequestNotes.remove(track.code);
        _photoRequestCreatedAt.remove(track.code);
        _photoRequestUpdatedAt.remove(track.code);
      });
      _showStyledSnackBar(
        context,
        _photoRequestError(
          context,
          ref.read(tracksApiServiceProvider).lastPhotoRequestErrorCode,
        ),
        isError: true,
      );
    }
    return success;
  }

  Future<bool> _askQuestionInline(BuildContext context, TrackItem track) async {
    final auth = ref.read(authStateProvider);
    final clientId = auth.clientId;
    final clientCodeId = _clientCodeIdForTrack(track, auth);
    if (track.id == null || clientId == null) {
      if (context.mounted) {
        _showStyledSnackBar(
          context,
          'Ошибка: нет данных для запроса',
          isError: true,
        );
      }
      return false;
    }
    final now = DateTime.now();
    final wasEmpty = (_askedQuestions[track.code] ?? '').trim().isEmpty;
    setState(() {
      _askedQuestions[track.code] = _unknownTrackQuestionText;
      if (wasEmpty) _questionCreatedAt[track.code] = now;
      _questionUpdatedAt[track.code] = now;
    });
    final success = await ref
        .read(tracksApiServiceProvider)
        .createTrackQuestion(
          clientId: clientId,
          clientCodeId: clientCodeId,
          trackId: track.id!,
          trackNumber: track.code,
          question: _unknownTrackQuestionText,
          questionType: _unknownTrackQuestionType,
        );
    if (!context.mounted) return success;
    if (success) {
      _showStyledSnackBar(context, 'Вопрос отправлен');
      _refreshTracks();
    } else {
      setState(() {
        if (wasEmpty) {
          _askedQuestions.remove(track.code);
          _questionCreatedAt.remove(track.code);
        }
        _questionUpdatedAt.remove(track.code);
      });
      _showStyledSnackBar(context, 'Ошибка отправки вопроса', isError: true);
    }
    return success;
  }

  Future<bool> _requestReturnInline(
    BuildContext context,
    TrackItem track,
    String returnCode,
  ) async {
    if (track.id == null || returnCode.trim().isEmpty) return false;
    setState(() {
      _returnRequestedTracks.add(track.code);
      _selectedTracks.remove(track.code);
      if (_selectedTracks.isEmpty) _selectedStatus = null;
    });
    final success = await ref
        .read(tracksApiServiceProvider)
        .createTrackReturn(trackId: track.id!, returnCode: returnCode.trim());
    if (!context.mounted) return success;
    if (success) {
      _refreshTracks();
      _showStyledSnackBar(
        context,
        'Возврат оформлен. Склад получит уведомление.',
      );
    } else {
      setState(() => _returnRequestedTracks.remove(track.code));
      _showStyledSnackBar(context, 'Ошибка оформления возврата', isError: true);
    }
    return success;
  }

  Future<bool> _confirmCompletedReturn(
    BuildContext context,
    TrackItem track,
  ) async {
    if (track.id == null) return false;
    final confirmed = await _confirmAction(
      context,
      title: tr(
        context,
        ru: 'Подтвердить выполненный возврат?',
        zh: '确认退货已完成？',
      ),
      message: tr(
        context,
        ru: 'После подтверждения трек ${track.code} будет удалён из системы без возможности восстановления.',
        zh: '确认后，运单号 ${track.code} 将从系统中删除，且无法恢复。',
      ),
      cancelLabel: tr(context, ru: 'Отмена', zh: '取消'),
      confirmLabel: tr(context, ru: 'Подтвердить и удалить', zh: '确认并删除'),
      destructive: true,
    );
    if (!context.mounted || !confirmed) return false;

    final success = await ref
        .read(tracksApiServiceProvider)
        .confirmCompletedTrackReturn(track.id!);
    if (!context.mounted) return success;
    if (success) {
      _currentNotifier?.removeTrackOptimistically(track.id!);
      setState(() {
        _returnRequestedTracks.remove(track.code);
        _selectedTracks.remove(track.code);
        if (_selectedTracks.isEmpty) _selectedStatus = null;
      });
      _refreshTracks();
      _showStyledSnackBar(
        context,
        tr(
          context,
          ru: 'Возврат подтверждён. Трек удалён.',
          zh: '退货已确认，运单号已删除。',
        ),
      );
    } else {
      _showStyledSnackBar(
        context,
        tr(context, ru: 'Не удалось подтвердить возврат', zh: '无法确认退货'),
        isError: true,
      );
    }
    return success;
  }

  Future<bool> _saveTrackComment(
    BuildContext context,
    TrackItem track,
    String comment,
  ) async {
    if (track.id == null) {
      if (context.mounted) {
        _showStyledSnackBar(
          context,
          tr(
            context,
            ru: 'Не удалось сохранить заметку. Обновите трек и повторите попытку.',
            zh: '无法保存备注，请刷新货件后重试。',
          ),
          isError: true,
        );
      }
      return false;
    }
    final success = await ref
        .read(tracksApiServiceProvider)
        .addTrackComment(trackId: track.id!, comment: comment);
    if (!mounted || !context.mounted) return success;
    if (success) setState(() => _overrideComments[track.code] = comment);
    _showStyledSnackBar(
      context,
      tr(
        context,
        ru: success
            ? 'Заметка сохранена'
            : 'Не удалось сохранить заметку. Текст остался в форме.',
        zh: success ? '备注已保存' : '无法保存备注，文字已保留在表单中。',
      ),
      isError: !success,
    );
    return success;
  }

  Future<void> _showGroupCommentSheet(
    BuildContext context,
    TrackAssembly assembly,
  ) async {
    final existing =
        _groupComments[assembly.id.toString()] ?? assembly.comment ?? '';
    final controller = TextEditingController(text: existing);
    var saving = false;
    await showBlurredModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .22),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> save() async {
            if (saving) return;
            setSheetState(() => saving = true);
            var success = false;
            try {
              success = await ref
                  .read(assembliesApiServiceProvider)
                  .addAssemblyComment(
                    assemblyId: assembly.id,
                    comment: controller.text.trim(),
                  );
            } catch (_) {
              success = false;
            }
            if (!sheetContext.mounted) return;
            if (success) {
              if (mounted) {
                setState(
                  () => _groupComments[assembly.id.toString()] = controller.text
                      .trim(),
                );
              }
              _showStyledSnackBar(
                sheetContext,
                tr(
                  sheetContext,
                  ru: 'Заметка по сборке сохранена',
                  zh: '集运单备注已保存',
                ),
              );
              Navigator.of(sheetContext).pop();
            } else {
              setSheetState(() => saving = false);
              _showStyledSnackBar(
                sheetContext,
                tr(
                  sheetContext,
                  ru: 'Не удалось сохранить заметку. Текст остался в форме — повторите сохранение.',
                  zh: '无法保存备注，文字已保留在表单中，请重试。',
                ),
                isError: true,
              );
            }
          }

          return UnsavedFormGuard(
            controllers: [controller],
            isBusy: saving,
            child: AbsorbPointer(
              absorbing: saving,
              child: _TrackSheetSurface(
                icon: Icons.sticky_note_2_rounded,
                title: tr(sheetContext, ru: 'Заметка по сборке', zh: '集运单备注'),
                subtitle: tr(
                  sheetContext,
                  ru: 'Комментарий к сборке ${assembly.number}',
                  zh: '集运单 ${assembly.number} 的备注',
                ),
                keyboardAware: true,
                footer: Row(
                  children: [
                    Expanded(
                      child: _TrackSheetSecondaryButton(
                        label: tr(sheetContext, ru: 'Отмена', zh: '取消'),
                        onTap: () {
                          if (!saving) Navigator.of(sheetContext).maybePop();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TrackSheetPrimaryButton(
                        label: tr(
                          sheetContext,
                          ru: saving ? 'Сохраняем…' : 'Сохранить заметку',
                          zh: saving ? '正在保存…' : '保存备注',
                        ),
                        icon: Icons.check_rounded,
                        onTap: saving ? null : save,
                      ),
                    ),
                  ],
                ),
                child: _TrackFilterSectionCard(
                  icon: Icons.edit_note_rounded,
                  title: tr(sheetContext, ru: 'Текст заметки', zh: '备注内容'),
                  child: AppGradientInputFrame(
                    child: TextField(
                      controller: controller,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: tr(
                          sheetContext,
                          ru: 'Добавьте или отредактируйте заметку по сборке…',
                          zh: '添加或编辑集运单备注…',
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    _disposeAfterBottomSheetClose([controller.dispose]);
  }

  Future<void> _showGroupQuestionSheet(
    BuildContext context,
    TrackAssembly assembly,
  ) async {
    final controller = TextEditingController(
      text: _groupQuestions[assembly.id.toString()] ?? '',
    );
    final result = await showBlurredModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (ctx) {
        return _TrackSheetSurface(
          icon: Icons.help_rounded,
          title: 'Вопрос по сборке',
          subtitle: 'Склад ответит по сборке ${assembly.number}',
          keyboardAware: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TrackFilterSectionCard(
                icon: Icons.edit_note_rounded,
                title: 'Текст вопроса',
                child: AppGradientInputFrame(
                  child: TextField(
                    controller: controller,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Опишите ваш вопрос по сборке…',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF999999),
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _TrackSheetPrimaryButton(
                label: 'Задать вопрос',
                icon: Icons.send_rounded,
                onTap: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        );
      },
    );
    if (result == true) {
      if (!context.mounted) return;
      final now = DateTime.now();
      setState(() {
        final wasEmpty = (_groupQuestions[assembly.id.toString()] ?? '')
            .trim()
            .isEmpty;
        _groupQuestions[assembly.id.toString()] = controller.text.trim();
        if (wasEmpty) {
          _groupQuestionCreatedAt[assembly.id.toString()] = now;
        }
        _groupQuestionUpdatedAt[assembly.id.toString()] = now;
      });
      _showStyledSnackBar(context, 'Вопрос по сборке отправлен');
    }
  }

  Future<void> _showDeliverySheet(
    BuildContext context,
    TrackAssembly assembly,
  ) async {
    if (!assembly.canEditDelivery) {
      _showStyledSnackBar(
        context,
        tr(
          context,
          ru: 'Доставленная сборка доступна только для просмотра',
          zh: '已送达的集运单仅可查看',
        ),
        isError: true,
      );
      return;
    }

    // Текущий метод доставки
    String? selectedMethod = assembly.deliveryMethod;
    final nameController = TextEditingController(
      text: assembly.recipientName ?? '',
    );
    final cityController = TextEditingController(
      text: assembly.recipientCity ?? '',
    );
    final transportCompanyController = TextEditingController(
      text: assembly.transportCompanyName ?? '',
    );

    final phoneController = PhoneController(
      initialValue:
          PhoneInputField.parse(assembly.recipientPhone) ??
          const PhoneNumber(isoCode: IsoCode.RU, nsn: ''),
    );

    var savingDelivery = false;
    await showBlurredModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final selectedDeliveryLabel = selectedMethod == 'self_pickup'
                ? tr(context, ru: 'Самовывоз', zh: '自提')
                : selectedMethod == 'transport_company'
                ? tr(context, ru: 'Транспортная компания', zh: '物流公司')
                : tr(context, ru: 'Не выбран', zh: '未选择');

            Future<void> submit() async {
              if (savingDelivery) return;
              final method = selectedMethod;
              if (method == null) return;

              // Валидация для ТК
              if (method == 'transport_company') {
                if (nameController.text.trim().isEmpty) {
                  _showStyledSnackBar(
                    sheetContext,
                    tr(context, ru: 'Укажите ФИО получателя', zh: '请输入收货人姓名'),
                    isError: true,
                  );
                  return;
                }
                final phone = phoneController.value;
                if (phone.nsn.trim().isEmpty) {
                  _showStyledSnackBar(
                    sheetContext,
                    tr(
                      context,
                      ru: 'Укажите телефон получателя',
                      zh: '请输入收货人电话',
                    ),
                    isError: true,
                  );
                  return;
                }
                if (!phone.isValid()) {
                  _showStyledSnackBar(
                    sheetContext,
                    tr(
                      context,
                      ru: 'Введите корректный номер телефона',
                      zh: '请输入有效的电话号码',
                    ),
                    isError: true,
                  );
                  return;
                }
                if (cityController.text.trim().isEmpty) {
                  _showStyledSnackBar(
                    sheetContext,
                    tr(context, ru: 'Укажите город получателя', zh: '请输入收货城市'),
                    isError: true,
                  );
                  return;
                }
              }

              setSheetState(() => savingDelivery = true);
              final saved = await _saveAssemblyDeliveryInline(
                sheetContext,
                assembly,
                deliveryMethod: method,
                recipientName: nameController.text.trim(),
                recipientPhone: phoneController.value.international,
                recipientCity: cityController.text.trim(),
                transportCompanyName: transportCompanyController.text.trim(),
              );
              if (!sheetContext.mounted) return;
              if (saved) {
                Navigator.of(sheetContext).pop();
              } else {
                setSheetState(() => savingDelivery = false);
              }
            }

            return _TrackSheetSurface(
              icon: Icons.local_shipping_rounded,
              title: tr(context, ru: 'Способ получения', zh: '收货方式'),
              subtitle: tr(
                context,
                ru: 'Настройте выдачу сборки ${assembly.number}',
                zh: '设置集运单 ${assembly.number} 的收货方式',
              ),
              keyboardAware: true,
              pinnedChild: _TrackSheetMetaCard(
                icon: Icons.inventory_2_rounded,
                title: tr(context, ru: 'Текущий выбор', zh: '当前选择'),
                value: selectedDeliveryLabel,
              ),
              footer: Row(
                children: [
                  Expanded(
                    child: _TrackSheetSecondaryButton(
                      label: tr(context, ru: 'Отмена', zh: '取消'),
                      onTap: () {
                        if (!savingDelivery) Navigator.of(sheetContext).pop();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TrackSheetPrimaryButton(
                      label: savingDelivery
                          ? tr(context, ru: 'Сохраняем…', zh: '正在保存…')
                          : tr(context, ru: 'Сохранить', zh: '保存'),
                      icon: Icons.check_rounded,
                      onTap: selectedMethod == null || savingDelivery
                          ? null
                          : submit,
                    ),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TrackFilterSectionCard(
                    icon: Icons.delivery_dining_rounded,
                    title: tr(context, ru: 'Вариант получения', zh: '收货方式'),
                    child: Column(
                      children: [
                        _DeliveryOptionCard(
                          title: tr(context, ru: 'Самовывоз', zh: '自提'),
                          subtitle: tr(
                            context,
                            ru: 'Забрать груз на терминале склада',
                            zh: '前往仓库站点提货',
                          ),
                          icon: Icons.storefront_rounded,
                          isSelected: selectedMethod == 'self_pickup',
                          onTap: () => setSheetState(
                            () => selectedMethod = 'self_pickup',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _DeliveryOptionCard(
                          title: tr(
                            context,
                            ru: 'Транспортная компания',
                            zh: '物流公司',
                          ),
                          subtitle: tr(
                            context,
                            ru: 'Передадим груз выбранной ТК',
                            zh: '将货物交给您选择的物流公司',
                          ),
                          icon: Icons.local_shipping_rounded,
                          isSelected: selectedMethod == 'transport_company',
                          onTap: () => setSheetState(
                            () => selectedMethod = 'transport_company',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selectedMethod == 'self_pickup') ...[
                    const SizedBox(height: 12),
                    _TrackSheetNoticeCard(
                      icon: Icons.warning_amber_rounded,
                      text: tr(
                        context,
                        ru: 'Доступ на терминал платный. Для уточнения условий свяжитесь с поддержкой.',
                        zh: '进入站点需付费，详情请联系客服。',
                      ),
                      color: Colors.amber.shade800,
                    ),
                    const SizedBox(height: 12),
                    _TrackSheetMetaCard(
                      icon: Icons.support_agent_rounded,
                      title: tr(context, ru: 'После сохранения', zh: '保存之后'),
                      value: tr(
                        context,
                        ru: 'Поддержка увидит выбранный способ и поможет согласовать получение на терминале.',
                        zh: '客服会看到您选择的方式，并协助安排站点提货。',
                      ),
                      valueMaxLines: 3,
                    ),
                  ],
                  if (selectedMethod == 'transport_company') ...[
                    const SizedBox(height: 12),
                    _TrackSheetNoticeCard(
                      icon: Icons.info_outline_rounded,
                      text: tr(
                        context,
                        ru: 'Заполните данные получателя. Склад использует их для передачи груза транспортной компании.',
                        zh: '请填写收货人信息，仓库将据此向物流公司交货。',
                      ),
                      color: context.brandPrimary,
                    ),
                    const SizedBox(height: 12),
                    _TrackFilterSectionCard(
                      icon: Icons.apartment_rounded,
                      title: tr(
                        context,
                        ru: 'Транспортная компания',
                        zh: '物流公司',
                      ),
                      child: _outlinedInput(
                        context,
                        transportCompanyController,
                        hint: tr(
                          context,
                          ru: 'Название ТК (СДЭК, ПЭК, и т.д.)',
                          zh: '物流公司名称（如СДЭК、ПЭК等）',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _TrackFilterSectionCard(
                      icon: Icons.person_rounded,
                      title: tr(context, ru: 'Данные получателя', zh: '收货人信息'),
                      child: Column(
                        children: [
                          _outlinedInput(
                            context,
                            nameController,
                            hint: tr(
                              context,
                              ru: 'ФИО получателя',
                              zh: '收货人姓名',
                            ),
                          ),
                          const SizedBox(height: 10),
                          PhoneInputField(
                            controller: phoneController,
                            gradientFrame: true,
                            isRequired: true,
                            hintText: tr(
                              context,
                              ru: 'Телефон получателя',
                              zh: '收货人电话',
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 10),
                          _outlinedInput(
                            context,
                            cityController,
                            hint: tr(context, ru: 'Город', zh: '城市'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );

    _disposeAfterBottomSheetClose([
      nameController.dispose,
      cityController.dispose,
      transportCompanyController.dispose,
      phoneController.dispose,
    ]);
  }

  Future<bool> _saveAssemblyDeliveryInline(
    BuildContext context,
    TrackAssembly assembly, {
    required String deliveryMethod,
    String? recipientName,
    String? recipientPhone,
    String? recipientCity,
    String? transportCompanyName,
  }) async {
    if (!assembly.canEditDelivery) {
      _showStyledSnackBar(
        context,
        tr(
          context,
          ru: 'Нельзя изменить способ получения доставленной сборки',
          zh: '已送达的集运单无法修改收货方式',
        ),
        isError: true,
      );
      return false;
    }

    final success = await ref
        .read(assembliesApiServiceProvider)
        .updateAssemblyDelivery(
          assemblyId: assembly.id,
          deliveryMethod: deliveryMethod,
          recipientName: recipientName,
          recipientPhone: recipientPhone,
          recipientCity: recipientCity,
          transportCompanyName: transportCompanyName,
        );
    if (!context.mounted) return success;
    if (success) {
      final methodLabel = deliveryMethod == 'self_pickup'
          ? tr(context, ru: 'Самовывоз', zh: '自提')
          : tr(context, ru: 'Транспортная компания', zh: '物流公司');
      _showStyledSnackBar(
        context,
        tr(
          context,
          ru: 'Способ получения: $methodLabel',
          zh: '收货方式：$methodLabel',
        ),
      );
      _refreshTracks();
    } else {
      _showStyledSnackBar(
        context,
        tr(context, ru: 'Ошибка сохранения способа получения', zh: '无法保存收货方式'),
        isError: true,
      );
    }
    return success;
  }

  Future<bool> _confirmAssemblyReceipt(
    BuildContext context,
    TrackAssembly assembly,
  ) async {
    final confirmed = await _confirmAction(
      context,
      title: tr(context, ru: 'Подтвердить получение?', zh: '确认收货？'),
      message: tr(
        context,
        ru: 'Вы получили сборку ${assembly.number}? После подтверждения статус изменится на «Доставлена».',
        zh: '您已收到集运单 ${assembly.number} 吗？确认后状态将更改为“已送达”。',
      ),
      cancelLabel: tr(context, ru: 'Отмена', zh: '取消'),
      confirmLabel: tr(context, ru: 'Подтвердить получение', zh: '确认收货'),
    );
    if (!context.mounted || !confirmed) return false;

    final success = await ref
        .read(assembliesApiServiceProvider)
        .confirmAssemblyReceipt(assembly.id);
    if (!context.mounted) return success;
    if (success) {
      _refreshTracks();
      _showStyledSnackBar(
        context,
        tr(context, ru: 'Получение подтверждено', zh: '已确认收货'),
      );
    } else {
      _showStyledSnackBar(
        context,
        tr(context, ru: 'Не удалось подтвердить получение', zh: '无法确认收货'),
        isError: true,
      );
    }
    return success;
  }

  Future<void> _showCreateGroupSheet(BuildContext context) async {
    AnalyticsService.trackFunnel(
      WorkflowAction.assemblyCreate,
      WorkflowStage.viewed,
    );
    final authScope = ref.read(authProvider);
    final scope = jsonEncode([
      authScope.userDomain,
      authScope.clientId,
      ref.read(activeClientCodeProvider),
      ...(_selectedTracks.toList()..sort()),
    ]);
    final draft = scope == _assemblyDraftScope ? _assemblyDraft : null;
    final selectedPackingIds = <int>{...?draft?.packagingIds};
    bool hasFragileGoods = draft?.fragile ?? false;
    String? placePreference = draft?.placePreference;
    String selectedInsurance = draft?.insured == true ? 'yes' : 'no';
    String? insuranceAmount = draft?.insuranceAmount;
    String goodsDescription = draft?.goodsDescription ?? '';

    ref.invalidate(tariffsProvider);
    ref.invalidate(packagingTypesProvider);
    late List<Tariff> tariffs;
    late List<PackagingType> packagingTypes;
    try {
      tariffs = await ref.read(tariffsProvider.future);
      if (!context.mounted) return;
      packagingTypes = await ref.read(packagingTypesProvider.future);
    } catch (_) {
      if (!context.mounted) return;
      _showStyledSnackBar(
        context,
        tr(
          context,
          ru: 'Не удалось загрузить тарифы или упаковку. Проверьте соединение и откройте форму снова.',
          zh: '无法加载运价或包装，请检查网络后重新打开表单。',
        ),
        isError: true,
      );
      return;
    }
    if (!context.mounted) return;

    // Создаём контроллер ДО StatefulBuilder чтобы не терять фокус
    final insuranceAmountController = TextEditingController(
      text: insuranceAmount,
    );
    final goodsDescriptionController = TextEditingController(
      text: goodsDescription,
    );
    final createAssemblyScrollController = ScrollController();
    int currentStep = draft?.step.clamp(0, 3).toInt() ?? 0;

    // Выбираем первый тариф по умолчанию
    Tariff? selectedTariff =
        tariffs.where((t) => t.id == draft?.tariffId).firstOrNull ??
        (tariffs.length == 1 ? tariffs.first : null);

    if (!context.mounted) return;

    bool savingAssembly = false;
    Future<bool> submitAssembly() async {
      final assemblyGoodsDescription = goodsDescriptionController.text.trim();

      if (!context.mounted) return false;
      // Получаем данные для API
      final auth = ref.read(authStateProvider);
      final clientCode = ref.read(activeClientCodeProvider);
      if (clientCode == null) {
        _showStyledSnackBar(
          context,
          tr(context, ru: 'Ошибка: код клиента не найден', zh: '未找到客户代码'),
          isError: true,
        );
        return false;
      }

      final clientId = auth.clientId;

      if (clientId == null) {
        _showStyledSnackBar(
          context,
          tr(context, ru: 'Ошибка: нет данных клиента', zh: '客户信息不可用'),
          isError: true,
        );
        return false;
      }

      // Ensure all pages are loaded so every selected track code can be resolved to an ID
      final notifier = ref.read(paginatedTracksProvider(clientCode));
      if (notifier.state.hasMore) {
        // Показываем индикатор загрузки
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator()),
          );
        }
        var iterations = 0;
        const maxIterations = 100; // Предохранитель от бесконечного цикла
        while (notifier.state.hasMore &&
            !notifier.state.isLoading &&
            iterations < maxIterations) {
          await notifier.loadMore(pageSize: 200);
          iterations++;
          if (!context.mounted) return false;
          if (notifier.state.error != null) break;
        }
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true).pop(); // Убираем индикатор
        }
      }
      if (!context.mounted) return false;
      if (notifier.state.hasMore || notifier.state.error != null) {
        _showStyledSnackBar(
          context,
          tr(
            context,
            ru: 'Не удалось проверить все выбранные треки. Настройки сборки сохранены, повторите отправку.',
            zh: '无法核对全部已选运单，打包设置已保留，请重试。',
          ),
          isError: true,
        );
        return false;
      }
      final tracks = notifier.state.tracks;

      final selectedTracks = tracks
          .where((t) => _selectedTracks.contains(t.code) && t.id != null)
          .toList();

      if (selectedTracks.length != _selectedTracks.length ||
          selectedTracks.isEmpty) {
        _showStyledSnackBar(
          context,
          tr(
            context,
            ru: 'Не удалось проверить все выбранные треки. Обновите список и повторите попытку.',
            zh: '无法核对全部已选运单，请刷新列表后重试。',
          ),
          isError: true,
        );
        return false;
      }
      if (selectedTariff?.requiresCompleteProductInfo == true) {
        final issues = selectedTracks
            .map((track) => productInfoCompleteness(track.allProductInfos))
            .where((issue) => issue != ProductInfoCompleteness.complete)
            .toList();
        if (issues.isNotEmpty ||
            selectedTracks.length != _selectedTracks.length) {
          _showStyledSnackBar(
            context,
            _completeProductInfoMessage(
              context,
              issues.contains(ProductInfoCompleteness.missingNameOrQuantity) ||
                  selectedTracks.length != _selectedTracks.length,
            ),
            isError: true,
          );
          return false;
        }
      }

      final blockedSelectedTracks = selectedTracks
          .where(
            (track) =>
                !_canSelectTrackForAssembly(track, _returnRequestedTracks),
          )
          .toList();
      if (blockedSelectedTracks.isNotEmpty) {
        setState(() {
          _selectedTracks.removeAll(
            blockedSelectedTracks.map((track) => track.code),
          );
          if (_selectedTracks.isEmpty) _selectedStatus = null;
        });
        final hint = _assemblySelectionHint(
          context,
          blockedSelectedTracks.first,
          _returnRequestedTracks,
        );
        _showStyledSnackBar(
          context,
          hint ??
              tr(
                context,
                ru: 'Часть треков больше нельзя добавить в сборку',
                zh: '部分运单已无法加入集运单',
              ),
          isError: true,
        );
        return false;
      }

      final selectedTrackIds = selectedTracks.map((t) => t.id!).toList();

      // Фотоотчёты блокируются серверной проверкой выше. Вопросы можно отменить.
      final tracksWithActiveTasks = selectedTracks
          .where((t) => t.activeQuestion?.isActive == true)
          .toList();

      if (tracksWithActiveTasks.isNotEmpty) {
        if (!context.mounted) return false;
        final proceed = await showBlurredModalBottomSheet<bool>(
          context: context,
          useRootNavigator: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.22),
          builder: (sheetCtx) {
            return _TrackSheetSurface(
              icon: Icons.task_alt_rounded,
              title: tr(context, ru: 'Незавершённые задачи', zh: '未完成的任务'),
              subtitle: tr(
                context,
                ru: 'Перед созданием сборки нужно подтвердить действие',
                zh: '创建集运单前请确认此操作',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TrackSheetNoticeCard(
                    icon: Icons.info_outline_rounded,
                    text: tr(
                      context,
                      ru: 'Есть треки (${tracksWithActiveTasks.length} шт.) с неотвеченными вопросами. Если создать сборку, эти вопросы будут отменены.',
                      zh: '有 ${tracksWithActiveTasks.length} 个运单存在未回答的问题。创建打包单将取消这些问题。',
                    ),
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _TrackSheetSecondaryButton(
                          label: tr(context, ru: 'Отменить', zh: '取消'),
                          onTap: () => Navigator.of(sheetCtx).pop(false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TrackSheetPrimaryButton(
                          label: tr(context, ru: 'Создать', zh: '创建'),
                          icon: Icons.inventory_2_rounded,
                          onTap: () => Navigator.of(sheetCtx).pop(true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );

        if (proceed != true) return false;
        if (!context.mounted) return false;

        // The server cancels questions atomically with successful creation.
      }

      final tariffRequiresProductInfo =
          selectedTariff?.requiresProductInfo == true;
      final tracksWithoutProductInfo = tariffRequiresProductInfo
          ? selectedTracks.where((t) {
              final apiProductInfo = t.productInfo;
              final localProductInfo = _productInfos[t.code];
              final productInfoName =
                  apiProductInfo?.name ?? localProductInfo?.name ?? '';
              final productInfoQuantity =
                  apiProductInfo?.quantity ?? localProductInfo?.quantity;
              final productInfoImages =
                  (localProductInfo?.images.isNotEmpty == true) ||
                  (apiProductInfo?.imageUrl?.isNotEmpty == true);
              return productInfoName.trim().isEmpty &&
                  productInfoQuantity == null &&
                  !productInfoImages;
            }).toList()
          : <TrackItem>[];
      final shouldUseAssemblyGoodsDescription =
          tariffRequiresProductInfo && tracksWithoutProductInfo.isNotEmpty;

      if (shouldUseAssemblyGoodsDescription &&
          assemblyGoodsDescription.isEmpty) {
        if (!context.mounted) return false;
        await showBlurredModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.22),
          isScrollControlled: true,
          builder: (sheetCtx) {
            return _TrackSheetSurface(
              icon: Icons.assignment_outlined,
              title: tr(context, ru: 'О товаре', zh: '商品信息'),
              subtitle: tr(
                context,
                ru: 'Заполните описание товаров',
                zh: '请填写商品描述',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TrackSheetNoticeCard(
                    icon: Icons.info_outline_rounded,
                    text: tr(
                      context,
                      ru: 'В выбранном тарифе нужны данные о товаре. Не заполнены данные в ${tracksWithoutProductInfo.length} треках.',
                      zh: '所选运价要求填写商品信息，${tracksWithoutProductInfo.length} 个运单尚未填写。',
                    ),
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(height: 12),
                  _TrackFilterSectionCard(
                    icon: Icons.local_shipping_rounded,
                    title: tr(context, ru: 'Треки без данных', zh: '缺少信息的运单'),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(sheetCtx).size.height * 0.3,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: tracksWithoutProductInfo.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final t = tracksWithoutProductInfo[i];
                          return _TrackSheetMetaCard(
                            icon: Icons.local_shipping_outlined,
                            title: tr(
                              context,
                              ru: 'Нет данных о товаре',
                              zh: '尚无商品信息',
                            ),
                            value: t.code,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _TrackSheetPrimaryButton(
                    label: tr(context, ru: 'Понятно', zh: '知道了'),
                    icon: Icons.check_rounded,
                    onTap: () => Navigator.of(sheetCtx).pop(),
                  ),
                ],
              ),
            );
          },
        );
        return false; // Прерываем создание сборки
      }

      // Создаём сборку через API
      final apiService = ref.read(assembliesApiServiceProvider);
      // Берём clientCodeId из выбранных треков, а не из dropdown (чтобы не привязать к NOCODE)
      final trackClientCodeId = selectedTracks.firstOrNull?.clientCodeId;
      final clientCodeId =
          trackClientCodeId ?? ref.read(activeClientCodeIdProvider);
      final createResult = await apiService.createAssembly(
        clientId: clientId,
        clientCodeId: clientCodeId,
        clientCode: clientCodeId == null ? clientCode : null,
        tariffId: selectedTariff?.id,
        packagingTypeIds: selectedPackingIds.toList(),
        hasFragileGoods: hasFragileGoods,
        placePreference: placePreference!,
        supportsPackagingRemovalTargets:
            selectedTariff?.supportsPackagingRemovalTargets == true,
        hasInsurance: selectedInsurance == 'yes',
        insuranceAmount: selectedInsurance == 'yes' && insuranceAmount != null
            ? double.tryParse(insuranceAmount!)
            : null,
        goodsDescription:
            shouldUseAssemblyGoodsDescription &&
                assemblyGoodsDescription.isNotEmpty
            ? assemblyGoodsDescription
            : null,
        trackIds: selectedTrackIds,
        cancelPendingQuestions: tracksWithActiveTasks.isNotEmpty,
      );

      final assembly = createResult.assembly;
      if (assembly != null) {
        _assemblyDraft = null;
        _assemblyDraftScope = null;
        if (!context.mounted) return false;
        _showStyledSnackBar(
          context,
          createResult.assemblies.length > 1
              ? tr(
                  context,
                  ru: 'Созданы сборки: ${createResult.assemblies.map((item) => item.number).join(', ')}',
                  zh: '已创建打包单：${createResult.assemblies.map((item) => item.number).join(', ')}',
                )
              : tr(
                  context,
                  ru: 'Сборка ${assembly.number} создана',
                  zh: '打包单 ${assembly.number} 已创建',
                ),
        );
        setState(() {
          _selectedTracks.clear();
          _selectedStatus = null;
        });
        // Обновляем список треков
        _refreshTracks();
        ref.invalidate(assembliesListProvider(clientCode));
        return true;
      } else {
        if (!context.mounted) return false;
        final message =
            createResult.message ??
            (createResult.errorCode == trackWarehouseArrivalCooldownCode
                ? tr(
                    context,
                    ru: 'Этот трек только поступил на склад. Отправить его можно завтра.',
                    zh: '该运单今天刚入库，明天可申请发货。',
                  )
                : tr(context, ru: 'Ошибка создания сборки', zh: '创建集运单失败'));
        _showStyledSnackBar(
          context,
          '$message\n${tr(context, ru: 'Настройки сохранены в форме. Повторите отправку.', zh: '设置已保留在表单中，请重试。')}',
          isError: true,
        );
      }
      return false;
    }

    final result = await showBlurredModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final stepTitles = [
              tr(context, ru: 'Тариф', zh: '运价'),
              tr(context, ru: 'Груз', zh: '货物'),
              tr(context, ru: 'Упаковка', zh: '包装'),
              tr(context, ru: 'Итог', zh: '确认'),
            ];
            final primaryPackagingTypes = packagingTypes
                .where((p) => p.isPrimary)
                .toList();
            final addonPackagingTypes = packagingTypes
                .where((p) => p.isAddon)
                .toList();
            final primaryPackagingIds = primaryPackagingTypes
                .map((p) => p.id)
                .toSet();
            PackagingType? selectedPrimaryPackaging;
            for (final p in primaryPackagingTypes) {
              if (selectedPackingIds.contains(p.id)) {
                selectedPrimaryPackaging = p;
                break;
              }
            }
            final hasPrimaryPackaging = selectedPrimaryPackaging != null;
            final selectedPackagingNames = [
              if (selectedPrimaryPackaging != null)
                selectedPrimaryPackaging.localizedName(isZh(context)),
              ...addonPackagingTypes
                  .where((p) => selectedPackingIds.contains(p.id))
                  .map((p) => p.localizedName(isZh(context))),
            ];
            final hasSuitableAddonPackaging = addonPackagingTypes.any(
              (p) =>
                  selectedPackingIds.contains(p.id) &&
                  p.suitableForFragileGoods,
            );
            final showFragileAddonRecommendation =
                hasFragileGoods &&
                addonPackagingTypes.isNotEmpty &&
                !hasSuitableAddonPackaging;
            final selectedUnsuitableFragilePackagingNames = packagingTypes
                .where(
                  (p) =>
                      selectedPackingIds.contains(p.id) &&
                      !p.suitableForFragileGoods,
                )
                .map((p) => p.localizedName(isZh(context)))
                .toList();
            final showFragilePackagingRisk =
                hasFragileGoods &&
                selectedUnsuitableFragilePackagingNames.isNotEmpty;

            bool trackHasProductInfo(TrackItem track) {
              final apiProductInfo = track.productInfo;
              final localProductInfo = _productInfos[track.code];
              final productInfoName =
                  apiProductInfo?.name ?? localProductInfo?.name ?? '';
              final productInfoQuantity =
                  apiProductInfo?.quantity ?? localProductInfo?.quantity;
              final productInfoImages =
                  (localProductInfo?.images.isNotEmpty == true) ||
                  (apiProductInfo?.imageUrl?.isNotEmpty == true);
              return productInfoName.trim().isNotEmpty ||
                  productInfoQuantity != null ||
                  productInfoImages;
            }

            final loadedTracks =
                _currentNotifier?.state.tracks ?? const <TrackItem>[];
            final selectedLoadedTracks = loadedTracks
                .where((track) => _selectedTracks.contains(track.code))
                .toList();
            final tracksWithoutProductInfo = selectedLoadedTracks
                .where((track) => !trackHasProductInfo(track))
                .toList();
            final completeProductInfoIssues = selectedLoadedTracks
                .map((track) => productInfoCompleteness(track.allProductInfos))
                .where((issue) => issue != ProductInfoCompleteness.complete)
                .toList();
            final completeProductInfoRequired =
                selectedTariff?.requiresCompleteProductInfo == true;
            final completeProductInfoSatisfied =
                !completeProductInfoRequired ||
                (selectedLoadedTracks.length == _selectedTracks.length &&
                    completeProductInfoIssues.isEmpty);
            final requiresAssemblyGoodsDescription =
                selectedTariff?.requiresProductInfo == true &&
                tracksWithoutProductInfo.isNotEmpty;
            final hasAssemblyGoodsDescription = goodsDescription
                .trim()
                .isNotEmpty;
            final productInfoRequirementSatisfied =
                completeProductInfoSatisfied &&
                (!requiresAssemblyGoodsDescription ||
                    hasAssemblyGoodsDescription);
            final canSubmit =
                placePreference != null &&
                hasPrimaryPackaging &&
                selectedTariff != null &&
                productInfoRequirementSatisfied &&
                (selectedInsurance == 'no' ||
                    (selectedInsurance == 'yes' &&
                        insuranceAmount?.isNotEmpty == true));
            final canContinue = switch (currentStep) {
              0 =>
                selectedTariff != null &&
                    productInfoRequirementSatisfied &&
                    (selectedInsurance == 'no' ||
                        (selectedInsurance == 'yes' &&
                            insuranceAmount?.isNotEmpty == true)),
              1 => placePreference != null,
              2 => hasPrimaryPackaging,
              _ => canSubmit,
            };

            void goToStep(int value) {
              setSheetState(() => currentStep = value.clamp(0, 3).toInt());
              if (createAssemblyScrollController.hasClients) {
                createAssemblyScrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                );
              }
            }

            Widget placePreferenceChip({
              required String value,
              required String label,
            }) {
              final selected = placePreference == value;
              final chip = ChoiceChip(
                selected: selected,
                showCheckmark: selected,
                checkmarkColor: Colors.white,
                selectedColor: context.brandPrimary,
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: selected
                      ? context.brandPrimary
                      : context.brandPrimary.withValues(alpha: 0.36),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
                labelPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                label: Text(label),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : context.brandPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
                onSelected: (_) => setSheetState(() => placePreference = value),
              );
              return TrainingTarget(
                id: 'assembly.places.$value',
                child: TrainingTarget(
                  id: selected
                      ? 'assembly.places.selected'
                      : 'assembly.places.$value.unselected',
                  child: TrainingTarget(
                    id:
                        selected ||
                            (placePreference == null &&
                                value == 'single_if_possible')
                        ? 'assembly.places'
                        : 'assembly.places.$value.option',
                    child: chip,
                  ),
                ),
              );
            }

            Widget packagingOptionTile(
              PackagingType packaging, {
              required bool selected,
              required bool primary,
            }) {
              final warning =
                  hasFragileGoods && !packaging.suitableForFragileGoods;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setSheetState(() {
                    if (primary) {
                      selectedPackingIds.removeWhere(
                        primaryPackagingIds.contains,
                      );
                      selectedPackingIds.add(packaging.id);
                      return;
                    }
                    if (selected) {
                      selectedPackingIds.remove(packaging.id);
                    } else {
                      selectedPackingIds.add(packaging.id);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected
                        ? context.brandPrimary.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? context.brandPrimary
                          : const Color(0xFFE8EAEE),
                      width: selected ? 1.2 : 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        primary
                            ? (selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked)
                            : (selected
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank),
                        color: selected ? context.brandPrimary : Colors.black45,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              packaging.localizedName(isZh(context)),
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _PackagingBadge(
                                  label: primary
                                      ? tr(
                                          context,
                                          ru: 'Основная упаковка',
                                          zh: '主要包装',
                                        )
                                      : tr(
                                          context,
                                          ru: 'Доп. защита',
                                          zh: '额外防护',
                                        ),
                                  color: primary
                                      ? context.brandPrimary
                                      : Colors.blue.shade700,
                                ),
                                if (packaging.suitableForFragileGoods)
                                  _PackagingBadge(
                                    label: tr(
                                      context,
                                      ru: 'Для хрупкого',
                                      zh: '适合易碎品',
                                    ),
                                    color: Colors.green.shade700,
                                  ),
                                if (warning)
                                  _PackagingBadge(
                                    label: tr(
                                      context,
                                      ru: 'Не для хрупкого',
                                      zh: '不适合易碎品',
                                    ),
                                    color: Colors.red.shade700,
                                  ),
                              ],
                            ),
                            if (packaging.baseCost > 0) ...[
                              const SizedBox(height: 5),
                              Text(
                                '\$${packaging.baseCost.toStringAsFixed(2)} / ${isZh(context) ? switch (packaging.unitLabel) {
                                        'шт.' || 'шт' => '件',
                                        'кг' => '公斤',
                                        'м' => '米',
                                        _ => packaging.unitLabel,
                                      } : packaging.unitLabel}',
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (warning) ...[
                              const SizedBox(height: 5),
                              Text(
                                tr(
                                  context,
                                  ru: 'Для хрупких товаров лучше выбрать более надежную упаковку.',
                                  zh: '建议为易碎品选择更可靠的包装。',
                                ),
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget tariffOptionTile(Tariff tariff, {required bool selected}) {
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setSheetState(() {
                  selectedTariff = tariff;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selected
                        ? context.brandPrimary.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? context.brandPrimary
                          : const Color(0xFFE8EAEE),
                      width: selected ? 1.2 : 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: selected ? context.brandPrimary : Colors.black45,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tariff.localizedName(isZh(context)),
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _PackagingBadge(
                                  label: tr(
                                    context,
                                    ru: 'Тариф доставки',
                                    zh: '运输运价',
                                  ),
                                  color: context.brandPrimary,
                                ),
                                if (tariff.requiresProductInfo)
                                  _PackagingBadge(
                                    label: tr(
                                      context,
                                      ru: 'Нужны данные о товаре',
                                      zh: '需要商品信息',
                                    ),
                                    color: Colors.orange.shade700,
                                  ),
                              ],
                            ),
                            if (tariff.baseCost > 0) ...[
                              const SizedBox(height: 5),
                              Text(
                                tr(
                                  context,
                                  ru: '\$${tariff.baseCost.toStringAsFixed(2)} / кг',
                                  zh: '\$${tariff.baseCost.toStringAsFixed(2)} / 公斤',
                                ),
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (tariff.requiresProductInfo) ...[
                              const SizedBox(height: 5),
                              Text(
                                tr(
                                  context,
                                  ru: 'Для этого тарифа нужно заполнить информацию о товаре по трекам.',
                                  zh: '此运价要求为每个运单填写商品信息。',
                                ),
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget buildStepIndicator() {
              return Row(
                children: [
                  for (var i = 0; i < stepTitles.length; i++) ...[
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: i <= currentStep
                              ? context.brandPrimary.withValues(
                                  alpha: i == currentStep ? 0.16 : 0.08,
                                )
                              : const Color(0xFFF1F2F4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: i == currentStep
                                ? context.brandPrimary.withValues(alpha: 0.45)
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          '${i + 1}. ${stepTitles[i]}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: i <= currentStep
                                ? context.brandPrimary
                                : Colors.black45,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (i != stepTitles.length - 1) const SizedBox(width: 6),
                  ],
                ],
              );
            }

            Widget buildWizardFooter() {
              Widget? notice;
              if (currentStep == 2) {
                notice = _TrackSheetNoticeCard(
                  icon: Icons.info_outline_rounded,
                  text: tr(
                    context,
                    ru: 'Более надежная упаковка может увеличить вес и размер, но снижает риск повреждений.',
                    zh: '更可靠的包装可能增加重量和体积，但能降低货损风险。',
                  ),
                  color: Colors.orange.shade800,
                );
              } else if (currentStep == 3 && showFragilePackagingRisk) {
                notice = _TrackSheetNoticeCard(
                  icon: Icons.warning_amber_rounded,
                  text: tr(
                    context,
                    ru: 'Некоторые выбранные материалы не подходят для хрупких товаров. Рекомендуем выбрать более надежную упаковку или добавить защиту.',
                    zh: '部分所选材料不适合易碎品，建议选择更可靠的包装或增加防护。',
                  ),
                  color: Colors.deepOrange.shade700,
                );
              } else if (currentStep == 3 && showFragileAddonRecommendation) {
                notice = _TrackSheetNoticeCard(
                  icon: Icons.info_outline_rounded,
                  text: tr(
                    context,
                    ru: 'Для хрупкого груза лучше добавить подходящую защиту, чтобы снизить риск повреждений.',
                    zh: '建议为易碎货物增加适当防护，以降低损坏风险。',
                  ),
                  color: Colors.orange.shade800,
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (notice != null) ...[notice, const SizedBox(height: 10)],
                  Row(
                    children: [
                      ...[
                        Expanded(
                          child: TrainingTarget(
                            id: 'assembly.wizard.back-to-tariff',
                            onActivate: () => goToStep(currentStep - 1),
                            child: TrainingTarget(
                              id: currentStep == 3
                                  ? 'assembly.wizard.back-to-packaging'
                                  : 'assembly.wizard.back',
                              onActivate: () => goToStep(currentStep - 1),
                              child: _TrackSheetSecondaryButton(
                                label: currentStep > 0
                                    ? tr(context, ru: 'Назад', zh: '上一步')
                                    : tr(context, ru: 'Закрыть', zh: '关闭'),
                                onTap: () {
                                  if (savingAssembly) return;
                                  if (currentStep > 0) {
                                    goToStep(currentStep - 1);
                                  } else {
                                    Navigator.of(sheetContext).pop(false);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        flex: currentStep > 0 ? 1 : 2,
                        child: TrainingTarget(
                          id: currentStep == 3
                              ? 'assembly.review'
                              : 'assembly.wizard.next',
                          child: TrainingTarget(
                            id: 'assembly.wizard.next.$currentStep',
                            child: TrainingTarget(
                              id: canContinue
                                  ? 'assembly.wizard.ready.$currentStep'
                                  : 'assembly.wizard.waiting.$currentStep',
                              onActivate: canContinue && currentStep < 3
                                  ? () => goToStep(currentStep + 1)
                                  : null,
                              child: _TrackSheetPrimaryButton(
                                label: savingAssembly
                                    ? tr(
                                        context,
                                        ru: 'Создаём сборку…',
                                        zh: '正在创建打包单…',
                                      )
                                    : currentStep < 3
                                    ? tr(context, ru: 'Далее', zh: '下一步')
                                    : tr(
                                        context,
                                        ru: 'Отправить на сборку',
                                        zh: '提交打包',
                                      ),
                                icon: currentStep < 3
                                    ? Icons.arrow_forward_rounded
                                    : Icons.inventory_2_rounded,
                                onTap: canContinue && !savingAssembly
                                    ? () async {
                                        if (currentStep < 3) {
                                          goToStep(currentStep + 1);
                                          return;
                                        }
                                        setSheetState(
                                          () => savingAssembly = true,
                                        );
                                        try {
                                          final created =
                                              await submitAssembly();
                                          if (!sheetContext.mounted) return;
                                          if (created) {
                                            Navigator.of(
                                              sheetContext,
                                            ).pop(true);
                                          }
                                        } catch (_) {
                                          if (!sheetContext.mounted) return;
                                          _showStyledSnackBar(
                                            sheetContext,
                                            tr(
                                              sheetContext,
                                              ru: 'Не удалось создать сборку. Данные остались в форме.',
                                              zh: '无法创建打包单，数据已保留在表单中。',
                                            ),
                                            isError: true,
                                          );
                                        } finally {
                                          if (sheetContext.mounted) {
                                            setSheetState(
                                              () => savingAssembly = false,
                                            );
                                          }
                                        }
                                      }
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            return PopScope(
              canPop: !savingAssembly,
              child: _TrackSheetSurface(
                icon: Icons.inventory_2_rounded,
                title: tr(context, ru: 'Создать сборку', zh: '创建集运单'),
                subtitle: tr(
                  context,
                  ru: 'Настройте тариф, упаковку и отправку ${_selectedTracks.length} треков',
                  zh: '为 ${_selectedTracks.length} 个运单设置运价、包装和发货选项',
                ),
                keyboardAware: true,
                scrollController: createAssemblyScrollController,
                pinnedChild: buildStepIndicator(),
                footer: buildWizardFooter(),
                contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (currentStep == 1)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE8EAEE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.inventory_2_outlined,
                                  size: 18,
                                  color: context.brandPrimary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tr(
                                      context,
                                      ru: '2. Описание товаров',
                                      zh: '2. 商品描述',
                                    ),
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 18),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: hasFragileGoods,
                              activeColor: context.brandPrimary,
                              title: Text(
                                tr(
                                  context,
                                  ru: 'Есть хрупкие товары',
                                  zh: '包含易碎品',
                                ),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                tr(
                                  context,
                                  ru: 'Склад увидит это перед упаковкой.',
                                  zh: '仓库打包前会看到此标记。',
                                ),
                                style: TextStyle(fontSize: 12),
                              ),
                              onChanged: (value) =>
                                  setSheetState(() => hasFragileGoods = value),
                            ),
                            const Divider(height: 18),
                            Text(
                              tr(context, ru: 'Количество мест', zh: '件数'),
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                TrainingTarget(
                                  id: placePreference == null
                                      ? 'assembly.required.places'
                                      : 'assembly.places.chosen',
                                  child: placePreferenceChip(
                                    value: 'single_if_possible',
                                    label: tr(
                                      context,
                                      ru: 'По возможности 1 место',
                                      zh: '尽量合为1件',
                                    ),
                                  ),
                                ),
                                placePreferenceChip(
                                  value: 'split_allowed',
                                  label: tr(
                                    context,
                                    ru: 'Можно разделить',
                                    zh: '允许分件',
                                  ),
                                ),
                              ],
                            ),
                            if (placePreference == null) ...[
                              const SizedBox(height: 8),
                              Text(
                                tr(
                                  context,
                                  ru: 'Выберите один из вариантов, чтобы склад понимал как упаковывать груз.',
                                  zh: '请选择一种方式，以便仓库安排打包。',
                                ),
                                style: TextStyle(
                                  color: Colors.black45,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (placePreference == 'single_if_possible') ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 18,
                                      color: Colors.orange.shade800,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        tr(
                                          context,
                                          ru: 'Так мест может быть меньше, но материалов может потребоваться больше. Стоимость упаковки считается по фактическому расходу: коробки, мешки и доп. защита.',
                                          zh: '合件可减少件数，但可能需要更多材料。包装费用按纸箱、袋子和额外防护材料的实际用量计算。',
                                        ),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (currentStep == 1) const SizedBox(height: 16),
                    if (currentStep == 0) ...[
                      Text(
                        tr(context, ru: '1. Тариф и страховка', zh: '1. 运价与保险'),
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (tariffs.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FA),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE8EAEE)),
                          ),
                          child: Text(
                            tr(
                              context,
                              ru: 'Нет доступных тарифов',
                              zh: '暂无可用运价',
                            ),
                            style: TextStyle(
                              color: Colors.black45,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        TrainingTarget(
                          id: 'assembly.tariff.section',
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F8FA),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFE8EAEE),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  tr(context, ru: 'Тариф доставки', zh: '运输运价'),
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  tr(
                                    context,
                                    ru: 'Выберите один тариф для этой сборки.',
                                    zh: '请为此集运单选择一种运价。',
                                  ),
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ...tariffs.map(
                                  (t) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: TrainingTarget(
                                      id:
                                          t.id ==
                                              (selectedTariff?.id ??
                                                  tariffs.first.id)
                                          ? 'assembly.tariff'
                                          : 'assembly.tariff.${t.id}',
                                      child: tariffOptionTile(
                                        t,
                                        selected: selectedTariff?.id == t.id,
                                      ),
                                    ),
                                  ),
                                ),
                                if (!completeProductInfoSatisfied) ...[
                                  const SizedBox(height: 8),
                                  _TrackSheetNoticeCard(
                                    icon: Icons.info_outline_rounded,
                                    text: _completeProductInfoMessage(
                                      context,
                                      completeProductInfoIssues.contains(
                                            ProductInfoCompleteness
                                                .missingNameOrQuantity,
                                          ) ||
                                          selectedLoadedTracks.length !=
                                              _selectedTracks.length,
                                    ),
                                    color: Colors.orange.shade800,
                                  ),
                                ],
                                if (requiresAssemblyGoodsDescription) ...[
                                  const SizedBox(height: 6),
                                  const Divider(height: 18),
                                  Text(
                                    tr(
                                      context,
                                      ru: 'Описание товаров',
                                      zh: '商品描述',
                                    ),
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    tr(
                                      context,
                                      ru: 'Не заполнены данные о товаре в ${tracksWithoutProductInfo.length} треках. Укажите общее описание товаров для сборки.',
                                      zh: '${tracksWithoutProductInfo.length} 个运单尚未填写商品信息，请填写此集运单的总体商品描述。',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TrainingTarget(
                                    id: 'assembly.goods-description',
                                    child: TrainingTarget(
                                      id: !hasAssemblyGoodsDescription
                                          ? 'assembly.required.goods-description'
                                          : 'assembly.goods-description.filled',
                                      child: _outlinedInput(
                                        context,
                                        goodsDescriptionController,
                                        hint: tr(
                                          context,
                                          ru:
                                              'Пример:\n'
                                              'Джинсы 4 шт\n'
                                              'Кроссовки белые Nike 2 шт\n'
                                              'Розовый слон 1 шт\n'
                                              'Детский комбинезон 2 шт',
                                          zh: '例如：\n牛仔裤4件\n白色Nike运动鞋2双\n粉色大象玩具1件\n儿童连体衣2件',
                                        ),
                                        keyboardType: TextInputType.multiline,
                                        maxLines: 4,
                                        onChanged: (value) => setSheetState(
                                          () => goodsDescription = value.trim(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      const Divider(height: 24),
                    ],
                    // ── Тип упаковки ──
                    if (currentStep == 2) ...[
                      Text(
                        tr(context, ru: '3. Упаковка', zh: '3. 包装'),
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TrainingTarget(
                        id: 'assembly.packaging.section',
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F8FA),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE8EAEE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                tr(
                                  context,
                                  ru: 'Основная упаковка',
                                  zh: '主要包装',
                                ),
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                tr(
                                  context,
                                  ru: 'Выберите один вариант. Без основной упаковки сборку создать нельзя.',
                                  zh: '请选择一种主要包装，未选择时无法创建集运单。',
                                ),
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (primaryPackagingTypes.isEmpty)
                                Text(
                                  tr(
                                    context,
                                    ru: 'Нет доступной основной упаковки',
                                    zh: '暂无可用的主要包装',
                                  ),
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              else
                                ...primaryPackagingTypes.map(
                                  (p) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: TrainingTarget(
                                      id: p.id == primaryPackagingTypes.first.id
                                          ? 'assembly.packaging'
                                          : 'assembly.packaging.${p.id}',
                                      child: TrainingTarget(
                                        id: selectedPackingIds.contains(p.id)
                                            ? 'assembly.packaging.selected'
                                            : 'assembly.packaging.${p.id}.unselected',
                                        child: TrainingTarget(
                                          id:
                                              !hasPrimaryPackaging &&
                                                  p.id ==
                                                      primaryPackagingTypes
                                                          .first
                                                          .id
                                              ? 'assembly.required.packaging'
                                              : 'assembly.packaging.${p.id}.choice',
                                          child: packagingOptionTile(
                                            p,
                                            selected: selectedPackingIds
                                                .contains(p.id),
                                            primary: true,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE8EAEE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              tr(
                                context,
                                ru: 'Дополнительная защита',
                                zh: '额外防护',
                              ),
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tr(
                                context,
                                ru: 'Можно выбрать несколько вариантов или оставить без доп. защиты.',
                                zh: '可选择多种防护材料，也可不添加额外防护。',
                              ),
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (hasFragileGoods &&
                                addonPackagingTypes.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: context.brandPrimary.withValues(
                                    alpha: 0.07,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: context.brandPrimary.withValues(
                                      alpha: 0.18,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.health_and_safety_outlined,
                                      color: context.brandPrimary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        tr(
                                          context,
                                          ru: 'Для хрупких товаров рекомендуем добавить дополнительную защиту даже при надежной основной упаковке. Это может немного увеличить вес и стоимость упаковки, но снижает риск повреждений в пути.',
                                          zh: '即使主要包装可靠，也建议为易碎品增加额外防护。这可能略微增加重量和包装费，但能降低运输货损风险。',
                                        ),
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontSize: 12,
                                          height: 1.25,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            if (addonPackagingTypes.isEmpty)
                              Text(
                                tr(
                                  context,
                                  ru: 'Дополнительная защита недоступна',
                                  zh: '暂无额外防护材料',
                                ),
                                style: TextStyle(
                                  color: Colors.black45,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else
                              ...addonPackagingTypes.map(
                                (p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: packagingOptionTile(
                                    p,
                                    selected: selectedPackingIds.contains(p.id),
                                    primary: false,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (currentStep == 0) ...[
                      // ── Страховка ──
                      Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 18,
                            color: context.brandPrimary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            tr(context, ru: 'Страховка', zh: '保险'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          TrainingTarget(
                            id: 'assembly.insurance',
                            child: Switch.adaptive(
                              value: selectedInsurance == 'yes',
                              activeColor: context.brandPrimary,
                              onChanged: (v) => setSheetState(
                                () => selectedInsurance = v ? 'yes' : 'no',
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (selectedInsurance == 'yes') ...[
                        const SizedBox(height: 4),
                        TrainingTarget(
                          id: 'assembly.insurance-amount',
                          child: TrainingTarget(
                            id: insuranceAmount?.isNotEmpty == true
                                ? 'assembly.insurance-amount.filled'
                                : 'assembly.required.insurance-amount',
                            child: _outlinedInput(
                              context,
                              insuranceAmountController,
                              hint: tr(
                                context,
                                ru: 'Сумма товаров в юанях',
                                zh: '商品总金额（人民币）',
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (value) {
                                setSheetState(() => insuranceAmount = value);
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    if (currentStep == 3)
                      TrainingTarget(
                        id: 'assembly.review.summary',
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.brandPrimary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: context.brandPrimary.withValues(
                                alpha: 0.12,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                tr(
                                  context,
                                  ru: '4. Подтверждение',
                                  zh: '4. 确认',
                                ),
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _SummaryLine(
                                label: tr(
                                  context,
                                  ru: 'Описание товаров',
                                  zh: '商品描述',
                                ),
                                value: requiresAssemblyGoodsDescription
                                    ? goodsDescription
                                    : tr(
                                        context,
                                        ru: 'По данным треков',
                                        zh: '根据运单信息',
                                      ),
                              ),
                              _SummaryLine(
                                label: tr(
                                  context,
                                  ru: 'Хрупкий груз',
                                  zh: '易碎货物',
                                ),
                                value: hasFragileGoods
                                    ? tr(context, ru: 'Да', zh: '是')
                                    : tr(context, ru: 'Нет', zh: '否'),
                              ),
                              _SummaryLine(
                                label: tr(context, ru: 'Места', zh: '件数'),
                                value: switch (placePreference) {
                                  'single_if_possible' => tr(
                                    context,
                                    ru: 'По возможности 1 место',
                                    zh: '尽量合为1件',
                                  ),
                                  'split_allowed' => tr(
                                    context,
                                    ru: 'Можно разделить',
                                    zh: '允许分件',
                                  ),
                                  _ => tr(context, ru: 'Не выбрано', zh: '未选择'),
                                },
                              ),
                              _SummaryLine(
                                label: tr(context, ru: 'Тариф', zh: '运价'),
                                value:
                                    selectedTariff?.localizedName(
                                      isZh(context),
                                    ) ??
                                    tr(context, ru: 'Не выбран', zh: '未选择'),
                              ),
                              _SummaryLine(
                                label: tr(context, ru: 'Упаковка', zh: '包装'),
                                value: selectedPackagingNames.isEmpty
                                    ? tr(context, ru: 'Не выбрана', zh: '未选择')
                                    : selectedPackagingNames.join(', '),
                              ),
                              _SummaryLine(
                                label: tr(context, ru: 'Страховка', zh: '保险'),
                                value: selectedInsurance == 'yes'
                                    ? tr(
                                        context,
                                        ru: 'Да, ${insuranceAmount ?? ''} ¥',
                                        zh: '是，${insuranceAmount ?? ''} ¥',
                                      )
                                    : tr(context, ru: 'Нет', zh: '否'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    final assemblyGoodsDescription = goodsDescriptionController.text.trim();
    if (result != true) {
      _assemblyDraftScope = scope;
      _assemblyDraft = AssemblyFormDraft(
        tariffId: selectedTariff?.id,
        packagingIds: selectedPackingIds,
        fragile: hasFragileGoods,
        placePreference: placePreference,
        insured: selectedInsurance == 'yes',
        insuranceAmount: insuranceAmountController.text,
        goodsDescription: assemblyGoodsDescription,
        step: currentStep,
      );
    }
    _disposeAfterBottomSheetClose([
      insuranceAmountController.dispose,
      goodsDescriptionController.dispose,
      createAssemblyScrollController.dispose,
    ]);
  }

  Future<void> _showAboutProductSheet(
    BuildContext context,
    TrackItem track,
  ) async {
    final existing = _productInfos[track.code];
    final nameController = TextEditingController(
      text: existing?.name ?? track.productInfo?.name ?? '',
    );
    final qtyController = TextEditingController(
      text:
          existing?.quantity?.toString() ??
          track.productInfo?.quantity.toString() ??
          '',
    );

    // Список путей/URL для отображения
    final images = List<String>.from(existing?.images ?? const []);
    if (track.productInfo?.imageUrl != null &&
        track.productInfo!.imageUrl!.isNotEmpty) {
      if (!images.contains(track.productInfo!.imageUrl)) {
        images.insert(0, track.productInfo!.imageUrl!);
      }
    }

    // Новые выбранные файлы (XFile)
    final List<XFile> newFiles = [];
    var savingProduct = false;
    await showBlurredModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return _TrackSheetSurface(
              icon: Icons.inventory_2_rounded,
              title: tr(context, ru: 'О товаре', zh: '商品信息'),
              subtitle: tr(
                context,
                ru: 'Данные по треку ${track.code}',
                zh: '运单 ${track.code} 的信息',
              ),
              keyboardAware: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(context, ru: 'Название товара', zh: '商品名称'),
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _outlinedInput(
                    context,
                    nameController,
                    hint: tr(
                      context,
                      ru: 'например: кроссовки Nuke Air Max',
                      zh: '例如：Nuke Air Max 运动鞋',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr(context, ru: 'Количество', zh: '数量'),
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _outlinedInput(
                    context,
                    qtyController,
                    hint: tr(context, ru: 'например: 2', zh: '例如：2'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 12),
                  // Одно изображение товара — можно заменить
                  Builder(
                    builder: (_) {
                      // Определяем текущее изображение: новое > существующее
                      final hasNew = newFiles.isNotEmpty;
                      final hasExisting = images.isNotEmpty;
                      final hasImage = hasNew || hasExisting;

                      Future<void> pickImage() async {
                        try {
                          final picker = ImagePicker();
                          final picked = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 85,
                          );
                          if (picked != null) {
                            setSheetState(() {
                              newFiles.clear();
                              newFiles.add(picked);
                            });
                          }
                        } catch (e) {
                          if (context.mounted) {
                            _showStyledSnackBar(
                              context,
                              tr(
                                context,
                                ru: 'Не удалось открыть галерею: $e',
                                zh: '无法打开相册：$e',
                              ),
                              isError: true,
                            );
                          }
                        }
                      }

                      if (!hasImage) {
                        return SizedBox(
                          width: double.infinity,
                          child: _ActionChipButton(
                            icon: Icons.add_photo_alternate_rounded,
                            label: tr(
                              context,
                              ru: 'Добавить фото товара',
                              zh: '添加商品照片',
                            ),
                            onPressed: pickImage,
                          ),
                        );
                      }

                      Widget imageWidget;
                      if (hasNew) {
                        final file = newFiles.first;
                        imageWidget = kIsWeb
                            ? FutureBuilder<Uint8List>(
                                future: file.readAsBytes(),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData) {
                                    return Image.memory(
                                      snapshot.data!,
                                      fit: BoxFit.cover,
                                    );
                                  }
                                  return const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  );
                                },
                              )
                            : Image.file(
                                File(file.path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(color: Colors.black12),
                              );
                      } else {
                        final path = images.first;
                        final isUrl =
                            path.startsWith('http') || path.startsWith('/');
                        imageWidget = isUrl
                            ? AppCachedMediaImage(
                                url: path,
                                thumbnailSize: 480,
                                memCacheWidth: 320,
                                memCacheHeight: 240,
                                maxWidthDiskCache: 640,
                                maxHeightDiskCache: 480,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                useOldImageOnUrlChange: false,
                                filterQuality: FilterQuality.low,
                                imageBuilder: (_, imageProvider) =>
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        image: DecorationImage(
                                          image: imageProvider,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                placeholder: (_, _) => const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                errorWidget: (_, _, _) =>
                                    const ColoredBox(color: Colors.black12),
                              )
                            : (!kIsWeb
                                  ? Image.file(
                                      File(path),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const ColoredBox(
                                            color: Colors.black12,
                                          ),
                                    )
                                  : const ColoredBox(color: Colors.black12));
                      }

                      return Stack(
                        children: [
                          GestureDetector(
                            onTap: pickImage,
                            child: Container(
                              width: double.infinity,
                              height: 160,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x14000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: imageWidget,
                            ),
                          ),
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: GestureDetector(
                              onTap: pickImage,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.swap_horiz,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      tr(context, ru: 'Заменить', zh: '更换'),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 6,
                            top: 6,
                            child: GestureDetector(
                              onTap: () => setSheetState(() {
                                images.clear();
                                newFiles.clear();
                              }),
                              child: const CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.white,
                                child: Icon(Icons.close_rounded, size: 18),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _TrackSheetPrimaryButton(
                    label: tr(
                      context,
                      ru: savingProduct ? 'Сохраняем…' : 'Сохранить',
                      zh: savingProduct ? '正在保存…' : '保存',
                    ),
                    icon: Icons.check_rounded,
                    onTap: savingProduct
                        ? null
                        : () async {
                            setSheetState(() => savingProduct = true);
                            final saved = await _saveProductInfo(
                              context,
                              track,
                              productName: nameController.text.trim(),
                              quantity:
                                  int.tryParse(qtyController.text.trim()) ?? 1,
                              existingImages: images,
                              newImage: newFiles.firstOrNull,
                            );
                            if (!sheetContext.mounted) return;
                            if (saved) {
                              Navigator.of(sheetContext).pop();
                            } else {
                              setSheetState(() => savingProduct = false);
                            }
                          },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    nameController.dispose();
    qtyController.dispose();
  }

  Future<bool> _saveProductInfo(
    BuildContext context,
    TrackItem track, {
    required String productName,
    required int quantity,
    required List<String> existingImages,
    XFile? newImage,
  }) async {
    String? uploadedImageUrl;
    if (track.id != null && newImage != null) {
      try {
        final sourceBytes = await newImage.readAsBytes();
        const maxMultipartSafeBytes = 9 * 1024 * 1024;
        var compressed = await ImageCompressor.compressForUpload(
          sourceBytes,
          sourceName: newImage.name,
        );
        if (compressed.bytes.lengthInBytes > maxMultipartSafeBytes) {
          compressed = await ImageCompressor.compressForUpload(
            sourceBytes,
            sourceName: newImage.name,
            maxSide: 1600,
            quality: 75,
          );
        }
        if (compressed.bytes.lengthInBytes > maxMultipartSafeBytes) {
          throw Exception('фото не удалось сжать до 10 MB');
        }
        uploadedImageUrl = await ref
            .read(tracksApiServiceProvider)
            .uploadProductInfoImageFromBytes(
              track.id!,
              compressed.bytes,
              _fileNameWithExtension(newImage.name, compressed.extension),
              mimeType: compressed.mimeType,
            );
        if (uploadedImageUrl == null) {
          throw Exception('сервер не вернул URL изображения');
        }
      } catch (error) {
        debugPrint('Failed to upload image ${newImage.name}: $error');
        if (context.mounted) {
          _showStyledSnackBar(
            context,
            tr(context, ru: 'Не удалось загрузить фото товара', zh: '无法上传商品照片'),
            isError: true,
          );
        }
        return false;
      }
    }

    final images = uploadedImageUrl == null
        ? List<String>.from(existingImages)
        : <String>[uploadedImageUrl];
    if (track.id != null) {
      final success = await ref
          .read(tracksApiServiceProvider)
          .updateProductInfo(
            trackId: track.id!,
            productName: productName,
            quantity: quantity,
            imageUrl: images.firstOrNull,
          );
      if (success) {
        _refreshTracks();
        if (context.mounted) {
          _showStyledSnackBar(
            context,
            tr(context, ru: 'Информация о товаре сохранена', zh: '商品信息已保存'),
          );
        }
        return true;
      }
      if (context.mounted) {
        _showStyledSnackBar(
          context,
          tr(
            context,
            ru: 'Не удалось сохранить товар. Данные остались в форме — повторите сохранение.',
            zh: '商品保存失败，填写的内容仍保留在表单中，请重试。',
          ),
          isError: true,
        );
      }
      return false;
    }

    if (mounted) {
      setState(() {
        _productInfos[track.code] = _ProductInfo(
          name: productName,
          quantity: quantity,
          images: images,
        );
      });
    }
    if (context.mounted) {
      _showStyledSnackBar(
        context,
        track.id == null
            ? tr(
                context,
                ru: 'Информация о товаре сохранена локально',
                zh: '商品信息已保存在本机',
              )
            : tr(context, ru: 'Ошибка сохранения на сервере', zh: '无法保存到服务器'),
        isError: track.id != null,
      );
    }
    return true;
  }

  /// Получить текущие параметры фильтрации
  TracksFilterParams _getFilterParams(String clientCode) {
    final isAssemblyMode = _viewMode == ViewMode.groups;
    return TracksFilterParams(
      clientCode: clientCode,
      statusCode: isAssemblyMode ? null : _statusCode,
      assemblyStatusCode: isAssemblyMode ? _statusCode : null,
      search: _query.isNotEmpty ? _query : null,
      viewMode: _viewMode == ViewMode.all
          ? 'all'
          : _viewMode == ViewMode.groups
          ? 'groups'
          : 'singles',
      productInfo: isAssemblyMode
          ? null
          : switch (_productInfoMode) {
              ProductInfoMode.all => null,
              ProductInfoMode.filled => 'filled',
              ProductInfoMode.empty => 'empty',
            },
      photoRequestStatus: isAssemblyMode ? null : _photoRequestStatusCode,
      questionStatus: isAssemblyMode ? null : _questionStatusCode,
      assemblyDeliveryInfo: !isAssemblyMode
          ? null
          : switch (_deliveryInfoMode) {
              DeliveryInfoMode.all => null,
              DeliveryInfoMode.filled => 'filled',
              DeliveryInfoMode.empty => 'empty',
            },
      sortBy: _sortMode.queryValue,
    );
  }

  /// Обработчик изменения поиска с debounce
  void _onSearchChanged(String value, String clientCode) {
    setState(() => _query = value);

    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      final params = _getFilterParams(clientCode);
      ref.read(paginatedTracksProvider(clientCode)).updateFilters(params);
    });
  }

  void _onSortModeChanged(TrackSortMode mode, String clientCode) {
    setState(() => _sortMode = mode);

    final params = _getFilterParams(clientCode);
    ref.read(paginatedTracksProvider(clientCode)).updateFilters(params);
  }

  void _onDisplayModeChanged(ViewMode mode, String clientCode) {
    if (_viewMode == mode) return;
    setState(() {
      _viewMode = mode;
      // Статусы у треков и сборок разные, поэтому при переключении вкладки
      // сбрасываем выбранный статус, чтобы не применить нерелевантный код.
      _statusCode = null;
    });

    final params = _getFilterParams(clientCode);
    ref.read(paginatedTracksProvider(clientCode)).updateFilters(params);
  }

  String? _initialTargetKey() {
    final hasTarget =
        widget.initialTrackId != null ||
        (widget.initialTrackCode?.isNotEmpty ?? false) ||
        widget.initialAssemblyId != null;
    if (!hasTarget) return null;
    return [
      widget.initialClientCode ?? '',
      widget.initialTrackId?.toString() ?? '',
      widget.initialTrackCode ?? '',
      widget.initialAssemblyId?.toString() ?? '',
    ].join('|');
  }

  String? _clientCodeSwitchTarget(String activeCode) {
    final requested = widget.initialClientCode?.trim();
    if (requested == null || requested.isEmpty) return null;
    if (requested.toUpperCase() == activeCode.toUpperCase()) return null;

    final codesState = ref.watch(clientCodesControllerProvider).asData?.value;
    if (codesState == null) return null;
    for (final code in codesState.codes) {
      if (code.toUpperCase() == requested.toUpperCase()) return code;
    }
    return null;
  }

  void _scheduleInitialClientSwitch(String targetCode) {
    if (_initialClientSwitchTarget == targetCode) return;
    _initialClientSwitchTarget = targetCode;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref
          .read(clientCodesControllerProvider.notifier)
          .selectClient(targetCode);
    });
  }

  int? _findInitialBucketIndex(List<_GroupBucket> groups) {
    if (widget.initialAssemblyId != null) {
      for (var i = 0; i < groups.length; i++) {
        final group = groups[i];
        if (group.assembly?.id == widget.initialAssemblyId) {
          return i;
        }
      }
      return null;
    }

    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      final hasTrack = group.tracks.any((track) {
        final idMatches =
            widget.initialTrackId != null && track.id == widget.initialTrackId;
        final codeMatches =
            widget.initialTrackCode != null &&
            track.code.toLowerCase() == widget.initialTrackCode!.toLowerCase();
        return idMatches || codeMatches;
      });
      if (hasTrack) return i;
    }
    return null;
  }

  String _groupTargetKey(_GroupBucket bucket) {
    final assemblyId = bucket.assembly?.id;
    if (assemblyId != null) return 'assembly:$assemblyId';
    final track = bucket.tracks.firstOrNull;
    return 'track:${track?.id ?? track?.code ?? bucket.hashCode}';
  }

  GlobalKey _keyForGroup(_GroupBucket bucket) {
    final key = _groupTargetKey(bucket);
    return _targetGroupKeys.putIfAbsent(key, GlobalKey.new);
  }

  void _maybeOpenInitialTarget(
    List<_GroupBucket> groups,
    String clientCode, {
    required bool isLoading,
  }) {
    final targetKey = _initialTargetKey();
    if (targetKey == null) return;
    if (_handledInitialTargetKey == targetKey) return;

    final bucketIndex = _findInitialBucketIndex(groups);
    if (bucketIndex == null) {
      if (!isLoading) _loadInitialTargetIntoList(targetKey, clientCode);
      return;
    }

    final bucket = groups[bucketIndex];
    _handledInitialTargetKey = targetKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusInitialTarget(bucket, bucketIndex);
    });
  }

  void _focusInitialTarget(_GroupBucket bucket, int index) {
    final groupKey = _groupTargetKey(bucket);
    _highlightTimer?.cancel();
    setState(() => _highlightedGroupKey = groupKey);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        // Approximation first brings virtualized sliver item close enough to
        // build, then ensureVisible below aligns it precisely.
        final estimatedOffset = (260.0 + index * 180.0)
            .clamp(0.0, maxScroll)
            .toDouble();
        await _scrollController.animateTo(
          estimatedOffset,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      }

      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;

      final contextForTarget = _keyForGroup(bucket).currentContext;
      if (contextForTarget != null) {
        await Scrollable.ensureVisible(
          // ignore: use_build_context_synchronously
          contextForTarget,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          alignment: 0.18,
        );
      }

      _highlightTimer = Timer(const Duration(milliseconds: 1800), () {
        if (!mounted) return;
        setState(() => _highlightedGroupKey = null);
      });
    });
  }

  void _loadInitialTargetIntoList(String targetKey, String clientCode) {
    if (_loadingInitialTargetIntoList) return;
    _loadingInitialTargetIntoList = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final notifier = ref.read(paginatedTracksProvider(clientCode));
        var iterations = 0;
        const maxIterations = 60;

        while (mounted &&
            _initialTargetKey() == targetKey &&
            notifier.state.hasMore &&
            !notifier.state.isLoading &&
            _findInitialBucketIndex(_groupTracks(notifier.state.tracks)) ==
                null &&
            iterations < maxIterations) {
          await notifier.loadMore();
          iterations++;
        }

        if (!mounted || _initialTargetKey() != targetKey) return;
        final groups = _groupTracks(notifier.state.tracks);
        final index = _findInitialBucketIndex(groups);
        if (index != null) {
          _handledInitialTargetKey = targetKey;
          _focusInitialTarget(groups[index], index);
          return;
        }

        _handledInitialTargetKey = targetKey;
      } finally {
        _loadingInitialTargetIntoList = false;
      }
    });
  }

  Future<void> _showWarehouseDeliverySheet(
    BuildContext context,
    TrackItem track,
  ) async {
    await showBlurredModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => _TrackSheetSurface(
        icon: Icons.local_shipping_outlined,
        title: tr(sheetContext, ru: 'Доставка до склада', zh: '到仓物流'),
        subtitle: tr(
          sheetContext,
          ru: 'Трек ${track.code}',
          zh: '单号 ${track.code}',
        ),
        child: TrackWarehouseDeliveryPanel(track: track),
      ),
    );
  }

  _TrackGroupCard _buildTrackGroupCard(
    _GroupBucket group, {
    GlobalKey? tutorialActionsKey,
    GlobalKey? tutorialAssemblyKey,
    Set<String> trainingTargets = const {},
    List<TrackStatus>? trackStatuses,
    List<TrackStatus>? assemblyStatuses,
  }) {
    return _TrackGroupCard(
      trainingTargets: trainingTargets,
      assembly: group.assembly,
      tracks: group.tracks,
      trackStatuses:
          trackStatuses ??
          ref.read(trackStatusesProvider).asData?.value ??
          const [],
      assemblyStatuses:
          assemblyStatuses ??
          ref.read(assemblyStatusesProvider).asData?.value ??
          const [],
      selectedTrackCodes: _selectedTracks,
      selectedStatus: _selectedStatus,
      allowSelection: widget.embeddedTracks == null,
      onToggle: _toggleTrack,
      requestedPhotoReports: _requestedPhotoReports,
      onPhotoRequest: (track) => _showPhotoRequestSheet(context, track),
      onRequestPhotoInline: (track, wish) =>
          _requestPhotoInline(context, track, wish),
      onCancelPhotoRequest: (track) => _cancelPhotoRequest(track),
      onEditPhotoWish: (track) => _showEditPhotoWishSheet(context, track),
      onUpdatePhotoWishInline: (track, wish) =>
          _updatePhotoWishInline(context, track, wish),
      photoRequestCreatedAt: _photoRequestCreatedAt,
      photoRequestUpdatedAt: _photoRequestUpdatedAt,
      photoRequestNotes: _photoRequestNotes,
      overrideComments: _overrideComments,
      onAskQuestion: (track) => _showAskQuestionSheet(context, track),
      onAskQuestionInline: (track) => _askQuestionInline(context, track),
      onTransferClientCode: (track) =>
          _showClientCodeTransferSheet(context, track),
      onCancelQuestion: (track) => _cancelQuestion(track),
      onEditComment: (track) => _showCommentSheet(context, track),
      onSaveComment: (track, comment) =>
          _saveTrackComment(context, track, comment),
      onEditProduct: (track) => _showAboutProductSheet(context, track),
      onSaveProduct: (track, name, quantity, images, newImage) =>
          _saveProductInfo(
            context,
            track,
            productName: name,
            quantity: quantity,
            existingImages: images,
            newImage: newImage,
          ),
      askedQuestions: _askedQuestions,
      questionCreatedAt: _questionCreatedAt,
      questionUpdatedAt: _questionUpdatedAt,
      questionStatus: _questionStatus,
      questionAnswers: _questionAnswers,
      productInfos: _productInfos,
      groupComments: _groupComments,
      groupQuestions: _groupQuestions,
      groupQuestionCreatedAt: _groupQuestionCreatedAt,
      groupQuestionUpdatedAt: _groupQuestionUpdatedAt,
      onEditGroupComment: (assembly) =>
          _showGroupCommentSheet(context, assembly),
      onAskGroupQuestion: (assembly) =>
          _showGroupQuestionSheet(context, assembly),
      onSelectDelivery: (assembly) => _showDeliverySheet(context, assembly),
      onSaveDelivery:
          (
            assembly, {
            required deliveryMethod,
            recipientName,
            recipientPhone,
            recipientCity,
            transportCompanyName,
          }) => _saveAssemblyDeliveryInline(
            context,
            assembly,
            deliveryMethod: deliveryMethod,
            recipientName: recipientName,
            recipientPhone: recipientPhone,
            recipientCity: recipientCity,
            transportCompanyName: transportCompanyName,
          ),
      onConfirmAssemblyReceipt: (assembly) =>
          _confirmAssemblyReceipt(context, assembly),
      onDeleteTrack: (track) => _deleteTrack(track),
      onReturnRequest: (track) => _showReturnSheet(context, track),
      onRequestReturnInline: (track, code) =>
          _requestReturnInline(context, track, code),
      onWarehouseDelivery: (track) =>
          _showWarehouseDeliverySheet(context, track),
      onLoadReturn: (trackId) =>
          ref.read(tracksApiServiceProvider).getTrackReturn(trackId),
      onUpdateReturnCode: (trackId, returnCode) => ref
          .read(tracksApiServiceProvider)
          .updateTrackReturnCode(trackId: trackId, returnCode: returnCode),
      onConfirmCompletedReturn: (track) =>
          _confirmCompletedReturn(context, track),
      returnRequestedTracks: _returnRequestedTracks,
      tutorialActionsKey: tutorialActionsKey,
      tutorialAssemblyKey: tutorialAssemblyKey,
    );
  }

  Widget _buildHeaderSection(
    BuildContext context, {
    required String clientCode,
    required PaginatedTracksState tracksState,
    required List<TrackStatus> trackStatuses,
    required List<TrackStatus> assemblyStatuses,
    required List<TrackStatus> photoRequestStatuses,
    required List<TrackStatus> questionStatuses,
  }) {
    final isAssemblyMode = _viewMode == ViewMode.groups;
    final activeFilters =
        _statusCode != null ||
        (isAssemblyMode
            ? _deliveryInfoMode != DeliveryInfoMode.all
            : _productInfoMode != ProductInfoMode.all ||
                  _photoRequestStatusCode != null ||
                  _questionStatusCode != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _TracksHeroHeader(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black.withValues(alpha: 0.045)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 18,
                spreadRadius: -9,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TracksViewModeSwitch(
                value: _viewMode == ViewMode.groups
                    ? ViewMode.groups
                    : ViewMode.singles,
                onChanged: (mode) => _onDisplayModeChanged(mode, clientCode),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TrainingTarget(
                      id: 'tracks.search',
                      child: _TracksSearchField(
                        query: _query,
                        onChanged: (value) =>
                            _onSearchChanged(value, clientCode),
                        onClear: () => _onSearchChanged('', clientCode),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TrainingTarget(
                    id: 'tracks.filter',
                    child: _HeaderIconButton(
                      key: _filtersKey,
                      icon: Icons.filter_alt_rounded,
                      tooltip: 'Фильтр',
                      isActive: activeFilters,
                      onTap: () => _showTrackFiltersSheet(
                        clientCode,
                        tracksState.tracks,
                        trackStatuses: trackStatuses,
                        assemblyStatuses: assemblyStatuses,
                        photoRequestStatuses: photoRequestStatuses,
                        questionStatuses: questionStatuses,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _HeaderIconButton(
                    icon: Icons.swap_vert_rounded,
                    tooltip: 'Сортировка',
                    isActive: _sortMode != TrackSortMode.createdAt,
                    onTap: () => _showSortSheet(clientCode),
                  ),
                  const SizedBox(width: 8),
                  TrainingTarget(
                    id: 'tracks.add',
                    onActivate: () => showAddTracksDialog(context, ref),
                    child: _HeaderAddTrackButton(
                      key: _fabKey,
                      onTap: () => showAddTracksDialog(context, ref),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _showSortSheet(String clientCode) async {
    final selected = await showBlurredModalBottomSheet<TrackSortMode>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => _TrackSortSheet(selected: _sortMode),
    );
    if (selected == null || selected == _sortMode || !mounted) return;
    _onSortModeChanged(selected, clientCode);
  }

  Future<void> _showTrackFiltersSheet(
    String clientCode,
    List<TrackItem> tracks, {
    required List<TrackStatus> trackStatuses,
    required List<TrackStatus> assemblyStatuses,
    required List<TrackStatus> photoRequestStatuses,
    required List<TrackStatus> questionStatuses,
  }) async {
    final result = await showBlurredModalBottomSheet<_TrackFiltersResult>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => _TrackFiltersSheet(
        statusCode: _statusCode,
        viewMode: _viewMode,
        tracks: tracks,
        trackStatuses: trackStatuses,
        assemblyStatuses: assemblyStatuses,
        photoRequestStatuses: photoRequestStatuses,
        questionStatuses: questionStatuses,
        productInfoMode: _productInfoMode,
        photoRequestStatusCode: _photoRequestStatusCode,
        questionStatusCode: _questionStatusCode,
        deliveryInfoMode: _deliveryInfoMode,
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _statusCode = result.statusCode;
      _productInfoMode = result.productInfoMode;
      _photoRequestStatusCode = result.photoRequestStatusCode;
      _questionStatusCode = result.questionStatusCode;
      _deliveryInfoMode = result.deliveryInfoMode;
    });
    final params = _getFilterParams(clientCode);
    ref.read(paginatedTracksProvider(clientCode)).updateFilters(params);
  }

  @override
  Widget build(BuildContext context) {
    final clientCode = ref.watch(activeClientCodeProvider);
    if (clientCode == null) {
      return const EmptyState(
        icon: Icons.badge_outlined,
        title: 'Выберите код клиента',
        message:
            'Чтобы увидеть треки, сначала выберите или добавьте код клиента.',
      );
    }

    final embeddedTracks = widget.embeddedTracks;
    if (embeddedTracks != null) {
      if (embeddedTracks.isEmpty) return const SizedBox.shrink();
      final trackStatuses =
          ref.watch(trackStatusesProvider).asData?.value ??
          const <TrackStatus>[];
      final assemblyStatuses =
          ref.watch(assemblyStatusesProvider).asData?.value ??
          const <TrackStatus>[];
      return _buildTrackGroupCard(
        _GroupBucket(
          assembly: widget.embeddedAsAssembly
              ? embeddedTracks.first.assembly
              : null,
          tracks: embeddedTracks,
        ),
        trackStatuses: trackStatuses,
        assemblyStatuses: assemblyStatuses,
      );
    }

    final switchTarget = _clientCodeSwitchTarget(clientCode);
    if (switchTarget != null) {
      _scheduleInitialClientSwitch(switchTarget);
      return const Center(child: CircularProgressIndicator());
    }

    // Получаем notifier и состояние пагинированного списка
    final tracksNotifier = ref.watch(paginatedTracksProvider(clientCode));
    // Подписываемся на изменения состояния notifier
    _updateNotifierListener(tracksNotifier);

    final tracksState = tracksNotifier.state;
    final currentFilters = _getFilterParams(clientCode);
    if (_filtersInitializedForClientCode != clientCode) {
      _filtersInitializedForClientCode = clientCode;
      if (tracksState.filters != currentFilters) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(paginatedTracksProvider(clientCode))
              .updateFilters(currentFilters);
        });
      }
    }
    final trackStatuses =
        ref.watch(trackStatusesProvider).asData?.value ?? const <TrackStatus>[];
    final assemblyStatuses =
        ref.watch(assemblyStatusesProvider).asData?.value ??
        const <TrackStatus>[];
    final photoRequestStatuses =
        ref.watch(photoRequestStatusesProvider).asData?.value ??
        const <TrackStatus>[];
    final questionStatuses =
        ref.watch(questionStatusesProvider).asData?.value ??
        const <TrackStatus>[];
    final bottomPad = AppLayout.bottomScrollPadding(context);
    final topPad = AppLayout.topBarTotalHeight(context);
    const bulkButtonExtraPad = 110.0;
    // DesktopSideNav uses bottom safe-area + 14px padding around its surface.
    // Keep the selected-tracks action bar visually aligned with that bottom
    // edge on iPad/desktop, while preserving the mobile bottom-nav offset.
    const sideNavSurfaceBottomMargin = 14.0;
    final bulkActionsBottomOffset = AppLayout.useSideNavigation(context)
        ? MediaQuery.paddingOf(context).bottom + sideNavSurfaceBottomMargin
        : AppLayout.bottomBarHeightFor(context) +
              AppLayout.bottomBarBottomMarginFor(context) +
              72;

    final groups = tracksState.tracks.isNotEmpty
        ? _groupTracks(tracksState.tracks)
        : <_GroupBucket>[];
    if (tracksState.filters == currentFilters) {
      _maybeOpenInitialTarget(
        groups,
        clientCode,
        isLoading: tracksState.isLoading,
      );
      _scheduleGroupedViewportAutofill(
        clientCode: clientCode,
        tracksState: tracksState,
        currentFilters: currentFilters,
      );
    }
    final bottomScrollPad =
        bottomPad + 16 + (_selectedTracks.isEmpty ? 0 : bulkButtonExtraPad + 8);

    return TutorialScreenWrapper(
      screenKey: 'tracks',
      steps: [
        TutorialStep(
          icon: Icons.local_shipping_rounded,
          title: 'Список треков',
          description:
              'Каждая строка — одна посылка. Цветной статус показывает этап: склад в Китае, в пути, склад в России или получено клиентом.',
          targetKey: _tracksListKey,
        ),
        TutorialStep(
          icon: Icons.add_circle_rounded,
          title: 'Добавить трек',
          description:
              'Нажмите кнопку «+» в верхней панели, чтобы добавить трек-номер новой посылки. Мы начнём её отслеживать.',
          targetKey: _fabKey,
        ),
        TutorialStep(
          icon: Icons.filter_list_rounded,
          title: 'Фильтр по статусу',
          description:
              'Нажмите на статус в верхней панели, чтобы показать только посылки на этом этапе. Удобно при большом количестве треков.',
          targetKey: _filtersKey,
        ),
        TutorialStep(
          icon: Icons.touch_app_rounded,
          title: 'Детали посылки',
          description:
              'Нажмите на трек, чтобы развернуть карточку с подробностями: вес, тариф, история статусов и кнопки действий.',
          targetKey: _trackDetailKey,
        ),
        TutorialStep(
          icon: Icons.photo_camera_rounded,
          title: 'Запросить фотоотчёт',
          description:
              'Кнопка «Запросить фотоотчёт» внутри карточки отправляет запрос на склад. Мы сфотографируем посылку и пришлём снимки. Услуга может быть платной.',
          targetKey: _actionsRowKey,
        ),
        TutorialStep(
          icon: Icons.help_outline_rounded,
          title: 'Задать вопрос',
          description:
              'Кнопка «Задать вопрос» открывает форму для обращения к менеджеру по конкретному треку. Ответ придёт в этой же карточке.',
          targetKey: _actionsRowKey,
        ),
        TutorialStep(
          icon: Icons.sticky_note_2_rounded,
          title: 'Комментарий к треку',
          description:
              'В карточке трека есть поле для заметки. Введите текст и нажмите «Сохранить заметку» — заметка видна только вам.',
          targetKey: _actionsRowKey,
        ),
        TutorialStep(
          icon: Icons.assignment_return_rounded,
          title: 'Оформить возврат',
          description:
              '«Оформить возврат» — открывает форму возврата товара. Укажите причину и код — заявка уйдёт на склад в Китае.',
          targetKey: _actionsRowKey,
        ),
        TutorialStep(
          icon: Icons.inventory_2_rounded,
          title: 'Сборка и доставка по РФ',
          description:
              'Блок сборки показывает транспортную компанию, коробки с весами, тариф и упаковку. Нажмите «Выбрать ТК» для настройки доставки.',
          targetKey: _assemblyKey,
        ),
      ],
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              if (_isRefreshing) return;
              _isRefreshing = true;
              try {
                // Обновляем с актуальными фильтрами из UI
                final filterParams = _getFilterParams(clientCode);
                await ref
                    .read(paginatedTracksProvider(clientCode))
                    .updateFilters(filterParams);
                if (!mounted) return;
                ref.invalidate(assembliesListProvider(clientCode));
                // Очищаем оптимистичные Map-записи для треков у которых
                // сервер уже подтвердил данные (вопросы, фото-запросы)
                final changed = _syncMapsWithServerData(
                  ref.read(paginatedTracksProvider(clientCode)).state.tracks,
                );
                if (changed && mounted) setState(() {});
              } finally {
                _isRefreshing = false;
              }
            },
            color: context.brandPrimary,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Проверяем нужна ли подгрузка при скролле
                if (notification is ScrollUpdateNotification) {
                  final metrics = notification.metrics;
                  final maxScroll = metrics.maxScrollExtent;
                  final currentScroll = metrics.pixels;
                  // Загружаем ещё когда до конца осталось ~10% списка.
                  // Throttle: не чаще 1 раза в 300мс, не пробуем если уже грузим или нет страниц.
                  final now = DateTime.now();
                  final canLoad =
                      _lastLoadMoreTime == null ||
                      now.difference(_lastLoadMoreTime!).inMilliseconds > 300;
                  if (maxScroll > 0 &&
                      currentScroll >= maxScroll * 0.9 &&
                      !tracksState.isLoading &&
                      tracksState.hasMore &&
                      tracksState.error == null &&
                      canLoad) {
                    _lastLoadMoreTime = now;
                    ref.read(paginatedTracksProvider(clientCode)).loadMore();
                  }
                }
                return false;
              },
              child: CustomScrollView(
                controller: _scrollController,
                key: _tracksListKey,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Заголовок + фильтры
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16, topPad * 0.7 + 16, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _buildHeaderSection(
                        context,
                        clientCode: clientCode,
                        tracksState: tracksState,
                        trackStatuses: trackStatuses,
                        assemblyStatuses: assemblyStatuses,
                        photoRequestStatuses: photoRequestStatuses,
                        questionStatuses: questionStatuses,
                      ),
                    ),
                  ),
                  // Список треков или состояние (загрузка/ошибка/пусто)
                  ..._buildTracksList(
                    tracksState,
                    clientCode,
                    groups,
                    bottomScrollPad,
                  ),
                ],
              ),
            ),
          ),
          // Нижние кнопки выбора и отправки показываются только когда выбраны треки.
          if (_selectedTracks.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: bulkActionsBottomOffset,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 86,
                    child: _TrackSheetSecondaryButton(
                      label: 'Все',
                      onTap: _selectAll,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: TrainingTarget(
                      id: _selectedStatus == 'На складе'
                          ? 'assembly.submit'
                          : 'tracks.bulkAction',
                      onActivate: _selectedStatus == 'На складе'
                          ? () => _bulkAction(context)
                          : null,
                      child: TrainingTarget(
                        id: _selectedTracks.length >= 2
                            ? 'assembly.selection.multiple'
                            : 'assembly.selection.single',
                        child: _TrackSheetPrimaryButton(
                          label: _actionLabel(),
                          icon: Icons.inventory_2_rounded,
                          onTap: _selectedStatus == null
                              ? null
                              : () => _bulkAction(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ScrollToTopButton(controller: _scrollController),
        ],
      ),
    );
  }

  /// Построить список треков как slivers (ленивый рендеринг через SliverList.builder)
  List<Widget> _buildTracksList(
    PaginatedTracksState tracksState,
    String clientCode,
    List<_GroupBucket> groups,
    double bottomPad,
  ) {
    // Показываем загрузку при первоначальной загрузке
    if (tracksState.isLoading && tracksState.tracks.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _TracksLoadingState(),
          ),
        ),
      ];
    }

    // Показываем ошибку
    if (tracksState.error != null && tracksState.tracks.isEmpty) {
      final errorInfo = ErrorUtils.getErrorInfo(tracksState.error!);
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _TracksStateCard(
              icon: errorInfo.icon,
              title: errorInfo.getTitle(context),
              message: errorInfo.getMessage(context),
              iconColor: Colors.redAccent,
              actionLabel: 'Повторить',
              onAction: () {
                final params = _getFilterParams(clientCode);
                ref
                    .read(paginatedTracksProvider(clientCode))
                    .updateFilters(params);
              },
            ),
          ),
        ),
      ];
    }

    // Пустой список
    if (tracksState.tracks.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _TracksStateCard(
              icon: Icons.local_shipping_outlined,
              title: 'Ничего не найдено',
              message: 'Попробуйте изменить фильтры или строку поиска.',
            ),
          ),
        ),
      ];
    }

    final trainingActionsIndex = groups.indexWhere(
      (group) => group.assembly == null && group.tracks.length == 1,
    );
    final trainingByGroup = <int, Set<String>>{};
    final assignedTrainingTargets = <String>{};
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      final ids = <String>{};
      if (group.assembly != null) {
        ids.addAll({
          'assembly.open',
          'assembly.status',
          'assembly.tracks',
          'assembly.places',
          'assembly.delivery',
        });
      } else if (group.tracks.length == 1) {
        final track = group.tracks.single;
        ids.addAll({
          'track.open',
          'track.status',
          'track.product',
          'track.photos',
        });
        final hasQuestion =
            track.questions.any((q) => q.status != 'cancelled') ||
            (_askedQuestions[track.code] ?? '').trim().isNotEmpty;
        if ((track.status == 'В ожидании' || track.status == 'На складе') &&
            !hasQuestion) {
          ids.add('track.question');
        }
        if (track.status == 'На складе' &&
            track.statusCode == 'in_warehouse' &&
            !_returnRequestedTracks.contains(track.code)) {
          ids.add('track.return');
        }
        if (track.assembly == null &&
            (track.statusCode == 'pending' ||
                track.statusCode == 'in_warehouse') &&
            !track.questions.any(
              (q) =>
                  q.status != 'cancelled' &&
                  q.questionType == _clientCodeTransferQuestionType &&
                  q.isActive,
            )) {
          ids.add('track.transfer');
        }
        if (track.status == 'На складе' &&
            _canSelectTrackForAssembly(track, _returnRequestedTracks)) {
          ids.add('tracks.selection');
        }
      }
      trainingByGroup[i] = ids.difference(assignedTrainingTargets);
      assignedTrainingTargets.addAll(ids);
    }

    // SliverList.builder — ленивый рендеринг: только видимые карточки строятся
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPad),
        sliver: SliverList.builder(
          itemCount: groups.length + 1, // +1 для footer
          addAutomaticKeepAlives: false,
          addSemanticIndexes: false,
          itemBuilder: (context, index) {
            // Footer: индикатор загрузки, ошибка или "все загружены"
            if (index == groups.length) {
              if (tracksState.isLoading && tracksState.tracks.isNotEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (tracksState.error != null && tracksState.tracks.isNotEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: _TracksEndCard(
                    text:
                        'Не удалось загрузить всё. Потяните вниз для обновления.',
                    icon: Icons.cloud_off_rounded,
                  ),
                );
              }
              if (!tracksState.hasMore && tracksState.tracks.isNotEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: _TracksEndCard(
                    text: 'Все треки загружены',
                    icon: Icons.done_all_rounded,
                  ),
                );
              }
              return const SizedBox.shrink();
            }

            final g = groups[index];
            final isFirstAssembly =
                g.assembly != null &&
                groups.sublist(0, index).every((gr) => gr.assembly == null);
            Widget trackCard = _buildTrackGroupCard(
              g,
              tutorialActionsKey: index == trainingActionsIndex
                  ? _actionsRowKey
                  : null,
              tutorialAssemblyKey: isFirstAssembly ? _assemblyKey : null,
              trainingTargets: trainingByGroup[index] ?? const {},
            );
            final groupTargetKey = _groupTargetKey(g);
            final highlighted = _highlightedGroupKey == groupTargetKey;

            return KeyedSubtree(
              key: _keyForGroup(g),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TargetHighlightFrame(
                  highlighted: highlighted,
                  child: index == 0
                      ? KeyedSubtree(key: _trackDetailKey, child: trackCard)
                      : trackCard,
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  List<_GroupBucket> _groupTracks(List<TrackItem> tracks) {
    final byKey = <String, _GroupBucket>{};
    for (final t in tracks) {
      final key = t.groupId ?? '__${t.code}';
      byKey[key] =
          (byKey[key] ?? _GroupBucket(assembly: t.assembly, tracks: []))
            ..tracks.add(t);
    }
    final list = byKey.values.toList(growable: false);
    for (final bucket in list) {
      bucket.tracks.sort(_compareTracksBySelectedSort);
    }
    list.sort((a, b) {
      final byDate = _latestGroupDate(b).compareTo(_latestGroupDate(a));
      if (byDate != 0) return byDate;
      final aId = a.tracks.isNotEmpty ? a.tracks.first.id ?? 0 : 0;
      final bId = b.tracks.isNotEmpty ? b.tracks.first.id ?? 0 : 0;
      return bId.compareTo(aId);
    });
    return list;
  }

  int _compareTracksBySelectedSort(TrackItem a, TrackItem b) {
    final byDate = _sortDate(b).compareTo(_sortDate(a));
    if (byDate != 0) return byDate;
    return (b.id ?? 0).compareTo(a.id ?? 0);
  }

  DateTime _sortDate(TrackItem track) {
    return _sortMode == TrackSortMode.updatedAt
        ? track.updatedAt
        : track.createdAt;
  }

  DateTime _latestGroupDate(_GroupBucket bucket) {
    var latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final track in bucket.tracks) {
      final date = _sortDate(track);
      if (date.isAfter(latest)) latest = date;
    }
    return latest;
  }

  void _toggleTrack(TrackItem track) {
    final status = track.status;
    if (!_selectableStatuses.contains(status) ||
        (status == 'На складе' &&
            !_canSelectTrackForAssembly(track, _returnRequestedTracks))) {
      final hint = _assemblySelectionHint(
        context,
        track,
        _returnRequestedTracks,
      );
      if (hint != null) _showStyledSnackBar(context, hint, isError: true);
      return;
    }

    setState(() {
      if (_selectedTracks.contains(track.code)) {
        _selectedTracks.remove(track.code);
        if (_selectedTracks.isEmpty) _selectedStatus = null;
      } else {
        if (_selectedStatus == null) {
          _selectedStatus = status;
        } else if (_selectedStatus != status) {
          return;
        }
        _selectedTracks.add(track.code);
      }
    });
  }

  Future<void> _selectAll() async {
    final selectedStatus = _selectedStatus;
    if (selectedStatus == null) return;
    final clientCode = ref.read(activeClientCodeProvider);
    if (clientCode == null) return;

    final notifier = ref.read(paginatedTracksProvider(clientCode));

    // Load all remaining pages so we select every track, not just the loaded page
    if (notifier.state.hasMore) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      var iterations = 0;
      const maxIterations = 100;
      while (notifier.state.hasMore &&
          !notifier.state.isLoading &&
          iterations < maxIterations) {
        await notifier.loadMore(pageSize: 200);
        iterations++;
        if (!mounted) return;
        if (notifier.state.error != null) break;
      }
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    if (!mounted) return;
    if (notifier.state.hasMore || notifier.state.error != null) {
      _showStyledSnackBar(
        context,
        tr(
          context,
          ru: 'Не удалось загрузить все треки. Выделение не изменено — повторите действие.',
          zh: '无法加载全部运单，原有选择未改变，请重试。',
        ),
        isError: true,
      );
      return;
    }

    final allWithStatus = notifier.state.tracks
        .where(
          (t) =>
              t.status == selectedStatus &&
              (selectedStatus != 'На складе' ||
                  _canSelectTrackForAssembly(t, _returnRequestedTracks)),
        )
        .map((t) => t.code)
        .toSet();

    if (allWithStatus.isEmpty) return;

    if (!mounted) return;
    final allAlreadySelected = allWithStatus.every(_selectedTracks.contains);
    setState(() {
      if (allAlreadySelected) {
        _selectedTracks.clear();
        _selectedStatus = null;
      } else {
        _selectedTracks.addAll(allWithStatus);
      }
    });
    if (allAlreadySelected) {
      _showStyledSnackBar(context, 'Выделение треков снято');
      return;
    }
    _showStyledSnackBar(
      context,
      'Рекомендуем проверить все трек-номера перед передачей на сборку, '
      'так как будут отправлены именно те трек-номера которые были выбраны.',
    );
  }

  String _actionLabel() {
    final count = _selectedTracks.length;
    return switch (_selectedStatus) {
      'На складе' => 'Отправка на сборку ($count)',
      'Прибыл на терминал' => 'Сформировать к выдаче ($count)',
      'Сформирован к выдаче' => 'Груз получен ($count)',
      _ => 'Действие ($count)',
    };
  }

  void _bulkAction(BuildContext context) {
    final status = _selectedStatus;
    if (status == null) return;

    if (status == 'На складе') {
      _showCreateGroupSheet(context);
    } else {
      final text = switch (status) {
        'Прибыл на терминал' =>
          'Перевод в «Сформирован к выдаче» добавим следующим шагом.',
        'Сформирован к выдаче' =>
          'Подтверждение «Получен» добавим следующим шагом.',
        _ => 'Действие добавим следующим шагом.',
      };
      AppToast.showFromSnackBar(context, SnackBar(content: Text(text)));
    }
  }
}

class _TracksLoadingState extends StatelessWidget {
  const _TracksLoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _tracksPremiumCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.local_shipping_rounded,
                  color: context.brandPrimary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Загружаем треки и сборки',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Подготовим актуальные статусы и задачи',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _TrackSkeletonLine(widthFactor: 0.86),
          const SizedBox(height: 10),
          const _TrackSkeletonLine(widthFactor: 0.62),
          const SizedBox(height: 10),
          const _TrackSkeletonLine(widthFactor: 0.74),
        ],
      ),
    );
  }
}

class _TrackSkeletonLine extends StatelessWidget {
  final double widthFactor;

  const _TrackSkeletonLine({required this.widthFactor});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F7),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _TracksStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color? iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _TracksStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.iconColor,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? context.brandPrimary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _tracksPremiumCardDecoration(context),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontWeight: FontWeight.w900,
              fontSize: 17,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.25,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: context.brandPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Gilroy',
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TracksEndCard extends StatelessWidget {
  final String text;
  final IconData icon;

  const _TracksEndCard({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: context.brandPrimary, size: 16),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Gilroy',
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _tracksPremiumCardDecoration(
  BuildContext context, {
  double radius = 22,
  bool selected = false,
}) {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: selected
          ? context.brandPrimary.withValues(alpha: 0.32)
          : Colors.black.withValues(alpha: 0.045),
      width: selected ? 1.3 : 1,
    ),
    boxShadow: [
      BoxShadow(
        color: selected
            ? context.brandPrimary.withValues(alpha: 0.13)
            : Colors.black.withValues(alpha: 0.045),
        blurRadius: selected ? 24 : 18,
        spreadRadius: -9,
        offset: const Offset(0, 12),
      ),
    ],
  );
}

class _TargetHighlightFrame extends StatelessWidget {
  final bool highlighted;
  final Widget child;

  const _TargetHighlightFrame({required this.highlighted, required this.child});

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: highlighted ? const EdgeInsets.all(3) : EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: highlighted
            ? Border.all(color: accent.withValues(alpha: 0.38), width: 1.4)
            : null,
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.20),
                  blurRadius: 26,
                  spreadRadius: -8,
                  offset: const Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

enum ViewMode { all, groups, singles }

enum ProductInfoMode { all, filled, empty }

enum DeliveryInfoMode { all, filled, empty }

enum TrackSortMode { createdAt, updatedAt }

extension TrackSortModeX on TrackSortMode {
  String get queryValue => switch (this) {
    TrackSortMode.createdAt => 'createdAt',
    TrackSortMode.updatedAt => 'updatedAt',
  };

  String get label => switch (this) {
    TrackSortMode.createdAt => 'По дате добавления',
    TrackSortMode.updatedAt => 'По дате изменения',
  };
}

class _TracksHeroHeader extends StatelessWidget {
  const _TracksHeroHeader();

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(24);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: context.brandPrimary.withValues(alpha: 0.22),
            blurRadius: 28,
            spreadRadius: -12,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            const Positioned.fill(child: _TracksHeaderGlowBackdrop()),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: const Icon(
                      Icons.local_shipping_rounded,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Треки и сборки',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Gilroy',
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                            height: 1.04,
                            letterSpacing: -0.35,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Управляйте посылками, сборками и задачами склада',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xE6FFFFFF),
                            fontFamily: 'Gilroy',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            height: 1.18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TracksHeaderGlowBackdrop extends StatefulWidget {
  const _TracksHeaderGlowBackdrop();

  @override
  State<_TracksHeaderGlowBackdrop> createState() =>
      _TracksHeaderGlowBackdropState();
}

class _TracksHeaderGlowBackdropState extends State<_TracksHeaderGlowBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat(reverse: true);
    _settleAfter(const Duration(seconds: 9));
  }

  void _settleAfter(Duration activeFor) {
    Future<void>.delayed(activeFor, () {
      if (!mounted || !_controller.isAnimating) return;
      _controller.animateTo(
        0.5,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final wave = Curves.easeInOutCubic.transform(_controller.value);
            final shift = (wave * 2) - 1;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -62,
                  top: -58,
                  child: Transform.translate(
                    offset: Offset(-10 * shift, 6 * shift),
                    child: _TracksHeaderGlowCircle(
                      size: 154,
                      color: Colors.white.withValues(alpha: 0.13),
                    ),
                  ),
                ),
                Positioned(
                  right: 22,
                  bottom: -68,
                  child: Transform.translate(
                    offset: Offset(9 * shift, -7 * shift),
                    child: _TracksHeaderGlowCircle(
                      size: 152,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  right: -14,
                  bottom: 16,
                  child: Transform.translate(
                    offset: Offset(5 * shift, -4 * shift),
                    child: _TracksHeaderGlowCircle(
                      size: 82,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TracksHeaderGlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _TracksHeaderGlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;
    final color = isActive ? accent : AppColors.textSecondary;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isActive
                  ? accent.withValues(alpha: 0.10)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive
                    ? accent.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.035),
              ),
            ),
            child: Center(child: Icon(icon, size: 21, color: color)),
          ),
        ),
      ),
    );
  }
}

class _HeaderAddTrackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HeaderAddTrackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Добавить треки',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: context.brandGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: context.brandPrimary.withValues(alpha: 0.20),
                  blurRadius: 14,
                  spreadRadius: -7,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.add_rounded, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

class _TracksViewModeSwitch extends StatelessWidget {
  final ViewMode value;
  final ValueChanged<ViewMode> onChanged;

  const _TracksViewModeSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TrainingTarget(
              id: value == ViewMode.singles
                  ? 'tracks.view.singles.active'
                  : 'tracks.view.switch-to-singles',
              onActivate: value != ViewMode.singles
                  ? () => onChanged(ViewMode.singles)
                  : null,
              child: _TracksViewModeSegment(
                icon: Icons.local_shipping_rounded,
                label: 'Треки',
                selected: value == ViewMode.singles,
                onTap: () => onChanged(ViewMode.singles),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TrainingTarget(
              id: 'tracks.view.groups',
              child: TrainingTarget(
                id: value == ViewMode.groups
                    ? 'tracks.view.groups.active'
                    : 'tracks.view.switch-to-groups',
                onActivate: value != ViewMode.groups
                    ? () => onChanged(ViewMode.groups)
                    : null,
                child: _TracksViewModeSegment(
                  icon: Icons.inventory_2_rounded,
                  label: 'Сборки',
                  selected: value == ViewMode.groups,
                  onTap: () => onChanged(ViewMode.groups),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TracksViewModeSegment extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TracksViewModeSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected ? context.brandGradient : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(15),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: context.brandPrimary.withValues(alpha: 0.18),
                      blurRadius: 12,
                      spreadRadius: -7,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Gilroy',
                  fontSize: 14,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : AppColors.textPrimary,
                  letterSpacing: -0.05,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TracksSearchField extends StatefulWidget {
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _TracksSearchField({
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  State<_TracksSearchField> createState() => _TracksSearchFieldState();
}

class _TracksSearchFieldState extends State<_TracksSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _TracksSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query && _controller.text != widget.query) {
      _controller.text = widget.query;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppOutlinedInputFrame(
      height: 48,
      radius: 16,
      fillColor: const Color(0xFFF8FAFC),
      borderColor: const Color(0xFFE3E7EE),
      builder: (context, focusNode) => TextField(
        focusNode: focusNode,
        controller: _controller,
        style: const TextStyle(
          fontFamily: 'Gilroy',
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          prefixIcon: focusNode.hasFocus
              ? null
              : Icon(
                  Icons.search_rounded,
                  color: context.brandPrimary,
                  size: 22,
                ),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _controller.clear();
                    setState(() {});
                    widget.onClear();
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                )
              : null,
          hintText: tr(
            context,
            ru: 'Трек, товар, сборка, заметка',
            zh: '单号、商品、打包、备注',
          ),
          hintStyle: const TextStyle(
            fontFamily: 'Gilroy',
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            letterSpacing: 0,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(
            focusNode.hasFocus ? 16 : 0,
            14,
            12,
            14,
          ),
          isDense: true,
        ),
        onChanged: (value) {
          setState(() {});
          widget.onChanged(value);
        },
      ),
    );
  }
}

class _TrackSheetSurface extends TrackSheetSurface {
  const _TrackSheetSurface({
    required super.icon,
    required super.title,
    required super.subtitle,
    required super.child,
    super.pinnedChild,
    super.footer,
    super.contentPadding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    super.keyboardAware = false,
    super.scrollController,
    super.useMaxHeight = false,
  });
}

class _TrackSortSheet extends StatelessWidget {
  final TrackSortMode selected;

  const _TrackSortSheet({required this.selected});

  @override
  Widget build(BuildContext context) {
    return _TrackSheetSurface(
      icon: Icons.swap_vert_rounded,
      title: 'Сортировка',
      subtitle: 'Выберите порядок отображения треков и сборок',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final mode in TrackSortMode.values) ...[
            _SheetOptionTile(
              icon: mode == TrackSortMode.createdAt
                  ? CupertinoIcons.plus_circle
                  : CupertinoIcons.arrow_2_circlepath_circle,
              title: mode.label,
              subtitle: mode == TrackSortMode.createdAt
                  ? 'Сначала недавно добавленные посылки'
                  : 'Сначала недавно изменённые статусы',
              selected: mode == selected,
              onTap: () => Navigator.pop(context, mode),
            ),
            if (mode != TrackSortMode.values.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _TrackFiltersResult {
  final String? statusCode;
  final ProductInfoMode productInfoMode;
  final String? photoRequestStatusCode;
  final String? questionStatusCode;
  final DeliveryInfoMode deliveryInfoMode;

  const _TrackFiltersResult({
    required this.statusCode,
    required this.productInfoMode,
    required this.photoRequestStatusCode,
    required this.questionStatusCode,
    required this.deliveryInfoMode,
  });
}

class _StatusOption {
  final String? code;
  final String label;

  const _StatusOption({required this.code, required this.label});
}

class _TrackFiltersSheet extends StatefulWidget {
  final String? statusCode;
  final ViewMode viewMode;
  final List<TrackItem> tracks;
  final List<TrackStatus> trackStatuses;
  final List<TrackStatus> assemblyStatuses;
  final List<TrackStatus> photoRequestStatuses;
  final List<TrackStatus> questionStatuses;
  final ProductInfoMode productInfoMode;
  final String? photoRequestStatusCode;
  final String? questionStatusCode;
  final DeliveryInfoMode deliveryInfoMode;

  const _TrackFiltersSheet({
    required this.statusCode,
    required this.viewMode,
    required this.tracks,
    required this.trackStatuses,
    required this.assemblyStatuses,
    required this.photoRequestStatuses,
    required this.questionStatuses,
    required this.productInfoMode,
    required this.photoRequestStatusCode,
    required this.questionStatusCode,
    required this.deliveryInfoMode,
  });

  @override
  State<_TrackFiltersSheet> createState() => _TrackFiltersSheetState();
}

class _TrackFiltersSheetState extends State<_TrackFiltersSheet> {
  static const _noneStatusCode = 'none';

  late String? _statusCode = widget.statusCode;
  late ProductInfoMode _productInfoMode = widget.productInfoMode;
  late String? _photoRequestStatusCode = widget.photoRequestStatusCode;
  late String? _questionStatusCode = widget.questionStatusCode;
  late DeliveryInfoMode _deliveryInfoMode = widget.deliveryInfoMode;

  @override
  Widget build(BuildContext context) {
    final isAssemblyMode = widget.viewMode == ViewMode.groups;
    final statusOptions = _buildStatusOptions();
    final photoRequestOptions = _buildTaskStatusOptions(
      widget.photoRequestStatuses,
      _fallbackPhotoRequestStatuses(),
      noneLabel: 'Без запроса',
    );
    final questionOptions = _buildTaskStatusOptions(
      widget.questionStatuses,
      _fallbackQuestionStatuses(),
      noneLabel: 'Без вопроса',
    );

    return _TrackSheetSurface(
      icon: Icons.filter_alt_rounded,
      title: 'Фильтр',
      subtitle: isAssemblyMode
          ? 'Настройте статусы и заполненность доставки'
          : 'Быстро отберите треки по статусу, товару и задачам',
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      footer: Row(
        children: [
          Expanded(
            child: _TrackSheetSecondaryButton(
              label: 'Сбросить',
              onTap: () => Navigator.pop(
                context,
                const _TrackFiltersResult(
                  statusCode: null,
                  productInfoMode: ProductInfoMode.all,
                  photoRequestStatusCode: null,
                  questionStatusCode: null,
                  deliveryInfoMode: DeliveryInfoMode.all,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TrackSheetPrimaryButton(
              label: 'Применить',
              icon: Icons.check_rounded,
              onTap: () => Navigator.pop(
                context,
                _TrackFiltersResult(
                  statusCode: _statusCode,
                  productInfoMode: _productInfoMode,
                  photoRequestStatusCode: _photoRequestStatusCode,
                  questionStatusCode: _questionStatusCode,
                  deliveryInfoMode: _deliveryInfoMode,
                ),
              ),
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TrainingTarget(
            id: 'tracks.statuses',
            child: _TrackFilterSectionCard(
              icon: Icons.flag_rounded,
              title: 'Статус',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in statusOptions)
                    _FilterChipButton(
                      label: option.label,
                      selected: option.code == _statusCode,
                      onTap: () => setState(() => _statusCode = option.code),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (isAssemblyMode)
            _TrackFilterSectionCard(
              icon: Icons.local_shipping_rounded,
              title: 'Данные доставки',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChipButton(
                    label: 'Все',
                    selected: _deliveryInfoMode == DeliveryInfoMode.all,
                    onTap: () => setState(
                      () => _deliveryInfoMode = DeliveryInfoMode.all,
                    ),
                  ),
                  _FilterChipButton(
                    label: 'Заполнены',
                    selected: _deliveryInfoMode == DeliveryInfoMode.filled,
                    onTap: () => setState(
                      () => _deliveryInfoMode = DeliveryInfoMode.filled,
                    ),
                  ),
                  _FilterChipButton(
                    label: 'Не заполнены',
                    selected: _deliveryInfoMode == DeliveryInfoMode.empty,
                    onTap: () => setState(
                      () => _deliveryInfoMode = DeliveryInfoMode.empty,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _TrackFilterSectionCard(
              icon: Icons.inventory_2_rounded,
              title: 'О товаре',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FilterChipButton(
                    label: 'Все',
                    selected: _productInfoMode == ProductInfoMode.all,
                    onTap: () =>
                        setState(() => _productInfoMode = ProductInfoMode.all),
                  ),
                  _FilterChipButton(
                    label: 'Заполнено',
                    selected: _productInfoMode == ProductInfoMode.filled,
                    onTap: () => setState(
                      () => _productInfoMode = ProductInfoMode.filled,
                    ),
                  ),
                  _FilterChipButton(
                    label: 'Пусто',
                    selected: _productInfoMode == ProductInfoMode.empty,
                    onTap: () => setState(
                      () => _productInfoMode = ProductInfoMode.empty,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _TrackFilterSectionCard(
              icon: Icons.photo_camera_rounded,
              title: 'Фотоотчёт',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in photoRequestOptions)
                    _FilterChipButton(
                      label: option.label,
                      selected: option.code == _photoRequestStatusCode,
                      onTap: () =>
                          setState(() => _photoRequestStatusCode = option.code),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _TrackFilterSectionCard(
              icon: Icons.help_rounded,
              title: 'Вопросы',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in questionOptions)
                    _FilterChipButton(
                      label: option.label,
                      selected: option.code == _questionStatusCode,
                      onTap: () =>
                          setState(() => _questionStatusCode = option.code),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<_StatusOption> _buildStatusOptions() {
    final options = <_StatusOption>[
      const _StatusOption(code: null, label: 'Все'),
    ];
    final added = <String>{};
    final isAssemblyMode = widget.viewMode == ViewMode.groups;
    final statuses = isAssemblyMode
        ? widget.assemblyStatuses
        : widget.trackStatuses;

    for (final status in statuses) {
      if (status.code.isEmpty || added.contains(status.code)) continue;
      added.add(status.code);
      options.add(_StatusOption(code: status.code, label: status.nameRu));
    }

    for (final track in widget.tracks) {
      if (isAssemblyMode) {
        final assembly = track.assembly;
        if (assembly == null ||
            assembly.status.isEmpty ||
            added.contains(assembly.status)) {
          continue;
        }
        added.add(assembly.status);
        options.add(
          _StatusOption(
            code: assembly.status,
            label: assembly.statusName?.isNotEmpty == true
                ? assembly.statusName!
                : assembly.status,
          ),
        );
      } else {
        if (track.statusCode.isEmpty || added.contains(track.statusCode)) {
          continue;
        }
        added.add(track.statusCode);
        options.add(_StatusOption(code: track.statusCode, label: track.status));
      }
    }

    return options;
  }

  List<_StatusOption> _buildTaskStatusOptions(
    List<TrackStatus> statuses,
    Map<String, String> fallbackStatuses, {
    required String noneLabel,
  }) {
    final options = <_StatusOption>[
      const _StatusOption(code: null, label: 'Все'),
      _StatusOption(code: _noneStatusCode, label: noneLabel),
    ];
    final added = <String>{_noneStatusCode};

    for (final status in statuses) {
      if (status.code.isEmpty || added.contains(status.code)) continue;
      added.add(status.code);
      options.add(_StatusOption(code: status.code, label: status.nameRu));
    }

    for (final entry in fallbackStatuses.entries) {
      if (entry.key.isEmpty || added.contains(entry.key)) continue;
      added.add(entry.key);
      options.add(_StatusOption(code: entry.key, label: entry.value));
    }

    return options;
  }

  Map<String, String> _fallbackPhotoRequestStatuses() {
    final statuses = <String, String>{
      'new': 'Новый',
      'at_warehouse': 'На складе',
      'in_progress': 'Передан в работу',
      'assigned': 'Назначен ответственный',
      'completed': 'Выполнен',
      'cancelled': 'Отменён',
    };
    for (final track in widget.tracks) {
      for (final request in track.photoRequests) {
        statuses[request.status] = request.statusLabel;
      }
    }
    return statuses;
  }

  Map<String, String> _fallbackQuestionStatuses() {
    final statuses = <String, String>{
      'new': 'Новый',
      'at_warehouse': 'На складе',
      'in_progress': 'Передан в работу',
      'assigned': 'Назначен ответственный',
      'completed': 'Отвечен',
      'cancelled': 'Отменён',
    };
    for (final track in widget.tracks) {
      for (final question in track.questions) {
        statuses[question.status] = question.statusLabel;
      }
    }
    return statuses;
  }
}

class _TrackFilterSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _TrackFilterSectionCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: context.brandPrimary, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 14.5,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.05,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _TrackDetailEmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TrackDetailEmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: context.brandPrimary, size: 23),
          ),
          const SizedBox(height: 11),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 13.5,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackSheetNoticeCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _TrackSheetNoticeCard({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withValues(alpha: 0.92),
                fontFamily: 'Gilroy',
                fontSize: 12.8,
                height: 1.22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackSheetMetaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final int valueMaxLines;

  const _TrackSheetMetaCard({
    required this.icon,
    required this.title,
    required this.value,
    this.valueMaxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: context.brandPrimary, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 12.2,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: valueMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 15.5,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            gradient: selected ? context.brandGradient : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? context.brandPrimary.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.045),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: context.brandPrimary.withValues(alpha: 0.16),
                      blurRadius: 12,
                      spreadRadius: -8,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Gilroy',
              fontSize: 12.8,
              height: 1,
              fontWeight: FontWeight.w900,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetOptionTile extends TrackSheetOptionTile {
  const _SheetOptionTile({
    required super.icon,
    required super.title,
    required super.subtitle,
    required super.selected,
    required super.onTap,
  });
}

class _TrackSheetPrimaryButton extends TrackSheetPrimaryButton {
  const _TrackSheetPrimaryButton({
    required super.label,
    required super.icon,
    required super.onTap,
  });
}

class _TrackSheetSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TrackSheetSecondaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.brandPrimary.withValues(alpha: 0.24),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: context.brandPrimary,
              fontFamily: 'Gilroy',
              fontSize: 14,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackSheetCompactAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TrackSheetCompactAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;
    return SizedBox(
      width: 132,
      height: 64,
      child: Material(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 19, color: accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: accent,
                      fontFamily: 'Gilroy',
                      fontSize: 12.5,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssemblyCompactCard extends StatelessWidget {
  final String number;
  final Set<String> trainingTargets;
  final String? name;
  final String status;
  final Color? statusColor;
  final int trackCount;
  final int boxCount;
  final bool hasDelivery;
  final bool canEditDelivery;
  final ValueChanged<int> onOpen;
  final VoidCallback onComment;
  final VoidCallback onDelivery;

  const _AssemblyCompactCard({
    this.trainingTargets = const {},
    required this.number,
    required this.name,
    required this.status,
    required this.statusColor,
    required this.trackCount,
    required this.boxCount,
    required this.hasDelivery,
    required this.canEditDelivery,
    required this.onOpen,
    required this.onComment,
    required this.onDelivery,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;
    String? target(String id) => trainingTargets.contains(id) ? id : null;
    return ClientTrackCompactCard(
      trainingOpenId: target('assembly.open'),
      trainingStatusId: target('assembly.status'),
      trackNumber: number,
      status: status,
      statusColor: statusColor ?? accent,
      productName: name ?? '',
      selectable: false,
      selected: false,
      onToggleSelection: null,
      onCopyTrack: () {},
      onOpenDetails: onOpen,
      entityLabel: 'Сборка',
      leadingIcon: Icons.inventory_2_rounded,
      showCopyAction: false,
      indicators: [
        ClientTrackIndicator(
          icon: Icons.local_shipping_outlined,
          trainingTargetId: target('assembly.tracks'),
          title: 'Треки',
          value: '$trackCount',
          label: 'Треки',
          color: trackCount > 0 ? accent : AppColors.textSecondary,
          tabIndex: 4,
        ),
        ClientTrackIndicator(
          icon: Icons.inventory_2_outlined,
          trainingTargetId: target('assembly.places'),
          title: 'Места',
          value: '$boxCount',
          label: 'Места',
          color: boxCount > 0 ? Colors.green : AppColors.textSecondary,
          tabIndex: 3,
        ),
        ClientTrackIndicator(
          icon: Icons.local_shipping_rounded,
          trainingTargetId: target('assembly.delivery'),
          title: 'Доставка',
          value: hasDelivery ? 'Выбрана' : '',
          label: 'Доставка',
          color: hasDelivery ? Colors.green : AppColors.textSecondary,
          tabIndex: 2,
        ),
      ],
      actions: [
        ClientTrackQuickAction(
          icon: Icons.sticky_note_2_outlined,
          label: 'Заметка',
          onTap: onComment,
        ),
        if (canEditDelivery)
          ClientTrackQuickAction(
            icon: Icons.local_shipping_outlined,
            label: 'Доставка',
            onTap: onDelivery,
          ),
      ],
    );
  }
}

typedef _InlineAssemblyDeliverySaver =
    Future<bool> Function({
      required String deliveryMethod,
      String? recipientName,
      String? recipientPhone,
      String? recipientCity,
      String? transportCompanyName,
    });

class _AssemblyDeliveryEditor extends StatefulWidget {
  final TrackAssembly assembly;
  final _InlineAssemblyDeliverySaver onSave;

  const _AssemblyDeliveryEditor({required this.assembly, required this.onSave});

  @override
  State<_AssemblyDeliveryEditor> createState() =>
      _AssemblyDeliveryEditorState();
}

class _AssemblyDeliveryEditorState extends State<_AssemblyDeliveryEditor> {
  late String? _selectedMethod;
  late final TextEditingController _nameController;
  late final TextEditingController _cityController;
  late final TextEditingController _transportCompanyController;
  late final PhoneController _phoneController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.assembly.deliveryMethod;
    _nameController = TextEditingController(
      text: widget.assembly.recipientName ?? '',
    );
    _cityController = TextEditingController(
      text: widget.assembly.recipientCity ?? '',
    );
    _transportCompanyController = TextEditingController(
      text: widget.assembly.transportCompanyName ?? '',
    );
    _phoneController = PhoneController(
      initialValue:
          PhoneInputField.parse(widget.assembly.recipientPhone) ??
          const PhoneNumber(isoCode: IsoCode.RU, nsn: ''),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _transportCompanyController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    _showStyledSnackBar(context, message, isError: true);
  }

  Future<void> _save() async {
    final method = _selectedMethod;
    if (!widget.assembly.canEditDelivery || method == null || _saving) return;
    if (method == 'transport_company') {
      if (_nameController.text.trim().isEmpty) {
        _showError(tr(context, ru: 'Укажите ФИО получателя', zh: '请输入收货人姓名'));
        return;
      }
      final phone = _phoneController.value;
      if (phone.nsn.trim().isEmpty) {
        _showError(
          tr(context, ru: 'Укажите телефон получателя', zh: '请输入收货人电话'),
        );
        return;
      }
      if (!phone.isValid()) {
        _showError(
          tr(
            context,
            ru: 'Введите корректный номер телефона',
            zh: '请输入有效的电话号码',
          ),
        );
        return;
      }
      if (_cityController.text.trim().isEmpty) {
        _showError(tr(context, ru: 'Укажите город получателя', zh: '请输入收货城市'));
        return;
      }
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    await widget.onSave(
      deliveryMethod: method,
      recipientName: _nameController.text.trim(),
      recipientPhone: _phoneController.value.international,
      recipientCity: _cityController.text.trim(),
      transportCompanyName: _transportCompanyController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final canEditDelivery = widget.assembly.canEditDelivery;
    final isTransport = _selectedMethod == 'transport_company';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!canEditDelivery) ...[
          _TrackSheetNoticeCard(
            icon: Icons.lock_outline_rounded,
            text: tr(
              context,
              ru: 'Сборка уже доставлена. Способ получения и данные получателя доступны только для просмотра.',
              zh: '集运单已送达。收货方式和收件人信息仅可查看。',
            ),
            color: AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
        ],
        _TrackFilterSectionCard(
          icon: Icons.delivery_dining_rounded,
          title: tr(context, ru: 'Вариант получения', zh: '收货方式'),
          child: Column(
            children: [
              _DeliveryOptionCard(
                key: const ValueKey('assembly-delivery-option-self_pickup'),
                title: tr(context, ru: 'Самовывоз', zh: '自提'),
                subtitle: tr(
                  context,
                  ru: 'Забрать груз на терминале склада',
                  zh: '前往仓库站点提货',
                ),
                icon: Icons.storefront_rounded,
                isSelected: _selectedMethod == 'self_pickup',
                enabled: canEditDelivery,
                onTap: () => setState(() => _selectedMethod = 'self_pickup'),
              ),
              const SizedBox(height: 10),
              _DeliveryOptionCard(
                key: const ValueKey(
                  'assembly-delivery-option-transport_company',
                ),
                title: tr(context, ru: 'Транспортная компания', zh: '物流公司'),
                subtitle: tr(
                  context,
                  ru: 'Передадим груз выбранной ТК',
                  zh: '将货物交给您选择的物流公司',
                ),
                icon: Icons.local_shipping_rounded,
                isSelected: isTransport,
                enabled: canEditDelivery,
                onTap: () =>
                    setState(() => _selectedMethod = 'transport_company'),
              ),
            ],
          ),
        ),
        if (_selectedMethod == 'self_pickup') ...[
          const SizedBox(height: 12),
          _TrackSheetNoticeCard(
            icon: Icons.warning_amber_rounded,
            text: tr(
              context,
              ru: 'Доступ на терминал платный. Для уточнения условий свяжитесь с поддержкой.',
              zh: '进入站点需付费，详情请联系客服。',
            ),
            color: Colors.amber.shade800,
          ),
        ],
        if (isTransport) ...[
          const SizedBox(height: 12),
          _TrackFilterSectionCard(
            icon: Icons.apartment_rounded,
            title: tr(context, ru: 'Транспортная компания', zh: '物流公司'),
            child: _outlinedInput(
              context,
              _transportCompanyController,
              hint: tr(
                context,
                ru: 'Название ТК (СДЭК, ПЭК и т. д.)',
                zh: '物流公司名称（如СДЭК、ПЭК等）',
              ),
              enabled: canEditDelivery,
            ),
          ),
          const SizedBox(height: 12),
          _TrackFilterSectionCard(
            icon: Icons.person_rounded,
            title: tr(context, ru: 'Данные получателя', zh: '收货人信息'),
            child: Column(
              children: [
                _outlinedInput(
                  context,
                  _nameController,
                  hint: tr(context, ru: 'ФИО получателя', zh: '收货人姓名'),
                  enabled: canEditDelivery,
                ),
                const SizedBox(height: 10),
                PhoneInputField(
                  controller: _phoneController,
                  gradientFrame: true,
                  enabled: canEditDelivery,
                  isRequired: true,
                  hintText: tr(context, ru: 'Телефон получателя', zh: '收货人电话'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                _outlinedInput(
                  context,
                  _cityController,
                  hint: tr(context, ru: 'Город', zh: '城市'),
                  textInputAction: TextInputAction.done,
                  enabled: canEditDelivery,
                ),
              ],
            ),
          ),
        ],
        if (canEditDelivery) ...[
          const SizedBox(height: 12),
          _TrackSheetPrimaryButton(
            label: _saving
                ? tr(context, ru: 'Сохраняем…', zh: '正在保存…')
                : tr(context, ru: 'Сохранить доставку', zh: '保存收货方式'),
            icon: Icons.check_rounded,
            onTap: _selectedMethod == null || _saving ? null : _save,
          ),
        ],
      ],
    );
  }
}

class _AssemblyDetailTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _AssemblyDetailTabs({
    required this.selectedIndex,
    required this.onSelected,
  });

  static const labels = ['Основное', 'Видео', 'Доставка', 'Места', 'Треки'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < labels.length; index++) ...[
              if (index > 0) const SizedBox(width: 6),
              TrainingTarget(
                id: 'assembly.tab.${const ['main', 'video', 'delivery', 'places', 'tracks'][index]}',
                onActivate: selectedIndex != index
                    ? () => onSelected(index)
                    : null,
                child: _AssemblyDetailTabButton(
                  label: labels[index],
                  selected: selectedIndex == index,
                  onTap: () => onSelected(index),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AssemblyDetailTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AssemblyDetailTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.brandPrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _Filters extends StatefulWidget {
  final String status;
  final List<String> statuses;
  final ViewMode viewMode;
  final String query;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<ViewMode> onViewModeChanged;
  final ValueChanged<String> onQueryChanged;

  const _Filters({
    required this.status,
    required this.statuses,
    required this.viewMode,
    required this.query,
    required this.onStatusChanged,
    required this.onViewModeChanged,
    required this.onQueryChanged,
  });

  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _Filters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query &&
        _searchController.text != widget.query) {
      _searchController.text = widget.query;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppSearchField(
          controller: _searchController,
          hintText: tr(
            context,
            ru: 'Трек, товар, сборка, заметка',
            zh: '单号、商品、打包、备注',
          ),
          onChanged: (value) {
            setState(() {});
            widget.onQueryChanged(value);
          },
          onClear: () {
            _searchController.selection = const TextSelection.collapsed(
              offset: 0,
            );
            widget.onQueryChanged('');
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TrainingTarget(
                id: 'tracks.view.selector',
                child: _CustomDropdown<ViewMode>(
                  value: widget.viewMode,
                  label: 'Вид',
                  items: const [
                    _DropdownItem(value: ViewMode.all, label: 'Все'),
                    _DropdownItem(value: ViewMode.groups, label: 'Сборки'),
                    _DropdownItem(value: ViewMode.singles, label: 'Одиночные'),
                  ],
                  onChanged: (v) =>
                      v != null ? widget.onViewModeChanged(v) : null,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CustomDropdown<String>(
                value: widget.status,
                label: 'Статус',
                items: widget.statuses
                    .map((s) => _DropdownItem(value: s, label: s))
                    .toList(),
                onChanged: (v) => v != null ? widget.onStatusChanged(v) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Новый виджет фильтров со статусами из БД
class _FiltersNew extends StatefulWidget {
  final String? statusCode; // null = Все
  final List<TrackItem> tracks; // Извлекаем статусы из треков
  final ViewMode viewMode;
  final ProductInfoMode productInfoMode;
  final String query;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<ViewMode> onViewModeChanged;
  final ValueChanged<ProductInfoMode> onProductInfoModeChanged;
  final ValueChanged<String> onQueryChanged;
  const _FiltersNew({
    required this.statusCode,
    required this.tracks,
    required this.viewMode,
    required this.productInfoMode,
    required this.query,
    required this.onStatusChanged,
    required this.onViewModeChanged,
    required this.onProductInfoModeChanged,
    required this.onQueryChanged,
  });

  @override
  State<_FiltersNew> createState() => _FiltersNewState();
}

class _FiltersNewState extends State<_FiltersNew> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _FiltersNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query &&
        _searchController.text != widget.query) {
      _searchController.text = widget.query;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Извлекаем уникальные статусы из загруженных треков
    final uniqueStatuses = <String, String>{};
    for (final track in widget.tracks) {
      if (track.statusCode.isNotEmpty &&
          !uniqueStatuses.containsKey(track.statusCode)) {
        uniqueStatuses[track.statusCode] = track.status;
      }
    }

    // Формируем список статусов для dropdown
    final statusItems = <_DropdownItem<String?>>[
      const _DropdownItem(value: null, label: 'Все'),
      ...uniqueStatuses.entries.map(
        (e) => _DropdownItem(value: e.key, label: e.value),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Поиск — занимает оставшееся место
        AppSearchField(
          controller: _searchController,
          hintText: tr(
            context,
            ru: 'Трек, товар, сборка, заметка',
            zh: '单号、商品、打包、备注',
          ),
          onChanged: (value) {
            setState(() {});
            widget.onQueryChanged(value);
          },
          onClear: () {
            _searchController.selection = const TextSelection.collapsed(
              offset: 0,
            );
            widget.onQueryChanged('');
          },
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Вид
              TrainingTarget(
                id: 'tracks.view.selector',
                child: _MiniDropdown<ViewMode>(
                  value: widget.viewMode,
                  items: const [
                    _DropdownItem(value: ViewMode.all, label: 'Все'),
                    _DropdownItem(value: ViewMode.groups, label: 'Сборки'),
                    _DropdownItem(value: ViewMode.singles, label: 'Одиночные'),
                  ],
                  onChanged: (v) =>
                      v != null ? widget.onViewModeChanged(v) : null,
                ),
              ),
              const SizedBox(width: 6),
              // Статус
              _MiniDropdown<String?>(
                value: widget.statusCode,
                items: statusItems,
                onChanged: (v) => widget.onStatusChanged(v),
              ),
              const SizedBox(width: 6),
              _MiniDropdown<ProductInfoMode>(
                value: widget.productInfoMode,
                items: const [
                  _DropdownItem(
                    value: ProductInfoMode.all,
                    label: 'О товаре: все',
                  ),
                  _DropdownItem(
                    value: ProductInfoMode.filled,
                    label: 'О товаре: заполнено',
                  ),
                  _DropdownItem(
                    value: ProductInfoMode.empty,
                    label: 'О товаре: пусто',
                  ),
                ],
                onChanged: (v) =>
                    v != null ? widget.onProductInfoModeChanged(v) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

typedef _AssemblyDeliverySaver =
    Future<bool> Function(
      TrackAssembly assembly, {
      required String deliveryMethod,
      String? recipientName,
      String? recipientPhone,
      String? recipientCity,
      String? transportCompanyName,
    });

class _TrackGroupCard extends StatefulWidget {
  final TrackAssembly? assembly;
  final List<TrackItem> tracks;
  final List<TrackStatus> trackStatuses;
  final List<TrackStatus> assemblyStatuses;
  final Set<String> selectedTrackCodes;
  final String? selectedStatus;
  final bool allowSelection;
  final ValueChanged<TrackItem> onToggle;
  final Set<String> requestedPhotoReports;
  final ValueChanged<TrackItem> onPhotoRequest;
  final Future<bool> Function(TrackItem track, String wish)
  onRequestPhotoInline;
  final ValueChanged<TrackItem> onCancelPhotoRequest;
  final ValueChanged<TrackItem> onEditPhotoWish;
  final Future<bool> Function(TrackItem track, String wish)
  onUpdatePhotoWishInline;
  final Map<String, DateTime> photoRequestCreatedAt;
  final Map<String, DateTime> photoRequestUpdatedAt;
  final Map<String, String> photoRequestNotes;
  final Map<String, String> overrideComments;
  final ValueChanged<TrackItem> onAskQuestion;
  final Future<bool> Function(TrackItem track) onAskQuestionInline;
  final ValueChanged<TrackItem> onTransferClientCode;
  final ValueChanged<TrackItem> onCancelQuestion;
  final ValueChanged<TrackItem> onEditComment;
  final Future<bool> Function(TrackItem track, String comment) onSaveComment;
  final ValueChanged<TrackItem> onEditProduct;
  final Future<bool> Function(
    TrackItem track,
    String name,
    int quantity,
    List<String> images,
    XFile? newImage,
  )
  onSaveProduct;
  final Map<String, String> askedQuestions;
  final Map<String, DateTime> questionCreatedAt;
  final Map<String, DateTime> questionUpdatedAt;
  final Map<String, String> questionStatus;
  final Map<String, String> questionAnswers;
  final Map<String, _ProductInfo> productInfos;
  final Map<String, String> groupComments;
  final Map<String, String> groupQuestions;
  final Map<String, DateTime> groupQuestionCreatedAt;
  final Map<String, DateTime> groupQuestionUpdatedAt;
  final ValueChanged<TrackAssembly> onEditGroupComment;
  final ValueChanged<TrackAssembly> onAskGroupQuestion;
  final ValueChanged<TrackAssembly> onSelectDelivery;
  final _AssemblyDeliverySaver onSaveDelivery;
  final Future<bool> Function(TrackAssembly assembly) onConfirmAssemblyReceipt;
  final ValueChanged<TrackItem> onDeleteTrack;
  final ValueChanged<TrackItem> onReturnRequest;
  final Future<bool> Function(TrackItem track, String returnCode)
  onRequestReturnInline;
  final ValueChanged<TrackItem> onWarehouseDelivery;
  final Future<TrackReturnInfo?> Function(int trackId) onLoadReturn;
  final Future<TrackReturnInfo?> Function(int trackId, String returnCode)
  onUpdateReturnCode;
  final Future<bool> Function(TrackItem track) onConfirmCompletedReturn;
  final Set<String> returnRequestedTracks;
  final GlobalKey? tutorialActionsKey;
  final GlobalKey? tutorialAssemblyKey;
  final Set<String> trainingTargets;

  const _TrackGroupCard({
    this.trainingTargets = const {},
    required this.assembly,
    required this.tracks,
    required this.trackStatuses,
    required this.assemblyStatuses,
    required this.selectedTrackCodes,
    required this.selectedStatus,
    required this.allowSelection,
    required this.onToggle,
    required this.requestedPhotoReports,
    required this.onPhotoRequest,
    required this.onRequestPhotoInline,
    required this.onCancelPhotoRequest,
    required this.onEditPhotoWish,
    required this.onUpdatePhotoWishInline,
    required this.photoRequestCreatedAt,
    required this.photoRequestUpdatedAt,
    required this.photoRequestNotes,
    required this.overrideComments,
    required this.onAskQuestion,
    required this.onAskQuestionInline,
    required this.onTransferClientCode,
    required this.onCancelQuestion,
    required this.onEditComment,
    required this.onSaveComment,
    required this.onEditProduct,
    required this.onSaveProduct,
    required this.askedQuestions,
    required this.questionCreatedAt,
    required this.questionUpdatedAt,
    required this.questionStatus,
    required this.questionAnswers,
    required this.productInfos,
    required this.groupComments,
    required this.groupQuestions,
    required this.groupQuestionCreatedAt,
    required this.groupQuestionUpdatedAt,
    required this.onEditGroupComment,
    required this.onAskGroupQuestion,
    required this.onSelectDelivery,
    required this.onSaveDelivery,
    required this.onConfirmAssemblyReceipt,
    required this.onDeleteTrack,
    required this.onReturnRequest,
    required this.onRequestReturnInline,
    required this.onWarehouseDelivery,
    required this.onLoadReturn,
    required this.onUpdateReturnCode,
    required this.onConfirmCompletedReturn,
    required this.returnRequestedTracks,
    this.tutorialActionsKey,
    this.tutorialAssemblyKey,
  });

  @override
  State<_TrackGroupCard> createState() => _TrackGroupCardState();
}

class _TrackGroupCardState extends State<_TrackGroupCard> {
  bool _showBoxes = false;
  bool _showTracks = false;
  bool _showAssemblyDetails = false;

  void _disposeControllersAfterSheetClose(
    Iterable<TextEditingController> controllers,
  ) {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 500)).then((_) {
        for (final controller in controllers) {
          controller.dispose();
        }
      }),
    );
  }

  List<StatusTimelineStatus> _timelineStatuses(List<TrackStatus> statuses) {
    return statuses
        .map(
          (status) => StatusTimelineStatus(
            code: status.code,
            name: status.nameRu.isNotEmpty ? status.nameRu : status.code,
            color: parseHexColor(status.color),
            sortOrder: status.sortOrder,
          ),
        )
        .toList(growable: false);
  }

  void _showTrackStatusTimeline(BuildContext context, TrackItem track) {
    showStatusTimelineSheet(
      context: context,
      title: 'Статус трека',
      currentStatusCode: track.statusCode,
      currentStatusName: track.status,
      currentStatusColor: parseHexColor(track.statusColor),
      history: track.statusHistory,
      statuses: _timelineStatuses(widget.trackStatuses),
    );
  }

  void _showAssemblyStatusTimeline(
    BuildContext context,
    TrackAssembly assembly,
  ) {
    showStatusTimelineSheet(
      context: context,
      title: 'Статус сборки',
      currentStatusCode: assembly.status,
      currentStatusName: assembly.statusName?.isNotEmpty == true
          ? assembly.statusName!
          : assembly.status,
      currentStatusColor: parseHexColor(assembly.statusColor),
      history: assembly.statusHistory,
      statuses: _timelineStatuses(widget.assemblyStatuses),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy', 'ru');
    // Используем комментарий из локального кэша или из данных сборки
    final groupComment = widget.assembly != null
        ? (widget.groupComments[widget.assembly!.id.toString()] ??
              widget.assembly!.comment ??
              '')
        : '';
    final groupQuestion = widget.assembly != null
        ? (widget.groupQuestions[widget.assembly!.id.toString()] ?? '')
        : '';
    final groupQuestionCreated = widget.assembly != null
        ? widget.groupQuestionCreatedAt[widget.assembly!.id.toString()]
        : null;
    final groupQuestionUpdated = widget.assembly != null
        ? widget.groupQuestionUpdatedAt[widget.assembly!.id.toString()]
        : null;
    if (widget.assembly == null && widget.tracks.length == 1) {
      final card = _buildTrackCard(context, df, widget.tracks.first);
      if (widget.tutorialActionsKey == null) return card;
      return TrainingTarget(
        id: 'tracks.card',
        child: KeyedSubtree(key: widget.tutorialActionsKey, child: card),
      );
    }
    if (widget.assembly != null) {
      final card = _buildAssemblyCard(context);
      if (widget.tutorialAssemblyKey == null) return card;
      return TrainingTarget(
        id: 'assembly.card',
        child: KeyedSubtree(key: widget.tutorialAssemblyKey, child: card),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _tracksPremiumCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.assembly != null) ...[
            Padding(
              key: widget.tutorialAssemblyKey,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Сборка ${widget.assembly!.number}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showAssemblyStatusTimeline(
                          context,
                          widget.assembly!,
                        ),
                        child: StatusPill(
                          text:
                              widget.assembly!.statusName ??
                              widget.assembly!.status,
                          color: parseHexColor(widget.assembly!.statusColor),
                          truncate: false,
                          textStyle: const TextStyle(
                            fontFamily: 'Gilroy',
                            fontSize: 14,
                            height: 16 / 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (widget.assembly!.name != null &&
                      widget.assembly!.name!.isNotEmpty)
                    Text(
                      widget.assembly!.name!,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  // Отображение тарифа, упаковки, страховки и доставки
                  if (widget.assembly!.tariffName != null ||
                      widget.assembly!.packagingTypes.isNotEmpty ||
                      widget.assembly!.hasFragileGoods ||
                      widget.assembly!.placePreference != 'unspecified' ||
                      widget.assembly!.hasInsurance ||
                      widget.assembly!.deliveryMethod != null) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showAssemblyDetails = !_showAssemblyDetails;
                        });
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.settings_outlined,
                                size: 16,
                                color: Colors.black54,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Детали сборки',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                _showAssemblyDetails
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 20,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            alignment: Alignment.topCenter,
                            child: _showAssemblyDetails
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 8),
                                      if (widget.assembly!.tariffName !=
                                          null) ...[
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.local_shipping_outlined,
                                              size: 16,
                                              color: Colors.black54,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'Тариф: ',
                                              style: TextStyle(
                                                color: Colors.black54,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Flexible(
                                              child: Text(
                                                widget.assembly!.tariffName!,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (widget
                                          .assembly!
                                          .packagingTypes
                                          .isNotEmpty) ...[
                                        if (widget.assembly!.tariffName != null)
                                          const SizedBox(height: 8),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.inventory_2_outlined,
                                              size: 16,
                                              color: Colors.black54,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'Упаковка: ',
                                              style: TextStyle(
                                                color: Colors.black54,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text.rich(
                                                TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: widget
                                                          .assembly!
                                                          .packagingTypes
                                                          .join(', '),
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (widget.assembly!.hasFragileGoods ||
                                          widget.assembly!.placePreference !=
                                              'unspecified') ...[
                                        if (widget.assembly!.tariffName !=
                                                null ||
                                            widget
                                                .assembly!
                                                .packagingTypes
                                                .isNotEmpty)
                                          const SizedBox(height: 8),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              Icons.inventory_2_outlined,
                                              size: 16,
                                              color: context.brandPrimary,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                [
                                                  if (widget
                                                      .assembly!
                                                      .hasFragileGoods)
                                                    'Хрупкий груз',
                                                  if (widget
                                                          .assembly!
                                                          .placePreference ==
                                                      'single_if_possible')
                                                    'По возможности 1 место',
                                                  if (widget
                                                          .assembly!
                                                          .placePreference ==
                                                      'split_allowed')
                                                    'Можно разделить',
                                                ].join(' • '),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (widget.assembly!.hasInsurance) ...[
                                        if (widget.assembly!.tariffName !=
                                                null ||
                                            widget
                                                .assembly!
                                                .packagingTypes
                                                .isNotEmpty ||
                                            widget.assembly!.hasFragileGoods ||
                                            widget.assembly!.placePreference !=
                                                'unspecified')
                                          const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.verified_user_outlined,
                                              size: 16,
                                              color: Colors.blue,
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'Страховка: ',
                                              style: TextStyle(
                                                color: Colors.black54,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Text(
                                              widget
                                                          .assembly!
                                                          .insuranceAmount !=
                                                      null
                                                  ? 'от ${_formatDecimal(widget.assembly!.insuranceAmount!)} ¥'
                                                  : 'Да',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                color: Colors.blue,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      // Доставка
                                      if (widget.assembly!.deliveryMethod !=
                                          null) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              widget.assembly!.deliveryMethod ==
                                                      'self_pickup'
                                                  ? Icons.store_outlined
                                                  : Icons
                                                        .local_shipping_outlined,
                                              size: 16,
                                              color: Colors.orange,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    widget
                                                                .assembly!
                                                                .deliveryMethod ==
                                                            'self_pickup'
                                                        ? 'Самовывоз'
                                                        : widget
                                                                      .assembly!
                                                                      .transportCompanyName !=
                                                                  null &&
                                                              widget
                                                                  .assembly!
                                                                  .transportCompanyName!
                                                                  .isNotEmpty
                                                        ? 'ТК: ${widget.assembly!.transportCompanyName}'
                                                        : 'Транспортная компания',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13,
                                                      color: Colors.orange,
                                                    ),
                                                  ),
                                                  if (widget
                                                              .assembly!
                                                              .deliveryMethod ==
                                                          'transport_company' &&
                                                      widget
                                                              .assembly!
                                                              .recipientName !=
                                                          null) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${widget.assembly!.recipientName}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                    if (widget
                                                            .assembly!
                                                            .recipientPhone !=
                                                        null)
                                                      Text(
                                                        widget
                                                            .assembly!
                                                            .recipientPhone!,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.black54,
                                                        ),
                                                      ),
                                                    if (widget
                                                            .assembly!
                                                            .recipientCity !=
                                                        null)
                                                      Text(
                                                        widget
                                                            .assembly!
                                                            .recipientCity!,
                                                        style: const TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.black54,
                                                        ),
                                                      ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (groupComment.trim().isNotEmpty ||
                      groupQuestion.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0x0F000000),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (groupComment.trim().isNotEmpty) ...[
                            const Text(
                              'Заметка',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              groupComment,
                              style: const TextStyle(color: Colors.black54),
                            ),
                            if (groupQuestion.trim().isNotEmpty)
                              const SizedBox(height: 10),
                          ],
                          if (groupQuestion.trim().isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.96),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.22),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x0A000000),
                                    offset: Offset(0, 3),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const _QuestionBadge(
                                        color: Colors.orange,
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Вопрос по сборке',
                                              style: TextStyle(
                                                fontFamily: 'Gilroy',
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                                color: Color(0xFF2F2F2F),
                                              ),
                                            ),
                                            if (groupQuestionCreated !=
                                                null) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                'Создан: ${df.format(groupQuestionCreated)}',
                                                style: const TextStyle(
                                                  fontFamily: 'Gilroy',
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.black45,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const _TaskStatusBadge(
                                        text: 'Новый',
                                        color: Colors.orange,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  _QuestionTextPanel(
                                    title: 'Вопрос',
                                    text: groupQuestion,
                                  ),
                                  if (groupQuestionUpdated != null) ...[
                                    const SizedBox(height: 8),
                                    _QuestionMetaPill(
                                      icon: CupertinoIcons.clock,
                                      text:
                                          'Обновлён: ${df.format(groupQuestionUpdated)}',
                                      color: Colors.black54,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  // Коробки
                  if (widget.assembly!.boxes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _showBoxes = !_showBoxes;
                        });
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 16,
                                  color: Colors.black54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  tr(
                                    context,
                                    ru: 'Коробки (${widget.assembly!.boxes.length})',
                                    zh: '箱子 (${widget.assembly!.boxes.length})',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  _showBoxes
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 20,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                          ),
                          // Отображаем каждую коробку
                          if (_showBoxes)
                            ...widget.assembly!.boxes.map(
                              (box) => _buildBoxCard(context, box),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ActionChipButton(
                        label: 'Добавить заметку',
                        onPressed: () =>
                            widget.onEditGroupComment(widget.assembly!),
                      ),
                      if (widget.assembly!.canEditDelivery)
                        _ActionChipButton(
                          icon: Icons.local_shipping_outlined,
                          label: 'Доставка',
                          onPressed: () =>
                              widget.onSelectDelivery(widget.assembly!),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Заголовок «Треки (N)» — сворачиваемый
            GestureDetector(
              onTap: () => setState(() => _showTracks = !_showTracks),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_shipping_outlined,
                      size: 16,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      // Используем реальное количество треков в сборке с бэка
                      // (не зависит от пагинации и загруженной страницы).
                      'Треки (${widget.assembly?.trackCount ?? widget.tracks.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _showTracks ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: Colors.black54,
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_showTracks || widget.assembly == null)
            ...widget.tracks.asMap().entries.map((entry) {
              final index = entry.key;
              final track = entry.value;
              final canSelect =
                  track.status == 'На складе' &&
                  _canSelectTrackForAssembly(
                    track,
                    widget.returnRequestedTracks,
                  );
              final allowedByStatus =
                  widget.selectedStatus == null ||
                  widget.selectedStatus == track.status;
              final isSelected = widget.selectedTrackCodes.contains(track.code);

              final canAskQuestion =
                  track.status == 'В ожидании' || track.status == 'На складе';
              final canRequestReturn =
                  track.status == 'На складе' &&
                  track.statusCode == 'in_warehouse' &&
                  !widget.returnRequestedTracks.contains(track.code);
              final availableFillInfo =
                  track.status == 'В ожидании' ||
                  track.status == 'На складе' ||
                  track.status == 'На сборке' ||
                  track.status == 'Отправлен';
              final activePhoto = track.activePhotoRequest;
              final visibleQuestions = track.questions
                  .where((q) => q.status != 'cancelled')
                  .toList();
              final hasActiveTransferRequest = visibleQuestions.any(
                (q) =>
                    q.questionType == _clientCodeTransferQuestionType &&
                    q.isActive,
              );
              final canTransferClientCode =
                  widget.assembly == null &&
                  track.assembly == null &&
                  !hasActiveTransferRequest &&
                  (track.statusCode == 'pending' ||
                      track.statusCode == 'in_warehouse');
              final isPhotoRequested =
                  activePhoto != null ||
                  widget.requestedPhotoReports.contains(track.code);
              // Запросить можно только если трек в статусе «В ожидании» и ещё не запрошен
              final canRequestPhoto = track.isPending && !isPhotoRequested;
              final commentText =
                  widget.overrideComments[track.code] ?? track.comment;
              final pendingLocalQuestion =
                  (widget.askedQuestions[track.code] ?? '').trim();
              final hasQuestion =
                  visibleQuestions.isNotEmpty ||
                  pendingLocalQuestion.isNotEmpty;
              // Используем productInfo из API или локальной карты
              final apiProductInfo = track.productInfo;
              final localProductInfo = widget.productInfos[track.code];
              // Объединяем данные: приоритет у API, затем локальные данные
              final productInfoName =
                  apiProductInfo?.name ?? localProductInfo?.name ?? '';
              final productInfoQuantity =
                  apiProductInfo?.quantity ?? localProductInfo?.quantity;
              // Локальные изображения (после загрузки, до обновления страницы)
              // После обновления страницы — используем imageUrl из API как fallback
              final productInfoImages =
                  (localProductInfo?.images.isNotEmpty == true)
                  ? localProductInfo!.images
                  : (apiProductInfo?.imageUrl?.isNotEmpty == true
                        ? [apiProductInfo!.imageUrl!]
                        : <String>[]);
              final hasProductInfo =
                  productInfoName.isNotEmpty ||
                  productInfoQuantity != null ||
                  productInfoImages.isNotEmpty;

              final List<Widget> infoSections = [];
              final commentValue = (commentText ?? '').trim();
              if (commentValue.isNotEmpty) {
                infoSections.add(
                  _CollapsibleNote(
                    text: commentValue,
                    onEdit: () => widget.onEditComment(track),
                  ),
                );
              }

              if (hasQuestion) {
                // Показываем все видимые вопросы (из API)
                for (var i = 0; i < visibleQuestions.length; i++) {
                  final q = visibleQuestions[i];
                  final statusColor = q.hasResponse
                      ? Colors.green
                      : q.status == 'cancelled'
                      ? Colors.red
                      : Colors.orange;
                  infoSections.add(
                    _CollapsibleQuestion(
                      title: visibleQuestions.length > 1
                          ? 'Вопрос ${i + 1}'
                          : 'Вопрос',
                      statusLabel: q.statusLabel,
                      statusColor: statusColor,
                      question: q.question,
                      answer: q.hasAnswer ? q.answer : null,
                      answerPhotoUrls: q.answerPhotoUrls,
                      trackCode: track.code,
                      createdAt: df.format(q.createdAt),
                      answeredAt: q.answeredAt != null
                          ? df.format(q.answeredAt!)
                          : null,
                      canCancel: q.isActive,
                      onCancel: () => widget.onCancelQuestion(track),
                    ),
                  );
                }
                // Показываем локально добавленный вопрос (ещё не сохранён в API)
                if (pendingLocalQuestion.isNotEmpty &&
                    visibleQuestions.isEmpty) {
                  infoSections.add(
                    _CollapsibleQuestion(
                      title: 'Вопрос',
                      statusLabel: widget.questionStatus[track.code] ?? 'Новый',
                      statusColor: Colors.orange,
                      question: pendingLocalQuestion,
                      answer: null,
                      answerPhotoUrls: const [],
                      trackCode: track.code,
                      createdAt: df.format(DateTime.now()),
                      answeredAt: null,
                      canCancel: true,
                      onCancel: () => widget.onCancelQuestion(track),
                    ),
                  );
                }
              }

              return Column(
                children: [
                  if (index > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: Color(0x11000000),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (canSelect && allowedByStatus) ...[
                              Transform.translate(
                                offset: const Offset(-5, 0),
                                child: Checkbox(
                                  value: isSelected,
                                  onChanged: (_) => widget.onToggle(track),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              const SizedBox(width: 2),
                            ],
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _copyTrackCode(
                                  context,
                                  track.code,
                                  compactToast: true,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    track.code,
                                    style: const TextStyle(
                                      fontFamily: 'Gilroy',
                                      fontSize: 16,
                                      height: 24 / 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ),
                            if (track.status != 'На сборке')
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () =>
                                    _showTrackStatusTimeline(context, track),
                                child: StatusPill(
                                  text: track.status,
                                  color: parseHexColor(track.statusColor),
                                  truncate: false,
                                  textStyle: const TextStyle(
                                    fontFamily: 'Gilroy',
                                    fontSize: 14,
                                    height: 16 / 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          df.format(track.date),
                          style: const TextStyle(color: Colors.black54),
                        ),
                        if (hasProductInfo) ...[
                          const SizedBox(height: 8),
                          _ProductInfoInline(
                            name: productInfoName,
                            quantity: productInfoQuantity,
                            imageUrls: productInfoImages,
                            trackCode: track.code,
                            onEdit: () => widget.onEditProduct(track),
                          ),
                        ],
                        if (track.spItems.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _TrackSpItemsBlock(items: track.spItems),
                        ],
                        if (infoSections.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _TrackInfoSectionsSurface(children: infoSections),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          key: index == 0 ? widget.tutorialActionsKey : null,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (canRequestPhoto)
                              _ActionChipButton(
                                label: 'Фотоотчёт',
                                icon: Icons.photo_camera_outlined,
                                onPressed: () => widget.onPhotoRequest(track),
                              ),
                            if (canAskQuestion && !hasQuestion)
                              _ActionChipButton(
                                label: 'Вопрос',
                                icon: Icons.help_outline_rounded,
                                onPressed: () => widget.onAskQuestion(track),
                              ),
                            if (canTransferClientCode)
                              _ActionChipButton(
                                label: 'Перенести',
                                icon: Icons.swap_horiz_rounded,
                                onPressed: () =>
                                    widget.onTransferClientCode(track),
                              ),
                            if (commentValue.isEmpty)
                              _ActionChipButton(
                                label: 'Заметка',
                                icon: Icons.edit_note_rounded,
                                onPressed: () => widget.onEditComment(track),
                              ),
                            if (availableFillInfo && !hasProductInfo)
                              _ActionChipButton(
                                label: 'О товаре',
                                icon: Icons.inventory_2_outlined,
                                onPressed: () => widget.onEditProduct(track),
                              ),
                            if (canRequestReturn)
                              _ActionChipButton(
                                label: 'Возврат',
                                icon: Icons.assignment_return_outlined,
                                onPressed: () => widget.onReturnRequest(track),
                              ),
                            if (track.isPending)
                              _ActionChipButton(
                                label: 'Удалить',
                                icon: Icons.delete_outline_rounded,
                                isDestructive: true,
                                onPressed: () => widget.onDeleteTrack(track),
                              ),
                          ],
                        ),
                        if (widget.assembly == null &&
                            canShowTrackWarehouseDelivery(track)) ...[
                          const SizedBox(height: 10),
                          TrackWarehouseDeliveryButton(
                            onPressed: () => widget.onWarehouseDelivery(track),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTrackCard(
    BuildContext context,
    DateFormat df,
    TrackItem track, {
    bool embeddedInAssembly = false,
  }) {
    final canSelect =
        track.status == 'На складе' &&
        _canSelectTrackForAssembly(track, widget.returnRequestedTracks);
    final allowedByStatus =
        widget.selectedStatus == null || widget.selectedStatus == track.status;
    final canShowCheckbox =
        widget.allowSelection &&
        !embeddedInAssembly &&
        canSelect &&
        allowedByStatus;
    final isSelected = widget.selectedTrackCodes.contains(track.code);

    final canRequestReturn =
        track.status == 'На складе' &&
        track.statusCode == 'in_warehouse' &&
        !widget.returnRequestedTracks.contains(track.code);

    final activePhoto = track.activePhotoRequest;
    final visibleQuestions = track.questions
        .where((q) => q.status != 'cancelled')
        .toList();
    final hasActiveTransferRequest = visibleQuestions.any(
      (q) => q.questionType == _clientCodeTransferQuestionType && q.isActive,
    );
    final canTransferClientCode =
        !embeddedInAssembly &&
        track.assembly == null &&
        !hasActiveTransferRequest &&
        (track.statusCode == 'pending' || track.statusCode == 'in_warehouse');
    final commentText = widget.overrideComments[track.code] ?? track.comment;
    final commentValue = (commentText ?? '').trim();
    final pendingLocalQuestion = (widget.askedQuestions[track.code] ?? '')
        .trim();

    final photoStatusLabel = activePhoto?.statusLabel ?? 'Новый';
    final photoMediaUrls = _collectPhotoMediaUrls(track, activePhoto);

    final apiProductInfo = track.productInfo;
    final localProductInfo = widget.productInfos[track.code];
    final productInfoName =
        apiProductInfo?.name ?? localProductInfo?.name ?? '';
    final productInfoQuantity =
        apiProductInfo?.quantity ?? localProductInfo?.quantity;
    final productInfoImages = (localProductInfo?.images.isNotEmpty == true)
        ? localProductInfo!.images
        : (apiProductInfo?.imageUrl?.isNotEmpty == true
              ? [apiProductInfo!.imageUrl!]
              : <String>[]);
    final hasProductInfo =
        productInfoName.isNotEmpty ||
        productInfoQuantity != null ||
        productInfoImages.isNotEmpty;

    final activeQuestion = track.activeQuestion;
    final questionDone =
        activeQuestion?.hasResponse == true ||
        activeQuestion?.status == 'completed';
    final questionPending = activeQuestion != null && !questionDone;
    final photoDone =
        photoMediaUrls.isNotEmpty || activePhoto?.status == 'completed';
    final photoPending = activePhoto != null && !photoDone;
    final returnRequested =
        widget.returnRequestedTracks.contains(track.code) ||
        track.statusCode == 'return_requested';
    final statusColor =
        parseHexColor(track.statusColor) ?? context.brandPrimary;
    final indicatorMuted = AppColors.textSecondary;
    final successColor = const Color(0xFF168A5B);
    final warningColor = const Color(0xFFD97706);
    String? target(String id) =>
        !embeddedInAssembly && widget.trainingTargets.contains(id) ? id : null;
    final indicators = <ClientTrackIndicator>[
      ClientTrackIndicator(
        icon: hasProductInfo
            ? Icons.inventory_2_rounded
            : Icons.inventory_2_outlined,
        trainingTargetId: target('track.product'),
        title: 'Товар',
        value: hasProductInfo ? 'Заполнено' : 'Не заполнено',
        label: hasProductInfo ? 'Товар заполнен' : 'Товар не заполнен',
        color: hasProductInfo ? successColor : warningColor,
        tabIndex: 0,
      ),
      ClientTrackIndicator(
        icon: photoDone
            ? Icons.photo_library_rounded
            : Icons.photo_library_outlined,
        trainingTargetId: target('track.photos'),
        title: 'Фото',
        value: photoDone
            ? 'Готово'
            : photoPending
            ? photoStatusLabel
            : 'Нет',
        label: photoDone
            ? 'Фотоотчёт готов'
            : photoPending
            ? photoStatusLabel
            : 'Фотоотчёта нет',
        color: photoDone
            ? successColor
            : photoPending
            ? warningColor
            : indicatorMuted,
        tabIndex: 2,
      ),
      ClientTrackIndicator(
        trainingTargetId: target('track.question'),
        icon: questionDone
            ? Icons.mark_chat_read_rounded
            : Icons.help_outline_rounded,
        title: 'Вопросы',
        value: visibleQuestions.isEmpty && pendingLocalQuestion.isEmpty
            ? 'Нет'
            : questionDone
            ? 'Есть ответ'
            : 'Ждёт ответа',
        label: visibleQuestions.isEmpty && pendingLocalQuestion.isEmpty
            ? 'Вопросов нет'
            : questionDone
            ? '${visibleQuestions.length} · есть ответ'
            : '${visibleQuestions.length + (pendingLocalQuestion.isEmpty ? 0 : 1)} · ждёт ответа',
        color: questionDone
            ? successColor
            : questionPending || pendingLocalQuestion.isNotEmpty
            ? warningColor
            : indicatorMuted,
        tabIndex: 3,
      ),
      if (returnRequested)
        ClientTrackIndicator(
          icon: Icons.assignment_return_rounded,
          title: 'Возврат',
          value: 'Оформлен',
          label: 'Возврат оформлен',
          color: warningColor,
          tabIndex: 4,
        ),
    ];

    final quickActions = <ClientTrackQuickAction>[
      if (canTransferClientCode)
        ClientTrackQuickAction(
          icon: Icons.swap_horiz_rounded,
          trainingTargetId: target('track.transfer'),
          label: 'Перенести',
          onTap: () => widget.onTransferClientCode(track),
        ),
      ClientTrackQuickAction(
        icon: commentValue.isEmpty
            ? Icons.edit_note_rounded
            : Icons.sticky_note_2_outlined,
        label: 'Заметка',
        onTap: () => widget.onEditComment(track),
      ),
      if (!embeddedInAssembly && canRequestReturn)
        ClientTrackQuickAction(
          icon: Icons.assignment_return_outlined,
          trainingTargetId: target('track.return'),
          label: 'Возврат',
          onTap: () => widget.onReturnRequest(track),
        ),
    ];

    return ClientTrackCompactCard(
      trainingOpenId: target('track.open'),
      trainingStatusId: target('track.status'),
      trainingSelectionId: target('tracks.selection'),
      trackNumber: track.code,
      status: track.status,
      statusColor: statusColor,
      productName: productInfoName,
      selectable: canShowCheckbox,
      selected: isSelected,
      onToggleSelection: canShowCheckbox ? () => widget.onToggle(track) : null,
      onCopyTrack: () => _copyTrackCode(context, track.code),
      onOpenDetails: (tab) => _showTrackDetailSheet(
        context,
        track: track,
        embeddedInAssembly: embeddedInAssembly,
        initialTab: tab,
      ),
      indicators: indicators,
      actions: quickActions,
    );
  }

  Widget _buildAssemblyCard(BuildContext context) {
    final assembly = widget.assembly!;
    final statusColor = parseHexColor(assembly.statusColor);
    return _AssemblyCompactCard(
      trainingTargets: widget.trainingTargets,
      number: assembly.number,
      name: assembly.name,
      status: assembly.statusName?.isNotEmpty == true
          ? assembly.statusName!
          : assembly.status,
      statusColor: statusColor,
      trackCount: assembly.trackCount ?? widget.tracks.length,
      boxCount: assembly.boxes.length,
      hasDelivery: assembly.deliveryMethod != null,
      canEditDelivery: assembly.canEditDelivery,
      onOpen: (tab) =>
          _showAssemblyDetailSheet(context, assembly, initialTab: tab),
      onComment: () => widget.onEditGroupComment(assembly),
      onDelivery: () => widget.onSelectDelivery(assembly),
    );
  }

  Future<void> _showAssemblyDetailSheet(
    BuildContext context,
    TrackAssembly assembly, {
    int initialTab = 0,
  }) async {
    var selectedTab = initialTab.clamp(0, 4);
    final createdAt = _assemblyCreatedAt();
    final updatedAt = _assemblyUpdatedAt();
    final dateFormat = DateFormat('dd.MM.yyyy', 'ru');
    final comment =
        (widget.groupComments[assembly.id.toString()] ?? assembly.comment ?? '')
            .trim();
    var isConfirmingReceipt = false;

    await showBlurredModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          // This root modal can outlive the card that opened it.
          final context = sheetContext;
          Widget carrierTracking() => ClientCarrierTrackingPanel(
            target: (assemblyId: assembly.id, invoiceId: null),
            boxes: assembly.boxes,
            sectionBuilder: (context, child) => _TrackFilterSectionCard(
              icon: Icons.local_shipping_outlined,
              title: tr(context, ru: 'Движение груза', zh: '货物运输动态'),
              child: child,
            ),
          );
          Widget mainTab() => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TrainingTarget(
                id: 'assembly.status.details',
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    onTap: () => _showAssemblyStatusTimeline(context, assembly),
                    borderRadius: BorderRadius.circular(18),
                    child: _TrackSheetMetaCard(
                      icon: Icons.inventory_2_rounded,
                      title: 'Текущий статус',
                      value: assembly.statusName?.isNotEmpty == true
                          ? assembly.statusName!
                          : assembly.status,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              carrierTracking(),
              Row(
                children: [
                  Expanded(
                    child: _TrackSheetMetaCard(
                      icon: Icons.add_circle_outline_rounded,
                      title: 'Добавлена',
                      value: createdAt == null
                          ? '—'
                          : dateFormat.format(createdAt),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TrackSheetMetaCard(
                      icon: Icons.update_rounded,
                      title: 'Обновлена',
                      value: updatedAt == null
                          ? '—'
                          : dateFormat.format(updatedAt),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _TrackSheetMetaCard(
                icon: Icons.label_outline_rounded,
                title: 'Название сборки',
                value: assembly.name?.trim().isNotEmpty == true
                    ? assembly.name!.trim()
                    : '—',
              ),
              const SizedBox(height: 12),
              _TrackFilterSectionCard(
                icon: Icons.sticky_note_2_outlined,
                title: 'Комментарий пользователя',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TaskDetailBlock(
                      title: 'Заметка',
                      text: comment.isEmpty
                          ? 'Комментарий не добавлен'
                          : comment,
                      muted: comment.isEmpty,
                    ),
                    const SizedBox(height: 10),
                    _TrackSheetSecondaryButton(
                      label: comment.isEmpty
                          ? 'Добавить комментарий'
                          : 'Изменить комментарий',
                      onTap: () => widget.onEditGroupComment(assembly),
                    ),
                  ],
                ),
              ),
              if (assembly.tariffName != null ||
                  assembly.packagingTypes.isNotEmpty ||
                  assembly.hasFragileGoods ||
                  assembly.placePreference != 'unspecified') ...[
                const SizedBox(height: 12),
                _TrackFilterSectionCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'Упаковка и тариф',
                  child: _buildAssemblyPackingBlock(context, assembly),
                ),
              ],
            ],
          );

          Widget videoTab() => AssemblyScanSessionsSection(
            assemblyId: assembly.id,
            assemblyNumber: assembly.number,
          );

          Widget deliveryTab() => _AssemblyDeliveryEditor(
            assembly: assembly,
            onSave:
                ({
                  required deliveryMethod,
                  recipientName,
                  recipientPhone,
                  recipientCity,
                  transportCompanyName,
                }) => widget.onSaveDelivery(
                  assembly,
                  deliveryMethod: deliveryMethod,
                  recipientName: recipientName,
                  recipientPhone: recipientPhone,
                  recipientCity: recipientCity,
                  transportCompanyName: transportCompanyName,
                ),
          );

          Widget boxesTab() => assembly.boxes.isEmpty
              ? const _TrackDetailEmptyState(
                  icon: Icons.inventory_2_outlined,
                  text: 'Места сборки ещё не добавлены',
                )
              : Column(
                  children: [
                    carrierTracking(),
                    for (var i = 0; i < assembly.boxes.length; i++) ...[
                      if (i > 0) const SizedBox(height: 14),
                      _buildAssemblyBoxRow(
                        context,
                        assembly,
                        assembly.boxes[i],
                        i,
                      ),
                    ],
                  ],
                );

          Widget tracksTab() => widget.tracks.isEmpty
              ? const _TrackDetailEmptyState(
                  icon: Icons.local_shipping_outlined,
                  text: 'В сборке пока нет трек-номеров',
                )
              : _AssemblyTracksGrid(
                  tracks: widget.tracks,
                  itemBuilder: (track) => _buildTrackCard(
                    context,
                    DateFormat('dd MMM yyyy', 'ru'),
                    track,
                    embeddedInAssembly: true,
                  ),
                );

          final child = switch (selectedTab) {
            1 => videoTab(),
            2 => deliveryTab(),
            3 => boxesTab(),
            4 => tracksTab(),
            _ => mainTab(),
          };

          return _TrackSheetSurface(
            icon: Icons.inventory_2_rounded,
            title: assembly.number,
            subtitle: 'Карточка сборки',
            useMaxHeight: true,
            pinnedChild: _AssemblyDetailTabs(
              selectedIndex: selectedTab,
              onSelected: (value) => setSheetState(() => selectedTab = value),
            ),
            footer: selectedTab == 0 && assembly.canConfirmReceipt
                ? _TrackSheetPrimaryButton(
                    label: isConfirmingReceipt
                        ? tr(context, ru: 'Подтверждаем…', zh: '确认中…')
                        : tr(context, ru: 'Подтвердить получение', zh: '确认收货'),
                    icon: Icons.inventory_2_outlined,
                    onTap: isConfirmingReceipt
                        ? null
                        : () async {
                            setSheetState(() => isConfirmingReceipt = true);
                            final success = await widget
                                .onConfirmAssemblyReceipt(assembly);
                            if (!sheetContext.mounted) return;
                            if (success) {
                              Navigator.of(sheetContext).pop();
                              return;
                            }
                            setSheetState(() => isConfirmingReceipt = false);
                          },
                  )
                : null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(key: ValueKey(selectedTab), child: child),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAssemblyPackingBlock(
    BuildContext context,
    TrackAssembly assembly,
  ) {
    final placePreference = switch (assembly.placePreference) {
      'single_if_possible' => 'По возможности 1 место',
      'split_allowed' => 'Можно разделить',
      _ => 'Не важно',
    };
    final lines = [
      if (assembly.tariffName != null) 'Тариф: ${assembly.tariffName}',
      if (assembly.packagingTypes.isNotEmpty)
        'Упаковка: ${assembly.packagingTypes.join(', ')}',
      if (assembly.hasFragileGoods) 'Хрупкий груз: Да',
      if (assembly.placePreference != 'unspecified') 'Места: $placePreference',
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: 5),
          _AssemblyPlainText(lines[i]),
        ],
      ],
    );
  }

  Widget _buildAssemblyBoxRow(
    BuildContext context,
    TrackAssembly assembly,
    Box box,
    int index,
  ) {
    final photos = box.photos.map((photo) => photo.url).where((url) {
      return url.trim().isNotEmpty;
    }).toList();
    return _TrackFilterSectionCard(
      icon: Icons.inventory_2_outlined,
      title: 'Место ${index + 1}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: photos.isEmpty
                ? null
                : () => _openAssemblyMediaViewer(context, photos),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F1F4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.045),
                  ),
                ),
                child: photos.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.image_not_supported_outlined,
                              color: AppColors.textSecondary,
                              size: 28,
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Фото места не добавлено',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontFamily: 'Gilroy',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          AppCachedMediaImage(
                            url: photos.first,
                            thumbnailSize: 720,
                            memCacheWidth: 720,
                            maxWidthDiskCache: 1080,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            useOldImageOnUrlChange: false,
                            filterQuality: FilterQuality.medium,
                            imageBuilder: (_, imageProvider) => DecoratedBox(
                              decoration: BoxDecoration(
                                image: DecorationImage(
                                  image: imageProvider,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            placeholder: (_, _) => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            errorWidget: (_, _, _) => const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 28,
                              ),
                            ),
                          ),
                          if (photos.length > 1)
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.62),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '+${photos.length - 1} фото',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Gilroy',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 8.0;
              final width = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _AssemblyBoxFact(
                    width: width,
                    label: 'Номер',
                    value: (box.orderNumber ?? assembly.number).trim(),
                    icon: Icons.tag_rounded,
                  ),
                  _AssemblyBoxFact(
                    width: width,
                    label: 'Габариты',
                    value: _boxDimensionsForDesign(box),
                    icon: Icons.straighten_rounded,
                  ),
                  _AssemblyBoxFact(
                    width: width,
                    label: 'Вес',
                    value: '${_formatDecimal(box.weight)} кг',
                    icon: Icons.scale_outlined,
                  ),
                  _AssemblyBoxFact(
                    width: width,
                    label: 'Объём',
                    value: '${box.volume.toStringAsFixed(4)} м³',
                    icon: Icons.view_in_ar_outlined,
                  ),
                  _AssemblyBoxFact(
                    width: width,
                    label: 'Плотность',
                    value: '${box.density.toStringAsFixed(0)} кг/м³',
                    icon: Icons.compress_rounded,
                  ),
                  _AssemblyBoxFact(
                    width: width,
                    label: 'Тариф',
                    value: box.tariffName ?? assembly.tariffName ?? '—',
                    icon: Icons.payments_outlined,
                  ),
                  _AssemblyBoxFact(
                    width: constraints.maxWidth,
                    label: 'Упаковка',
                    value: _boxPackagingForDesign(box, assembly),
                    icon: Icons.inventory_outlined,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _boxDimensionsForDesign(Box box) {
    return '${box.height.toStringAsFixed(0)}x${box.width.toStringAsFixed(0)}x${box.length.toStringAsFixed(0)} см';
  }

  String _boxPackagingForDesign(Box box, TrackAssembly assembly) {
    if (box.packagingUsages.isNotEmpty) {
      return box.packagingUsages.map((usage) => usage.displayValue).join(', ');
    }
    final values = box.packagingTypes.isNotEmpty
        ? box.packagingTypes
        : assembly.packagingTypes;
    return values.isEmpty ? '—' : values.join(', ');
  }

  DateTime? _assemblyCreatedAt() {
    DateTime? result;
    for (final track in widget.tracks) {
      final value = track.createdAt;
      if (result == null || value.isBefore(result)) result = value;
    }
    return result;
  }

  DateTime? _assemblyUpdatedAt() {
    DateTime? result;
    for (final track in widget.tracks) {
      final value = track.updatedAt;
      if (result == null || value.isAfter(result)) result = value;
    }
    return result;
  }

  void _openAssemblyMediaViewer(
    BuildContext context,
    List<String> mediaUrls, {
    int initialIndex = 0,
  }) {
    if (mediaUrls.isEmpty) return;
    final safeInitialIndex = initialIndex
        .clamp(0, mediaUrls.length - 1)
        .toInt();
    final photos = mediaUrls
        .map((url) => PhotoItem(url: url, date: DateTime.now()))
        .toList();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoViewerScreen(
          item: photos[safeInitialIndex],
          allPhotos: photos,
          initialIndex: safeInitialIndex,
        ),
      ),
    );
  }

  Future<void> _showTrackDetailSheet(
    BuildContext context, {
    required TrackItem track,
    required bool embeddedInAssembly,
    int initialTab = 0,
  }) async {
    final dateFormat = DateFormat('dd.MM.yyyy', 'ru');
    final showWarehouseDeliveryTab = canShowTrackWarehouseDelivery(track);
    var selectedTab = initialTab.clamp(0, 4);
    if (!showWarehouseDeliveryTab && selectedTab == 1) selectedTab = 0;
    Future<TrackReturnInfo?>? returnFuture = track.id == null
        ? null
        : widget.onLoadReturn(track.id!);

    final activePhoto = track.activePhotoRequest;
    final photoMediaUrls = _collectPhotoMediaUrls(track, activePhoto);
    final photoCreated =
        activePhoto?.createdAt ?? widget.photoRequestCreatedAt[track.code];
    final photoUpdated =
        activePhoto?.completedAt ?? widget.photoRequestUpdatedAt[track.code];
    final photoStatus = activePhoto == null && photoMediaUrls.isNotEmpty
        ? 'Выполнен'
        : activePhoto?.statusLabel ?? 'Не запрошен';
    final photoNote = activePhoto?.wishes?.trim().isNotEmpty == true
        ? activePhoto!.wishes!.trim()
        : widget.photoRequestNotes[track.code]?.trim() ?? '';
    final isPhotoRequested =
        activePhoto != null ||
        widget.requestedPhotoReports.contains(track.code) ||
        photoMediaUrls.isNotEmpty;
    final canRequestPhoto = track.isPending && !isPhotoRequested;
    final canEditPhoto =
        activePhoto?.canChange == true &&
        (track.isPending || activePhoto?.reportType == 'custom');

    final apiProductInfo = track.productInfo;
    final localProductInfo = widget.productInfos[track.code];
    var productName = apiProductInfo?.name ?? localProductInfo?.name ?? '';
    var productQuantity =
        apiProductInfo?.quantity ?? localProductInfo?.quantity;
    var productImageUrls = localProductInfo?.images.isNotEmpty == true
        ? localProductInfo!.images
        : apiProductInfo?.imageUrl?.trim().isNotEmpty == true
        ? <String>[apiProductInfo!.imageUrl!]
        : const <String>[];
    final productNameController = TextEditingController(text: productName);
    final productQuantityController = TextEditingController(
      text: productQuantity?.toString() ?? '',
    );
    var isEditingProduct = false;
    var isSavingProduct = false;
    XFile? selectedProductImage;
    final canEditProductInfo =
        embeddedInAssembly ||
        track.status == 'В ожидании' ||
        track.status == 'На складе' ||
        track.status == 'На сборке' ||
        track.status == 'Отправлен';

    final visibleQuestions = track.questions
        .where((question) => question.status != 'cancelled')
        .toList(growable: false);
    var pendingLocalQuestion = (widget.askedQuestions[track.code] ?? '').trim();
    final canAskQuestion =
        track.status == 'В ожидании' || track.status == 'На складе';
    final hasActiveTransferRequest = visibleQuestions.any(
      (question) =>
          question.questionType == _clientCodeTransferQuestionType &&
          question.isActive,
    );
    final canTransferClientCode =
        !embeddedInAssembly &&
        track.assembly == null &&
        !hasActiveTransferRequest &&
        (track.statusCode == 'pending' || track.statusCode == 'in_warehouse');
    final canRequestReturn =
        !embeddedInAssembly &&
        track.status == 'На складе' &&
        track.statusCode == 'in_warehouse' &&
        !widget.returnRequestedTracks.contains(track.code);
    var comment = (widget.overrideComments[track.code] ?? track.comment ?? '')
        .trim();
    final commentController = TextEditingController(text: comment);
    var isEditingComment = false;
    var isSavingComment = false;
    final returnCodeController = TextEditingController();
    var isEditingReturn = false;
    var isSavingReturn = false;
    var isConfirmingReturn = false;
    var isCreatingQuestion = false;
    var isSavingQuestion = false;

    void closeAndRun(BuildContext sheetContext, VoidCallback callback) {
      Navigator.of(sheetContext).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    }

    await showBlurredModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            // All tabs and their callbacks belong to the modal, not the card.
            final context = sheetContext;
            Widget buildMainTab() {
              final hasProductInfo =
                  productName.trim().isNotEmpty ||
                  productQuantity != null ||
                  productImageUrls.isNotEmpty;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            onTap: () =>
                                _showTrackStatusTimeline(context, track),
                            borderRadius: BorderRadius.circular(18),
                            child: _TrackSheetMetaCard(
                              icon: Icons.route_rounded,
                              title: 'Текущий статус',
                              value: track.status,
                            ),
                          ),
                        ),
                      ),
                      if (canTransferClientCode) ...[
                        const SizedBox(width: 10),
                        _TrackSheetCompactAction(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Перенести трек',
                          onTap: () => widget.onTransferClientCode(track),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _TrackSheetMetaCard(
                          icon: Icons.add_circle_outline_rounded,
                          title: 'Добавлен',
                          value: dateFormat.format(track.createdAt),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TrackSheetMetaCard(
                          icon: Icons.update_rounded,
                          title: 'Обновлён',
                          value: dateFormat.format(track.updatedAt),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _TrackFilterSectionCard(
                    icon: Icons.sticky_note_2_outlined,
                    title: 'Комментарий пользователя',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isEditingComment) ...[
                          AppGradientInputFrame(
                            child: TextField(
                              controller: commentController,
                              maxLines: 4,
                              scrollPadding: const EdgeInsets.only(bottom: 180),
                              onTapOutside: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                              decoration: const InputDecoration(
                                hintText: 'Введите комментарий…',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _TrackSheetSecondaryButton(
                                  label: 'Отмена',
                                  onTap: isSavingComment
                                      ? () {}
                                      : () => setSheetState(() {
                                          commentController.text = comment;
                                          isEditingComment = false;
                                        }),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _TrackSheetPrimaryButton(
                                  label: isSavingComment
                                      ? 'Сохраняем…'
                                      : 'Сохранить',
                                  icon: Icons.check_rounded,
                                  onTap: isSavingComment
                                      ? null
                                      : () async {
                                          final value = commentController.text
                                              .trim();
                                          setSheetState(
                                            () => isSavingComment = true,
                                          );
                                          final saved = await widget
                                              .onSaveComment(track, value);
                                          if (!sheetContext.mounted) return;
                                          setSheetState(() {
                                            isSavingComment = false;
                                            if (saved) {
                                              comment = value;
                                              isEditingComment = false;
                                            }
                                          });
                                        },
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          _TaskDetailBlock(
                            title: 'Заметка',
                            text: comment.isEmpty
                                ? 'Комментарий не добавлен'
                                : comment,
                            muted: comment.isEmpty,
                          ),
                          const SizedBox(height: 10),
                          _TrackSheetSecondaryButton(
                            label: comment.isEmpty
                                ? 'Добавить комментарий'
                                : 'Изменить комментарий',
                            onTap: () =>
                                setSheetState(() => isEditingComment = true),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TrackFilterSectionCard(
                    icon: Icons.inventory_2_outlined,
                    title: tr(context, ru: 'О товаре', zh: '商品信息'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isEditingProduct)
                          _InlineProductEditor(
                            nameController: productNameController,
                            quantityController: productQuantityController,
                            existingImageUrl: productImageUrls.firstOrNull,
                            selectedImage: selectedProductImage,
                            saving: isSavingProduct,
                            onPickImage: () async {
                              try {
                                final picked = await ImagePicker().pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 85,
                                );
                                if (picked != null) {
                                  setSheetState(
                                    () => selectedProductImage = picked,
                                  );
                                }
                              } catch (error) {
                                if (sheetContext.mounted) {
                                  _showStyledSnackBar(
                                    sheetContext,
                                    tr(
                                      context,
                                      ru: 'Не удалось открыть галерею: $error',
                                      zh: '无法打开相册：$error',
                                    ),
                                    isError: true,
                                  );
                                }
                              }
                            },
                            onCancel: () => setSheetState(() {
                              productNameController.text = productName;
                              productQuantityController.text =
                                  productQuantity?.toString() ?? '';
                              selectedProductImage = null;
                              isEditingProduct = false;
                            }),
                            onSave: () async {
                              final name = productNameController.text.trim();
                              final quantity =
                                  int.tryParse(
                                    productQuantityController.text.trim(),
                                  ) ??
                                  1;
                              setSheetState(() => isSavingProduct = true);
                              final saved = await widget.onSaveProduct(
                                track,
                                name,
                                quantity,
                                productImageUrls,
                                selectedProductImage,
                              );
                              if (!sheetContext.mounted) return;
                              setSheetState(() {
                                isSavingProduct = false;
                                if (saved) {
                                  productName = name;
                                  productQuantity = quantity;
                                  selectedProductImage = null;
                                  isEditingProduct = false;
                                }
                              });
                            },
                          )
                        else if (hasProductInfo)
                          _TrackProductPreview(
                            name: productName,
                            quantity: productQuantity,
                            imageUrls: productImageUrls,
                            trackCode: track.code,
                            onTap: productImageUrls.isEmpty
                                ? null
                                : () => _openMediaViewer(
                                    context,
                                    productImageUrls,
                                    track,
                                  ),
                            onEdit: canEditProductInfo
                                ? () => setSheetState(
                                    () => isEditingProduct = true,
                                  )
                                : null,
                          )
                        else
                          _TrackDetailEmptyState(
                            icon: Icons.inventory_2_outlined,
                            text: tr(
                              context,
                              ru: 'Информация о товаре ещё не заполнена',
                              zh: '尚未填写商品信息',
                            ),
                          ),
                        if (canEditProductInfo && !isEditingProduct) ...[
                          const SizedBox(height: 10),
                          _TrackSheetSecondaryButton(
                            label: hasProductInfo
                                ? 'Изменить информацию'
                                : 'Заполнить информацию',
                            onTap: () =>
                                setSheetState(() => isEditingProduct = true),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (track.spItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _TrackSpItemsBlock(items: track.spItems),
                  ],
                  if (embeddedInAssembly && widget.assembly != null) ...[
                    const SizedBox(height: 12),
                    AssemblyScanTrackVideoLink(
                      assemblyId: widget.assembly!.id,
                      assemblyNumber: widget.assembly!.number,
                      track: track,
                    ),
                  ],
                  if (track.isPending && !embeddedInAssembly) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => closeAndRun(
                        sheetContext,
                        () => widget.onDeleteTrack(track),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Удалить трек'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ],
              );
            }

            Widget buildPhotoTab() {
              if (!isPhotoRequested && !canRequestPhoto) {
                return const _TrackDetailEmptyState(
                  icon: Icons.photo_library_outlined,
                  text: 'Фотоотчёт недоступен для текущего статуса трека',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isPhotoRequested) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _TaskStatusBadge(
                        text: photoStatus,
                        color: _taskStatusColor(sheetContext, photoStatus),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (activePhoto != null)
                      PhotoReportSummary(request: activePhoto)
                    else if (track.photoRequests.isNotEmpty)
                      PhotoReportSummary(request: track.photoRequests.last),
                    if (photoNote.isNotEmpty)
                      _TaskDetailBlock(
                        title: 'Пожелание',
                        text: photoNote.isEmpty
                            ? 'Пожелание не указано'
                            : photoNote,
                        muted: photoNote.isEmpty,
                      ),
                    if (activePhoto?.warehouseComment?.trim().isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 10),
                      _TaskDetailBlock(
                        title: 'Комментарий склада',
                        text: activePhoto!.warehouseComment!.trim(),
                      ),
                    ],
                    if (photoMediaUrls.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _TrackFilterSectionCard(
                        icon: Icons.photo_library_rounded,
                        title: 'Фото и видео',
                        child: _TrackPhotoGrid(
                          mediaUrls: photoMediaUrls,
                          track: track,
                          onTap: (index) => _openMediaViewer(
                            context,
                            photoMediaUrls,
                            track,
                            index,
                          ),
                        ),
                      ),
                    ],
                    if (photoCreated != null || photoUpdated != null) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          if (photoCreated != null)
                            _TaskDateLabel(
                              label: 'Создан',
                              value: dateFormat.format(photoCreated),
                            ),
                          if (photoUpdated != null)
                            _TaskDateLabel(
                              label: 'Обновлён',
                              value: dateFormat.format(photoUpdated),
                            ),
                        ],
                      ),
                    ],
                    if (activePhoto?.canChange == true) ...[
                      const SizedBox(height: 14),
                      if (canEditPhoto)
                        _TrackSheetSecondaryButton(
                          label: tr(
                            sheetContext,
                            ru: track.isPending
                                ? 'Изменить фотоотчёт'
                                : 'Изменить пожелания',
                            zh: track.isPending ? '修改拍照申请' : '修改检查要求',
                          ),
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            widget.onEditPhotoWish(track);
                          },
                        ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          widget.onCancelPhotoRequest(track);
                        },
                        child: Text(tr(sheetContext, ru: 'Отменить', zh: '取消')),
                      ),
                    ],
                  ] else ...[
                    const _TrackDetailEmptyState(
                      icon: Icons.photo_camera_outlined,
                      text: 'Фотоотчёт ещё не запрошен',
                    ),
                    const SizedBox(height: 12),
                    _TrackSheetPrimaryButton(
                      label: tr(
                        sheetContext,
                        ru: 'Выбрать фотоотчёт',
                        zh: '选择拍照报告',
                      ),
                      icon: Icons.photo_camera_outlined,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        widget.onRequestPhotoInline(track, '');
                      },
                    ),
                  ],
                ],
              );
            }

            Widget buildQuestionsTab() {
              final items = <_QuestionDetailsItem>[
                for (var i = 0; i < visibleQuestions.length; i++)
                  _QuestionDetailsItem.fromQuestion(
                    visibleQuestions[i],
                    visibleQuestions[i].questionType ==
                            _clientCodeTransferQuestionType
                        ? 'Перенос кода клиента'
                        : visibleQuestions.length > 1
                        ? 'Вопрос ${i + 1}'
                        : 'Вопрос',
                    track.code,
                  ),
                if (pendingLocalQuestion.isNotEmpty && visibleQuestions.isEmpty)
                  _QuestionDetailsItem(
                    title: 'Вопрос',
                    statusLabel: widget.questionStatus[track.code] ?? 'Новый',
                    statusColor: Colors.orange,
                    question: pendingLocalQuestion,
                    answer: null,
                    answerPhotoUrls: const [],
                    trackCode: track.code,
                    createdAt:
                        widget.questionCreatedAt[track.code] ?? DateTime.now(),
                    answeredAt: null,
                    canCancel: true,
                  ),
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (items.isEmpty)
                    const _TrackDetailEmptyState(
                      icon: Icons.help_outline_rounded,
                      text: 'По этому треку пока нет вопросов',
                    )
                  else
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _QuestionDetailsCard(
                        item: items[i],
                        dateFormat: dateFormat,
                      ),
                    ],
                  if (canAskQuestion) ...[
                    const SizedBox(height: 14),
                    if (isCreatingQuestion) ...[
                      _TrackSheetMetaCard(
                        icon: Icons.lock_outline_rounded,
                        title: 'Текст задачи',
                        value: _unknownTrackQuestionText,
                        valueMaxLines: 4,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _TrackSheetSecondaryButton(
                              label: 'Отмена',
                              onTap: isSavingQuestion
                                  ? () {}
                                  : () => setSheetState(
                                      () => isCreatingQuestion = false,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _TrackSheetPrimaryButton(
                              label: isSavingQuestion
                                  ? 'Отправляем…'
                                  : 'Отправить',
                              icon: Icons.send_rounded,
                              onTap: isSavingQuestion
                                  ? null
                                  : () async {
                                      setSheetState(
                                        () => isSavingQuestion = true,
                                      );
                                      final saved = await widget
                                          .onAskQuestionInline(track);
                                      if (!sheetContext.mounted) return;
                                      setSheetState(() {
                                        isSavingQuestion = false;
                                        if (saved) {
                                          pendingLocalQuestion =
                                              _unknownTrackQuestionText;
                                          isCreatingQuestion = false;
                                        }
                                      });
                                    },
                            ),
                          ),
                        ],
                      ),
                    ] else
                      _TrackSheetPrimaryButton(
                        label: 'Создать новый вопрос',
                        icon: Icons.add_comment_outlined,
                        onTap: () =>
                            setSheetState(() => isCreatingQuestion = true),
                      ),
                  ],
                ],
              );
            }

            Widget buildReturnTab() {
              if (track.id == null || embeddedInAssembly) {
                return const _TrackDetailEmptyState(
                  icon: Icons.assignment_return_outlined,
                  text: 'Возврат недоступен в этом представлении',
                );
              }
              final future = returnFuture;
              if (future == null) {
                return const _TrackDetailEmptyState(
                  icon: Icons.assignment_return_outlined,
                  text: 'Информация о возврате недоступна',
                );
              }
              return FutureBuilder<TrackReturnInfo?>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _TrackDetailEmptyState(
                          icon: Icons.cloud_off_outlined,
                          text: 'Не удалось загрузить информацию о возврате',
                        ),
                        const SizedBox(height: 12),
                        _TrackSheetSecondaryButton(
                          label: 'Повторить',
                          onTap: () => setSheetState(() {
                            returnFuture = widget.onLoadReturn(track.id!);
                          }),
                        ),
                      ],
                    );
                  }
                  final info = snapshot.data;
                  if (info == null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _TrackDetailEmptyState(
                          icon: Icons.assignment_return_outlined,
                          text: 'Возврат по этому треку ещё не оформлен',
                        ),
                        if (canRequestReturn) ...[
                          const SizedBox(height: 12),
                          if (isEditingReturn) ...[
                            _TrackSheetNoticeCard(
                              icon: Icons.schedule_rounded,
                              text:
                                  'Возврат можно оформить в окно с 13:00 до 15:00 по Китаю.',
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(height: 10),
                            AppGradientInputFrame(
                              child: TextField(
                                controller: returnCodeController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                scrollPadding: const EdgeInsets.only(
                                  bottom: 160,
                                ),
                                onTapOutside: (_) => FocusManager
                                    .instance
                                    .primaryFocus
                                    ?.unfocus(),
                                decoration: const InputDecoration(
                                  hintText: 'Введите код возврата…',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _TrackSheetSecondaryButton(
                                    label: 'Отмена',
                                    onTap: isSavingReturn
                                        ? () {}
                                        : () => setSheetState(
                                            () => isEditingReturn = false,
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _TrackSheetPrimaryButton(
                                    label: isSavingReturn
                                        ? 'Отправляем…'
                                        : 'Оформить',
                                    icon: Icons.assignment_return_rounded,
                                    onTap: isSavingReturn
                                        ? null
                                        : () async {
                                            final code = returnCodeController
                                                .text
                                                .trim();
                                            if (code.isEmpty) return;
                                            setSheetState(
                                              () => isSavingReturn = true,
                                            );
                                            final saved = await widget
                                                .onRequestReturnInline(
                                                  track,
                                                  code,
                                                );
                                            if (!sheetContext.mounted) return;
                                            setSheetState(() {
                                              isSavingReturn = false;
                                              if (saved) {
                                                isEditingReturn = false;
                                                returnFuture = widget
                                                    .onLoadReturn(track.id!);
                                              }
                                            });
                                          },
                                  ),
                                ),
                              ],
                            ),
                          ] else
                            _TrackSheetPrimaryButton(
                              label: 'Запросить возврат',
                              icon: Icons.assignment_return_outlined,
                              onTap: () =>
                                  setSheetState(() => isEditingReturn = true),
                            ),
                        ],
                      ],
                    );
                  }
                  final canEditCode =
                      info.status == 'pending' ||
                      info.status == 'in_progress' ||
                      info.status == 'completed';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _TaskStatusBadge(
                          text: info.statusLabel,
                          color: _taskStatusColor(
                            sheetContext,
                            info.statusLabel,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _TrackSheetMetaCard(
                        icon: Icons.pin_outlined,
                        title: 'Код возврата',
                        value: info.returnCode,
                        valueMaxLines: 2,
                      ),
                      if (info.note?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 10),
                        _TaskDetailBlock(
                          title: 'Комментарий',
                          text: info.note!.trim(),
                        ),
                      ],
                      if (info.screenshotUrl?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        _TrackFilterSectionCard(
                          icon: Icons.image_outlined,
                          title: 'Подтверждение',
                          child: _TrackPhotoGrid(
                            mediaUrls: [info.screenshotUrl!],
                            track: track,
                            onTap: (_) => _openMediaViewer(context, [
                              info.screenshotUrl!,
                            ], track),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          _TaskDateLabel(
                            label: 'Создан',
                            value: dateFormat.format(info.createdAt),
                          ),
                          if (info.updatedAt != null)
                            _TaskDateLabel(
                              label: 'Обновлён',
                              value: dateFormat.format(info.updatedAt!),
                            ),
                        ],
                      ),
                      if (info.canConfirmCompletion) ...[
                        const SizedBox(height: 14),
                        _TrackSheetPrimaryButton(
                          label: isConfirmingReturn
                              ? tr(context, ru: 'Подтверждаем…', zh: '确认中…')
                              : tr(
                                  context,
                                  ru: 'Подтвердить возврат',
                                  zh: '确认退货',
                                ),
                          icon: Icons.delete_forever_outlined,
                          onTap: isConfirmingReturn
                              ? null
                              : () async {
                                  setSheetState(
                                    () => isConfirmingReturn = true,
                                  );
                                  final success = await widget
                                      .onConfirmCompletedReturn(track);
                                  if (!sheetContext.mounted) return;
                                  if (success) {
                                    Navigator.of(sheetContext).pop();
                                    return;
                                  }
                                  setSheetState(
                                    () => isConfirmingReturn = false,
                                  );
                                },
                        ),
                      ],
                      if (canEditCode) ...[
                        const SizedBox(height: 14),
                        _TrackSheetPrimaryButton(
                          label: 'Изменить код возврата',
                          icon: Icons.edit_outlined,
                          onTap: () async {
                            final code = await _showReturnCodeEditor(
                              context,
                              currentCode: info.returnCode,
                            );
                            if (code == null || code == info.returnCode) return;
                            final updated = await widget.onUpdateReturnCode(
                              track.id!,
                              code,
                            );
                            if (!sheetContext.mounted) return;
                            if (updated == null) {
                              _showStyledSnackBar(
                                context,
                                'Не удалось изменить код возврата',
                                isError: true,
                              );
                              return;
                            }
                            setSheetState(() {
                              returnFuture = Future.value(updated);
                            });
                            _showStyledSnackBar(
                              context,
                              'Код возврата обновлён',
                            );
                          },
                        ),
                      ],
                    ],
                  );
                },
              );
            }

            Widget buildWarehouseDeliveryTab() {
              if (canShowTrackWarehouseDelivery(track)) {
                return TrackWarehouseDeliveryPanel(track: track);
              }
              return const _TrackDetailEmptyState(
                icon: Icons.local_shipping_outlined,
                text:
                    'Информация о доставке до склада для этого трека недоступна',
              );
            }

            final child = switch (selectedTab) {
              1 => buildWarehouseDeliveryTab(),
              2 => buildPhotoTab(),
              3 => buildQuestionsTab(),
              4 => buildReturnTab(),
              _ => buildMainTab(),
            };
            return _TrackSheetSurface(
              icon: Icons.local_shipping_rounded,
              title: track.code,
              subtitle: 'Карточка трек-номера',
              useMaxHeight: true,
              keyboardAware: true,
              pinnedChild: ClientTrackDetailTabs(
                selectedIndex: selectedTab,
                visibleIndices: showWarehouseDeliveryTab
                    ? const [0, 1, 2, 3, 4]
                    : const [0, 2, 3, 4],
                onSelected: (value) => setSheetState(() => selectedTab = value),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: KeyedSubtree(key: ValueKey(selectedTab), child: child),
              ),
            );
          },
        );
      },
    );
    _disposeControllersAfterSheetClose([
      commentController,
      productNameController,
      productQuantityController,
      returnCodeController,
    ]);
  }

  Future<String?> _showReturnCodeEditor(
    BuildContext context, {
    required String currentCode,
  }) async {
    var value = currentCode;
    return showBlurredModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) => _TrackSheetSurface(
            icon: Icons.pin_outlined,
            title: 'Код возврата',
            subtitle: 'Измените код, который склад использует для возврата',
            keyboardAware: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TrackFilterSectionCard(
                  icon: Icons.edit_outlined,
                  title: 'Новый код возврата',
                  child: AppGradientInputFrame(
                    child: TextFormField(
                      initialValue: currentCode,
                      autofocus: true,
                      onChanged: (text) => setSheetState(() => value = text),
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: 'Введите код возврата',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _TrackSheetPrimaryButton(
                  label: 'Сохранить код',
                  icon: Icons.check_rounded,
                  onTap: value.trim().isEmpty
                      ? null
                      : () => Navigator.of(sheetContext).pop(value.trim()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Legacy sheet entry point kept temporarily while the compact modal rolls out.
  // ignore: unused_element
  void _handlePhotoMarkerTap(
    BuildContext context, {
    required TrackItem track,
    required PhotoRequest? activePhoto,
    required List<String> mediaUrls,
    required String statusLabel,
    required DateTime? createdAt,
    required DateTime? updatedAt,
    required bool canRequestPhoto,
    required bool canCancelPhoto,
  }) {
    HapticFeedback.selectionClick();
    final hasRequestedPhoto =
        activePhoto != null ||
        widget.requestedPhotoReports.contains(track.code) ||
        mediaUrls.isNotEmpty;
    if (hasRequestedPhoto) {
      final note = activePhoto?.wishes?.trim().isNotEmpty == true
          ? activePhoto!.wishes!.trim()
          : widget.photoRequestNotes[track.code]?.trim() ?? '';
      _showPhotoRequestDetailsSheet(
        context,
        track: track,
        statusLabel: activePhoto == null && mediaUrls.isNotEmpty
            ? 'Выполнен'
            : statusLabel,
        note: note,
        warehouseComment: activePhoto?.warehouseComment,
        createdAt: createdAt,
        updatedAt: updatedAt,
        mediaUrls: mediaUrls,
        canEdit:
            canCancelPhoto &&
            activePhoto?.canChange == true &&
            (track.isPending || activePhoto?.reportType == 'custom'),
        canCancel: canCancelPhoto && activePhoto?.canChange == true,
      );
      return;
    }

    if (canRequestPhoto) {
      widget.onPhotoRequest(track);
      return;
    }

    _showStyledSnackBar(
      context,
      'Фотоотчёт недоступен для этого статуса',
      isError: true,
    );
  }

  // ignore: unused_element
  void _handleProductMarkerTap(
    BuildContext context, {
    required TrackItem track,
    required bool canEdit,
  }) {
    HapticFeedback.selectionClick();
    if (canEdit) {
      widget.onEditProduct(track);
      return;
    }

    _showStyledSnackBar(
      context,
      'Информация о товаре недоступна для этого статуса',
      isError: true,
    );
  }

  // ignore: unused_element
  void _handleQuestionMarkerTap(
    BuildContext context, {
    required TrackItem track,
    required bool canAskQuestion,
    required List<TrackQuestion> visibleQuestions,
    required String pendingLocalQuestion,
  }) {
    HapticFeedback.selectionClick();
    if (visibleQuestions.isNotEmpty || pendingLocalQuestion.isNotEmpty) {
      _showQuestionDetailsSheet(
        context,
        track: track,
        visibleQuestions: visibleQuestions,
        pendingLocalQuestion: pendingLocalQuestion,
      );
      return;
    }

    if (canAskQuestion) {
      widget.onAskQuestion(track);
      return;
    }

    _showStyledSnackBar(
      context,
      'Вопрос недоступен для этого статуса',
      isError: true,
    );
  }

  Future<void> _showPhotoRequestDetailsSheet(
    BuildContext context, {
    required TrackItem track,
    required String statusLabel,
    required String note,
    required String? warehouseComment,
    required DateTime? createdAt,
    required DateTime? updatedAt,
    required List<String> mediaUrls,
    required bool canEdit,
    required bool canCancel,
  }) async {
    final df = DateFormat('dd.MM.yyyy', 'ru');
    final statusColor = _taskStatusColor(context, statusLabel);
    await showBlurredModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => _TrackSheetSurface(
        icon: Icons.photo_library_rounded,
        title: 'Фотоотчёт',
        subtitle: track.code,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _TaskStatusBadge(text: statusLabel, color: statusColor),
            ),
            const SizedBox(height: 12),
            if (track.activePhotoRequest != null)
              PhotoReportSummary(request: track.activePhotoRequest!),
            if (note.isNotEmpty)
              _TaskDetailBlock(
                title: 'Пожелание',
                text: note.isNotEmpty ? note : 'Пожелание не указано',
                muted: note.isEmpty,
              ),
            if (warehouseComment?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              _TaskDetailBlock(
                title: 'Комментарий склада',
                text: warehouseComment!.trim(),
              ),
            ],
            if (mediaUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Фото и видео',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                addAutomaticKeepAlives: false,
                addSemanticIndexes: false,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1,
                ),
                itemCount: mediaUrls.length,
                itemBuilder: (itemContext, index) {
                  final fullUrl = ApiConfig.getMediaUrl(mediaUrls[index]);
                  final isVideo = _isVideoUrl(fullUrl);
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openMediaViewer(context, mediaUrls, track, index);
                    },
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (isVideo)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.45),
                                    Colors.black.withValues(alpha: 0.18),
                                  ],
                                ),
                              ),
                            )
                          else
                            AppCachedMediaImage(
                              url: mediaUrls[index],
                              thumbnailSize: 360,
                              memCacheWidth: 160,
                              memCacheHeight: 160,
                              maxWidthDiskCache: 320,
                              maxHeightDiskCache: 320,
                              imageBuilder: (_, imageProvider) => DecoratedBox(
                                decoration: BoxDecoration(
                                  image: DecorationImage(
                                    image: imageProvider,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              placeholder: (_, _) => const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              errorWidget: (_, _, _) => const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 20,
                                ),
                              ),
                            ),
                          if (isVideo)
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
            if (createdAt != null || updatedAt != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  if (createdAt != null)
                    _TaskDateLabel(
                      label: 'Создан',
                      value: df.format(createdAt),
                    ),
                  if (updatedAt != null)
                    _TaskDateLabel(
                      label: 'Обновлён',
                      value: df.format(updatedAt),
                    ),
                ],
              ),
            ],
            if (canEdit || canCancel) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  if (canEdit)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          widget.onEditPhotoWish(track);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Изменить'),
                      ),
                    ),
                  if (canEdit && canCancel) const SizedBox(width: 10),
                  if (canCancel)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          widget.onCancelPhotoRequest(track);
                        },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Отменить'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showQuestionDetailsSheet(
    BuildContext context, {
    required TrackItem track,
    required List<TrackQuestion> visibleQuestions,
    required String pendingLocalQuestion,
  }) async {
    final df = DateFormat('dd.MM.yyyy', 'ru');
    final items = <_QuestionDetailsItem>[
      for (var i = 0; i < visibleQuestions.length; i++)
        _QuestionDetailsItem.fromQuestion(
          visibleQuestions[i],
          visibleQuestions.length > 1 ? 'Вопрос ${i + 1}' : 'Вопрос',
          track.code,
        ),
      if (pendingLocalQuestion.isNotEmpty && visibleQuestions.isEmpty)
        _QuestionDetailsItem(
          title: 'Вопрос',
          statusLabel: widget.questionStatus[track.code] ?? 'Новый',
          statusColor: Colors.orange,
          question: pendingLocalQuestion,
          answer: null,
          answerPhotoUrls: const [],
          trackCode: track.code,
          createdAt: widget.questionCreatedAt[track.code] ?? DateTime.now(),
          answeredAt: null,
          canCancel: true,
        ),
    ];
    if (items.isEmpty) return;
    final canCancelAny = items.any((item) => item.canCancel);

    await showBlurredModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (sheetContext) => _TrackSheetSurface(
        icon: Icons.help_rounded,
        title: 'Вопрос по треку',
        subtitle: track.code,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _QuestionDetailsCard(item: items[i], dateFormat: df),
            ],
            if (canCancelAny) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  widget.onCancelQuestion(track);
                },
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Отменить вопрос'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // A root modal can outlive this card; use its live context when rebuilding.
  Color _taskStatusColor(BuildContext context, String statusLabel) {
    final normalized = statusLabel.toLowerCase();
    if (normalized.contains('выполн') || normalized.contains('отвеч')) {
      return const Color(0xFF27C47A);
    }
    if (normalized.contains('отмен')) return Colors.redAccent;
    return context.brandPrimary;
  }

  // Legacy expanded-card renderer kept for rollback safety during rollout.
  // ignore: unused_element
  Widget _buildTrackCardHeader(
    BuildContext context, {
    required TrackItem track,
    required bool canShowCheckbox,
    required bool isSelected,
    required Color? statusColor,
    required bool photoDone,
    required bool photoPending,
    required bool questionDone,
    required bool questionPending,
    required bool hasProductInfo,
    required List<_TrackCardAction> actions,
    required bool canDelete,
    required VoidCallback onPhotoMarkerTap,
    required VoidCallback onProductMarkerTap,
    required VoidCallback onQuestionMarkerTap,
    required bool showStatusAndMarkers,
  }) {
    final dateFormat = DateFormat('dd.MM.yy', 'ru');
    final accent = context.brandPrimary;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 76),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canShowCheckbox) ...[
                          _TrackCheckbox(
                            value: isSelected,
                            accent: accent,
                            onTap: () => widget.onToggle(track),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _copyTrackCode(context, track.code),
                            child: Text(
                              track.code,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF2F2F2F),
                                fontFamily: 'Gilroy',
                                fontSize: 16,
                                height: 24 / 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _TrackDateMeta(
                          icon: CupertinoIcons.plus_circle,
                          value: dateFormat.format(track.createdAt),
                        ),
                        _TrackDateMeta(
                          icon: CupertinoIcons.arrow_2_circlepath_circle,
                          value: dateFormat.format(track.updatedAt),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showStatusAndMarkers) ...[
                const SizedBox(width: 10),
                IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showTrackStatusTimeline(context, track),
                        child: _TrackCardStatusPill(
                          text: track.status,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 44,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _TrackMarkerIcon(
                              icon: CupertinoIcons.camera_circle,
                              color: _trackMarkerColor(
                                context,
                                done: photoDone,
                                pending: photoPending,
                              ),
                              tooltip: 'Фотоотчёт',
                              onTap: onPhotoMarkerTap,
                            ),
                            const SizedBox(width: 5),
                            _TrackMarkerIcon(
                              icon: CupertinoIcons.info_circle,
                              color: _trackMarkerColor(
                                context,
                                done: hasProductInfo,
                                pending: false,
                              ),
                              tooltip: 'О товаре',
                              onTap: onProductMarkerTap,
                            ),
                            const SizedBox(width: 5),
                            _TrackMarkerIcon(
                              icon: CupertinoIcons.question_circle,
                              color: _trackMarkerColor(
                                context,
                                done: questionDone,
                                pending: questionPending,
                              ),
                              tooltip: 'Вопрос',
                              onTap: onQuestionMarkerTap,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (actions.isNotEmpty || canDelete) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: _HorizontalScrollHint(
                      child: Row(
                        children: [
                          for (var i = 0; i < actions.length; i++) ...[
                            if (i > 0) const SizedBox(width: 5),
                            _TrackCardActionChip(
                              action: actions[i],
                              accent: accent,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (canDelete) ...[
                    const SizedBox(width: 10),
                    _TrackDeleteButton(
                      onTap: () => widget.onDeleteTrack(track),
                    ),
                  ],
                ],
              ),
            ),
            if (actions.length > 2)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr(
                    context,
                    ru: 'Прокрутите действия влево →',
                    zh: '向左滑动查看更多操作 →',
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildTrackCardMediaSection(
    BuildContext context, {
    required TrackItem track,
    required String productName,
    required int? productQuantity,
    required List<String> productImageUrls,
    required List<String> photoMediaUrls,
    required bool hasProductInfo,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canUseRow =
            hasProductInfo &&
            photoMediaUrls.isNotEmpty &&
            constraints.maxWidth >= 330;
        if (canUseRow) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TrackProductPreview(
                name: productName,
                quantity: productQuantity,
                imageUrls: productImageUrls,
                trackCode: track.code,
                onEdit: () => widget.onEditProduct(track),
                onTap: productImageUrls.isNotEmpty
                    ? () => _openMediaViewer(context, productImageUrls, track)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TrackPhotoGrid(
                  mediaUrls: photoMediaUrls,
                  track: track,
                  onTap: (index) =>
                      _openMediaViewer(context, photoMediaUrls, track, index),
                ),
              ),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasProductInfo)
              _TrackProductPreview(
                name: productName,
                quantity: productQuantity,
                imageUrls: productImageUrls,
                trackCode: track.code,
                onEdit: () => widget.onEditProduct(track),
                onTap: productImageUrls.isNotEmpty
                    ? () => _openMediaViewer(context, productImageUrls, track)
                    : null,
              ),
            if (hasProductInfo && photoMediaUrls.isNotEmpty)
              const SizedBox(height: 10),
            if (photoMediaUrls.isNotEmpty)
              _TrackPhotoGrid(
                mediaUrls: photoMediaUrls,
                track: track,
                onTap: (index) =>
                    _openMediaViewer(context, photoMediaUrls, track, index),
              ),
          ],
        );
      },
    );
  }

  List<String> _collectPhotoMediaUrls(
    TrackItem track,
    PhotoRequest? activePhoto,
  ) {
    final urls = <String>[];
    final seen = <String>{};
    if (activePhoto?.mediaUrls.isNotEmpty == true) {
      for (final url in activePhoto!.mediaUrls) {
        if (seen.add(url)) urls.add(url);
      }
    }
    for (final url in track.photoReportUrls) {
      if (seen.add(url)) urls.add(url);
    }
    return urls;
  }

  Color _trackMarkerColor(
    BuildContext context, {
    required bool done,
    required bool pending,
  }) {
    if (done) return const Color(0xFF27C47A);
    if (pending) return context.brandPrimary;
    return const Color(0xFF2F2F2F).withValues(alpha: 0.28);
  }

  void _openMediaViewer(
    BuildContext context,
    List<String> mediaUrls,
    TrackItem track, [
    int initialIndex = 0,
  ]) {
    if (mediaUrls.isEmpty) return;
    final safeInitialIndex = initialIndex
        .clamp(0, mediaUrls.length - 1)
        .toInt();
    final photos = mediaUrls
        .map(
          (url) => PhotoItem(
            url: url,
            date: DateTime.now(),
            trackingNumber: track.code,
          ),
        )
        .toList();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoViewerScreen(
          item: photos[safeInitialIndex],
          allPhotos: photos,
          initialIndex: safeInitialIndex,
        ),
      ),
    );
  }

  Widget _buildBoxCard(BuildContext context, Box box) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок с номером коробки
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '#${box.number}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: context.brandPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                box.displayName(context),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Параметры коробки
          _buildBoxParam(
            context,
            icon: Icons.straighten,
            label: tr(context, ru: 'Габариты', zh: '尺寸'),
            value: box.dimensionsDisplay,
          ),
          const SizedBox(height: 6),
          _buildBoxParam(
            context,
            icon: Icons.scale,
            label: tr(context, ru: 'Вес', zh: '重量'),
            value: box.weightDisplay,
          ),
          const SizedBox(height: 6),
          _buildBoxParam(
            context,
            icon: Icons.inventory_2_outlined,
            label: tr(context, ru: 'Объём', zh: '体积'),
            value: box.volumeDisplay,
          ),
          const SizedBox(height: 6),
          _buildBoxParam(
            context,
            icon: Icons.compress,
            label: tr(context, ru: 'Плотность', zh: '密度'),
            value: box.densityDisplay,
          ),

          // Тариф и упаковка коробки (если отличаются от сборки)
          if (box.tariffName != null ||
              box.packagingTypes.isNotEmpty ||
              box.packagingUsages.isNotEmpty ||
              box.orderNumber != null) ...[
            const SizedBox(height: 8),
            if (box.orderNumber != null && box.orderNumber!.isNotEmpty)
              _buildBoxParam(
                context,
                icon: Icons.tag,
                label: tr(context, ru: 'Заказ', zh: '单号'),
                value: box.orderNumber!,
              ),
            if (box.orderNumber != null &&
                box.orderNumber!.isNotEmpty &&
                (box.tariffName != null ||
                    box.packagingTypes.isNotEmpty ||
                    box.packagingUsages.isNotEmpty))
              const SizedBox(height: 6),
            if (box.tariffName != null)
              _buildBoxParam(
                context,
                icon: Icons.local_shipping_outlined,
                label: tr(context, ru: 'Тариф', zh: '费率'),
                value: box.tariffName!,
              ),
            if (box.tariffName != null &&
                (box.packagingTypes.isNotEmpty ||
                    box.packagingUsages.isNotEmpty))
              const SizedBox(height: 6),
            if (box.packagingTypes.isNotEmpty || box.packagingUsages.isNotEmpty)
              _buildBoxParam(
                context,
                icon: Icons.inventory_2_outlined,
                label: tr(context, ru: 'Упаковка', zh: '包装'),
                value: box.packagingUsages.isNotEmpty
                    ? box.packagingUsages
                          .map((usage) => usage.displayValue)
                          .join(', ')
                    : box.packagingTypes.join(', '),
              ),
          ],
          // Фото на весах — одно большое
          if (box.photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                final allPhotos = box.photos
                    .map((p) => PhotoItem(url: p.url, date: DateTime.now()))
                    .toList();
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => PhotoViewerScreen(
                      item: allPhotos.first,
                      allPhotos: allPhotos,
                      initialIndex: 0,
                    ),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                height: 140,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AppCachedMediaImage(
                  url: box.photos.first.url,
                  thumbnailSize: 720,
                  memCacheWidth: 360,
                  memCacheHeight: 240,
                  maxWidthDiskCache: 720,
                  maxHeightDiskCache: 480,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  useOldImageOnUrlChange: false,
                  filterQuality: FilterQuality.low,
                  imageBuilder: (_, imageProvider) => DecoratedBox(
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: imageProvider,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  placeholder: (_, _) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 24),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBoxParam(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.black45),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _TrackCardAction {
  final String label;
  final VoidCallback onTap;

  const _TrackCardAction({required this.label, required this.onTap});
}

class _AssemblyTracksGrid extends StatelessWidget {
  final List<TrackItem> tracks;
  final Widget Function(TrackItem track) itemBuilder;

  const _AssemblyTracksGrid({required this.tracks, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1180
            ? 4
            : width >= 880
            ? 3
            : width >= 560
            ? 2
            : 1;
        final spacing = columns == 1 ? 20.0 : 12.0;
        final tileWidth = columns == 1
            ? width
            : (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final track in tracks)
              SizedBox(width: tileWidth, child: itemBuilder(track)),
          ],
        );
      },
    );
  }
}

class _AssemblyPlainText extends StatelessWidget {
  final String text;

  const _AssemblyPlainText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      softWrap: true,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontFamily: 'Gilroy',
        fontSize: 12.5,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _AssemblyBoxFact extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final IconData icon;

  const _AssemblyBoxFact({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: context.brandPrimary),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 13,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackCheckbox extends StatelessWidget {
  final bool value;
  final Color accent;
  final VoidCallback onTap;

  const _TrackCheckbox({
    required this.value,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: value ? accent : Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: value ? accent : Colors.black.withValues(alpha: 0.18),
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.18),
                    blurRadius: 10,
                    spreadRadius: -6,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: value
            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
            : null,
      ),
    );
  }
}

class _TrackDateMeta extends StatelessWidget {
  final IconData icon;
  final String value;

  const _TrackDateMeta({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(width: 1),
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontFamily: 'Gilroy',
            fontSize: 12,
            height: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TrackCardStatusPill extends StatelessWidget {
  final String text;
  final Color? color;

  const _TrackCardStatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.brandPrimary;
    final isLight = accent.computeLuminance() > 0.58;
    final bg = isLight
        ? accent.withValues(alpha: 0.42)
        : accent.withValues(alpha: 0.12);
    final textColor = isLight ? AppColors.textPrimary : accent;

    return Container(
      constraints: const BoxConstraints(minHeight: 28, maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.20)),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontFamily: 'Gilroy',
          fontSize: 12.5,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TrackMarkerIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  const _TrackMarkerIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(child: Icon(icon, size: 17, color: color)),
    );
    if (onTap == null) return child;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class _TaskStatusBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _TaskStatusBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final textColor = _taskReadableColor(color);
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: textColor,
          fontFamily: 'Gilroy',
          fontSize: 12.2,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

Color _taskReadableColor(Color color) {
  return color.computeLuminance() > 0.58 ? AppColors.textPrimary : color;
}

class _TrackTaskIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _TrackTaskIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: color.withValues(alpha: 0.12)),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}

class _TrackTaskChevronButton extends StatelessWidget {
  final bool expanded;

  const _TrackTaskChevronButton({required this.expanded});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Icon(
        expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
        size: 15,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _TaskDetailBlock extends StatelessWidget {
  final String title;
  final String text;
  final bool muted;

  const _TaskDetailBlock({
    required this.title,
    required this.text,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x0A000000),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.black54,
              fontFamily: 'Gilroy',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            text,
            style: TextStyle(
              color: muted ? Colors.black38 : const Color(0xFF2F2F2F),
              fontFamily: 'Gilroy',
              fontSize: 14,
              height: 18 / 14,
              fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskDateLabel extends StatelessWidget {
  final String label;
  final String value;

  const _TaskDateLabel({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: $value',
      style: const TextStyle(
        color: Colors.black45,
        fontFamily: 'Gilroy',
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _QuestionDetailsItem {
  final String title;
  final String statusLabel;
  final Color statusColor;
  final String question;
  final String? answer;
  final List<String> answerPhotoUrls;
  final String trackCode;
  final DateTime createdAt;
  final DateTime? answeredAt;
  final bool canCancel;

  const _QuestionDetailsItem({
    required this.title,
    required this.statusLabel,
    required this.statusColor,
    required this.question,
    required this.answer,
    required this.answerPhotoUrls,
    required this.trackCode,
    required this.createdAt,
    required this.answeredAt,
    required this.canCancel,
  });

  factory _QuestionDetailsItem.fromQuestion(
    TrackQuestion question,
    String title,
    String trackCode,
  ) {
    return _QuestionDetailsItem(
      title: title,
      statusLabel: question.statusLabel,
      statusColor: question.hasResponse
          ? const Color(0xFF27C47A)
          : question.status == 'cancelled'
          ? Colors.redAccent
          : Colors.orange,
      question: question.question,
      answer: question.hasAnswer ? question.answer : null,
      answerPhotoUrls: question.answerPhotoUrls,
      trackCode: trackCode,
      createdAt: question.createdAt,
      answeredAt: question.answeredAt,
      canCancel: question.isActive,
    );
  }
}

class _QuestionDetailsCard extends StatelessWidget {
  final _QuestionDetailsItem item;
  final DateFormat dateFormat;

  const _QuestionDetailsCard({required this.item, required this.dateFormat});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.statusColor.withValues(alpha: 0.24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            offset: Offset(0, 4),
            blurRadius: 14,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _QuestionBadge(color: item.statusColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: Color(0xFF2F2F2F),
                        fontFamily: 'Gilroy',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    _TaskDateLabel(
                      label: 'Создан',
                      value: dateFormat.format(item.createdAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: _TaskStatusBadge(
                  text: item.statusLabel,
                  color: item.statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TaskDetailBlock(title: 'Вопрос', text: item.question),
          if (item.answer?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            _TaskDetailBlock(title: 'Ответ', text: item.answer!.trim()),
          ],
          if (item.answerPhotoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            _QuestionAnswerPhotoGrid(
              urls: item.answerPhotoUrls,
              trackCode: item.trackCode,
            ),
          ],
          if (item.answeredAt != null) ...[
            const SizedBox(height: 10),
            _QuestionMetaPill(
              icon: CupertinoIcons.checkmark_alt_circle,
              text: 'Отвечен: ${dateFormat.format(item.answeredAt!)}',
              color: const Color(0xFF27C47A),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionBadge extends StatelessWidget {
  final Color color;

  const _QuestionBadge({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      alignment: Alignment.center,
      child: Icon(CupertinoIcons.question_circle_fill, size: 18, color: color),
    );
  }
}

class _QuestionMetaPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _QuestionMetaPill({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = _taskReadableColor(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontFamily: 'Gilroy',
                fontSize: 11.5,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionAnswerPhotoGrid extends StatelessWidget {
  final List<String> urls;
  final String trackCode;

  const _QuestionAnswerPhotoGrid({required this.urls, required this.trackCode});

  void _open(BuildContext context, int index) {
    final photos = urls
        .map(
          (url) => PhotoItem(
            url: url,
            date: DateTime.now(),
            trackingNumber: trackCode,
          ),
        )
        .toList();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PhotoViewerScreen(
          item: photos[index],
          allPhotos: photos,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Фото склада',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontFamily: 'Gilroy',
            fontSize: 12.5,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 1,
          ),
          itemCount: urls.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () => _open(context, index),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.035),
                  ),
                ),
                child: AppCachedMediaImage(
                  url: urls[index],
                  thumbnailSize: 360,
                  fit: BoxFit.cover,
                  memCacheWidth: 180,
                  memCacheHeight: 180,
                  maxWidthDiskCache: 360,
                  maxHeightDiskCache: 360,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, _) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: Colors.black.withValues(alpha: 0.06),
                    child: const Icon(Icons.broken_image_outlined, size: 20),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _QuestionTextPanel extends StatelessWidget {
  final String title;
  final String text;
  final bool muted;

  const _QuestionTextPanel({
    required this.title,
    required this.text,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: muted ? const Color(0xFFF6FBF8) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontSize: 12.2,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            text,
            style: TextStyle(
              color: muted ? AppColors.textSecondary : AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 13.5,
              height: 1.28,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackCardActionChip extends StatelessWidget {
  final _TrackCardAction action;
  final Color accent;

  const _TrackCardActionChip({required this.action, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withValues(alpha: 0.16)),
          ),
          alignment: Alignment.center,
          child: Text(
            action.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontFamily: 'Gilroy',
              fontSize: 12.5,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _HorizontalScrollHint extends StatefulWidget {
  final Widget child;

  const _HorizontalScrollHint({required this.child});

  @override
  State<_HorizontalScrollHint> createState() => _HorizontalScrollHintState();
}

class _HorizontalScrollHintState extends State<_HorizontalScrollHint> {
  final ScrollController _controller = ScrollController();
  bool _showLeadingHint = false;
  bool _showTrailingHint = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateHints);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHints());
  }

  @override
  void didUpdateWidget(covariant _HorizontalScrollHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHints());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateHints);
    _controller.dispose();
    super.dispose();
  }

  void _updateHints() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (!position.hasContentDimensions) return;

    final canScroll = position.maxScrollExtent > 1;
    final showLeading = canScroll && position.pixels > 1;
    final showTrailing =
        canScroll && position.pixels < position.maxScrollExtent - 1;

    if (_showLeadingHint == showLeading && _showTrailingHint == showTrailing) {
      return;
    }

    setState(() {
      _showLeadingHint = showLeading;
      _showTrailingHint = showTrailing;
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateHints());

    return Stack(
      fit: StackFit.expand,
      children: [
        SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: widget.child,
        ),
        if (_showLeadingHint)
          Positioned.fill(
            right: null,
            child: _HorizontalScrollEdgeHint(
              alignment: Alignment.centerLeft,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              icon: CupertinoIcons.chevron_left,
            ),
          ),
        if (_showTrailingHint)
          Positioned.fill(
            left: null,
            child: _HorizontalScrollEdgeHint(
              alignment: Alignment.centerRight,
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              icon: CupertinoIcons.chevron_right,
            ),
          ),
      ],
    );
  }
}

class _HorizontalScrollEdgeHint extends StatelessWidget {
  final Alignment alignment;
  final Alignment begin;
  final Alignment end;
  final IconData icon;

  const _HorizontalScrollEdgeHint({
    required this.alignment,
    required this.begin,
    required this.end,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 34,
        alignment: alignment,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: begin,
            end: end,
            colors: const [Colors.white, Color(0x00FFFFFF)],
          ),
        ),
        child: Icon(
          icon,
          size: 14,
          color: context.brandPrimary.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

class _TrackDeleteButton extends StatelessWidget {
  final VoidCallback onTap;

  const _TrackDeleteButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr(context, ru: 'Удалить трек', zh: '删除运单'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFFE1A1A),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Icon(
            CupertinoIcons.trash,
            size: 12,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _InlineProductEditor extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController quantityController;
  final String? existingImageUrl;
  final XFile? selectedImage;
  final bool saving;
  final VoidCallback onPickImage;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _InlineProductEditor({
    required this.nameController,
    required this.quantityController,
    required this.existingImageUrl,
    required this.selectedImage,
    required this.saving,
    required this.onPickImage,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = existingImageUrl?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppGradientInputFrame(
          child: TextField(
            controller: nameController,
            textInputAction: TextInputAction.next,
            scrollPadding: const EdgeInsets.only(bottom: 240),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              hintText: tr(context, ru: 'Название товара', zh: '商品名称'),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        AppGradientInputFrame(
          child: TextField(
            controller: quantityController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            scrollPadding: const EdgeInsets.only(bottom: 240),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              hintText: tr(context, ru: 'Количество', zh: '数量'),
              suffixText: 'шт',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: context.brandPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: saving ? null : onPickImage,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: selectedImage != null || imageUrl.isNotEmpty ? 128 : 52,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: context.brandPrimary.withValues(alpha: 0.18),
                ),
              ),
              child: selectedImage != null
                  ? (kIsWeb
                        ? FutureBuilder<Uint8List>(
                            future: selectedImage!.readAsBytes(),
                            builder: (_, snapshot) => snapshot.hasData
                                ? Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.cover,
                                  )
                                : const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                          )
                        : Image.file(
                            File(selectedImage!.path),
                            fit: BoxFit.cover,
                          ))
                  : imageUrl.isNotEmpty
                  ? AppCachedMediaImage(
                      url: imageUrl,
                      fit: BoxFit.cover,
                      thumbnailSize: 480,
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: context.brandPrimary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          tr(context, ru: 'Добавить фото товара', zh: '添加商品照片'),
                          style: TextStyle(
                            color: context.brandPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        if (selectedImage != null || imageUrl.isNotEmpty) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: saving ? null : onPickImage,
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: Text(tr(context, ru: 'Заменить фото', zh: '更换照片')),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TrackSheetSecondaryButton(
                label: tr(context, ru: 'Отмена', zh: '取消'),
                onTap: saving ? () {} : onCancel,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TrackSheetPrimaryButton(
                label: saving
                    ? tr(context, ru: 'Сохраняем…', zh: '正在保存…')
                    : tr(context, ru: 'Сохранить', zh: '保存'),
                icon: saving
                    ? Icons.hourglass_top_rounded
                    : Icons.check_rounded,
                onTap: saving ? null : onSave,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TrackProductPreview extends StatelessWidget {
  final String name;
  final int? quantity;
  final List<String> imageUrls;
  final String trackCode;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  const _TrackProductPreview({
    required this.name,
    required this.quantity,
    required this.imageUrls,
    required this.trackCode,
    this.onTap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrls.isNotEmpty;
    final title = name.trim().isNotEmpty ? name.trim() : 'О товаре';
    final countText = quantity != null ? 'Количество: $quantity шт' : null;

    return SizedBox(
      width: 124,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 124,
              height: 115,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFC4C4C4),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    offset: Offset(3, 4),
                    blurRadius: 25,
                  ),
                ],
              ),
              child: hasImage
                  ? AppCachedMediaImage(
                      url: imageUrls.first,
                      thumbnailSize: 480,
                      memCacheWidth: 220,
                      memCacheHeight: 220,
                      maxWidthDiskCache: 440,
                      maxHeightDiskCache: 440,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      useOldImageOnUrlChange: false,
                      filterQuality: FilterQuality.low,
                      imageBuilder: (context, imageProvider) => DecoratedBox(
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: imageProvider,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      placeholder: (_, _) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 24),
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.inventory_2_outlined,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEdit,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF2F2F2F),
                fontFamily: 'Gilroy',
                fontSize: 16,
                height: 19 / 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (countText != null)
            Text(
              countText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF2F2F2F),
                fontFamily: 'Gilroy',
                fontSize: 14,
                height: 16 / 14,
                fontWeight: FontWeight.w400,
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackPhotoGrid extends StatelessWidget {
  final List<String> mediaUrls;
  final TrackItem track;
  final ValueChanged<int> onTap;

  const _TrackPhotoGrid({
    required this.mediaUrls,
    required this.track,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visibleUrls = mediaUrls.take(6).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0.0, 246.0).toDouble()
            : 246.0;
        final tileSize = ((gridWidth - 20) / 3).clamp(54.0, 75.5).toDouble();
        return SizedBox(
          width: gridWidth,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < visibleUrls.length; i++)
                GestureDetector(
                  onTap: () => onTap(i),
                  child: Container(
                    width: tileSize,
                    height: tileSize,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC4C4C4),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          offset: Offset(3, 4),
                          blurRadius: 25,
                        ),
                      ],
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_isVideoUrl(ApiConfig.getMediaUrl(visibleUrls[i])))
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.black.withValues(alpha: 0.45),
                                  Colors.black.withValues(alpha: 0.18),
                                ],
                              ),
                            ),
                          )
                        else
                          AppCachedMediaImage(
                            url: visibleUrls[i],
                            thumbnailSize: 360,
                            memCacheWidth: 180,
                            memCacheHeight: 180,
                            maxWidthDiskCache: 360,
                            maxHeightDiskCache: 360,
                            imageBuilder: (context, imageProvider) =>
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    image: DecorationImage(
                                      image: imageProvider,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                            placeholder: (_, _) => const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            errorWidget: (_, _, _) => const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                        if (_isVideoUrl(ApiConfig.getMediaUrl(visibleUrls[i])))
                          Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DropdownItem<T> {
  final T value;
  final String label;

  const _DropdownItem({required this.value, required this.label});
}

/// Компактный dropdown-чип для фильтров в одну строку
class _MiniDropdown<T> extends StatelessWidget {
  final T value;
  final List<_DropdownItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _MiniDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = items.firstWhere(
      (i) => i.value == value,
      orElse: () => items.first,
    );
    return GestureDetector(
      onTap: () {
        showBlurredModalBottomSheet<T>(
          context: context,
          useRootNavigator: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                for (final item in items)
                  TrainingTarget(
                    id: item.value == ViewMode.groups
                        ? 'tracks.view.groups'
                        : 'tracks.view.option.${item.value}',
                    child: ListTile(
                      dense: true,
                      title: Text(
                        item.label,
                        style: TextStyle(
                          fontWeight: item.value == value
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: item.value == value
                              ? context.brandPrimary
                              : Colors.black87,
                          fontSize: 14,
                        ),
                      ),
                      trailing: item.value == value
                          ? Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: context.brandPrimary,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        onChanged(item.value);
                      },
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0x0A000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 16, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}

class _CustomDropdown<T> extends StatefulWidget {
  final T value;
  final String label;
  final List<_DropdownItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _CustomDropdown({
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
  });

  @override
  State<_CustomDropdown<T>> createState() => _CustomDropdownState<T>();
}

class _CustomDropdownState<T> extends State<_CustomDropdown<T>> {
  late T _selectedValue;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _targetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.value;
  }

  @override
  void didUpdateWidget(_CustomDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _selectedValue = widget.value;
    }
  }

  void _showMenu() {
    final targetContainer = ProviderScope.containerOf(context, listen: false);
    final renderBox =
        _targetKey.currentContext?.findRenderObject() as RenderBox?;
    final double menuWidth = renderBox?.size.width ?? 200;
    _overlayEntry = OverlayEntry(
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _hideMenu,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: const Offset(0, 50),
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: menuWidth,
                        constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.of(context).size.height *
                              0.4, // 40% of screen height
                        ),
                        decoration: const BoxDecoration(color: Colors.white),
                        child: ListView(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          children: widget.items.asMap().entries.map((entry) {
                            final index = entry.key;
                            final item = entry.value;
                            final isFirst = index == 0;
                            final isLast = index == widget.items.length - 1;

                            final option = InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedValue = item.value;
                                });
                                widget.onChanged(item.value);
                                _overlayEntry?.remove();
                                _overlayEntry = null;
                              },
                              // Добавляем borderRadius для InkWell эффекта
                              borderRadius: BorderRadius.vertical(
                                top: isFirst
                                    ? const Radius.circular(14)
                                    : Radius.zero,
                                bottom: isLast
                                    ? const Radius.circular(14)
                                    : Radius.zero,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _selectedValue == item.value
                                      ? context.brandPrimary.withValues(
                                          alpha: 0.1,
                                        )
                                      : Colors.transparent,
                                  // Добавляем borderRadius для первого/последнего элемента
                                  borderRadius: BorderRadius.vertical(
                                    top: isFirst
                                        ? const Radius.circular(14)
                                        : Radius.zero,
                                    bottom: isLast
                                        ? const Radius.circular(14)
                                        : Radius.zero,
                                  ),
                                ),
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: _selectedValue == item.value
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: _selectedValue == item.value
                                        ? context.brandPrimary
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            );
                            return item.value == ViewMode.groups
                                ? UncontrolledProviderScope(
                                    container: targetContainer,
                                    child: TrainingTarget(
                                      id: 'tracks.view.groups',
                                      child: option,
                                    ),
                                  )
                                : option;
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedLabel = widget.items
        .firstWhere(
          (item) => item.value == _selectedValue,
          orElse: () => _DropdownItem(value: _selectedValue, label: 'N/A'),
        )
        .label;

    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: () {
          if (_overlayEntry == null) {
            _showMenu();
          } else {
            _hideMenu();
          }
        },
        child: Container(
          key: _targetKey,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF999999),
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              Icon(
                _overlayEntry != null
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: context.brandPrimary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool isDestructive;

  const _ActionChipButton({
    this.icon,
    this.label,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = context.brandGradient;
    final destructiveGradient = const LinearGradient(
      colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
    );
    final activeGradient = isDestructive ? destructiveGradient : gradient;
    final activeColor = isDestructive
        ? const Color(0xFFD32F2F)
        : context.brandPrimary;
    final isDisabled = onPressed == null;

    // Icon-only button (circular) — fallback if no label
    if (label == null && icon != null) {
      return Opacity(
        opacity: isDisabled ? 0.45 : 1,
        child: Container(
          decoration: BoxDecoration(
            gradient: activeGradient,
            shape: BoxShape.circle,
          ),
          padding: const EdgeInsets.all(1.5),
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(icon, size: 18, color: activeColor),
              ),
            ),
          ),
        ),
      );
    }

    // Text-only or text+icon button — compact chip style
    return Opacity(
      opacity: isDisabled ? 0.45 : 1,
      child: Material(
        color: isDestructive
            ? const Color(0x14FF5252)
            : const Color(0x0A000000),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: activeColor.withOpacity(0.7)),
                  const SizedBox(width: 4),
                ],
                if (label != null)
                  Text(
                    label!,
                    style: TextStyle(
                      color: isDestructive ? activeColor : Colors.black54,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupBucket {
  final TrackAssembly? assembly;
  final List<TrackItem> tracks;

  _GroupBucket({required this.assembly, required this.tracks});

  DateTime get latestDate {
    var latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final t in tracks) {
      if (t.date.isAfter(latest)) latest = t.date;
    }
    return latest;
  }
}

Widget _outlinedInput(
  BuildContext context,
  TextEditingController controller, {
  String? hint,
  bool enabled = true,
  TextInputType? keyboardType,
  List<TextInputFormatter>? inputFormatters,
  ValueChanged<String>? onChanged,
  TextInputAction? textInputAction,
  int maxLines = 1,
}) {
  return AppGradientInputFrame(
    child: TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      textInputAction: textInputAction,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 14,
          color: Color(0xFF999999),
          fontWeight: FontWeight.w500,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    ),
  );
}

class _ProductInfo {
  final String name;
  final int? quantity;
  final List<String> images;

  _ProductInfo({
    required this.name,
    required this.quantity,
    required this.images,
  });
}

class _DeliveryOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  const _DeliveryOptionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;

    return Opacity(
      opacity: enabled ? 1 : 0.62,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? accent.withValues(alpha: 0.10)
                  : const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected
                    ? accent.withValues(alpha: 0.24)
                    : Colors.black.withValues(alpha: 0.045),
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.12),
                        blurRadius: 14,
                        spreadRadius: -8,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent.withValues(alpha: 0.14)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? accent : AppColors.textSecondary,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? accent : AppColors.textPrimary,
                          fontFamily: 'Gilroy',
                          fontSize: 15,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontFamily: 'Gilroy',
                          fontSize: 12.5,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isSelected ? accent : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? accent
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Определяет, является ли URL видео-файлом
bool _isVideoUrl(String url) {
  final lower = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.m4v') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.mov');
}

class _TrackInfoSectionsSurface extends StatelessWidget {
  final List<Widget> children;

  const _TrackInfoSectionsSurface({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Сворачиваемый блок «Заметка»
class _CollapsibleNote extends StatefulWidget {
  final String text;
  final VoidCallback? onEdit;

  const _CollapsibleNote({required this.text, this.onEdit});

  @override
  State<_CollapsibleNote> createState() => _CollapsibleNoteState();
}

class _CollapsibleNoteState extends State<_CollapsibleNote> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: accent.withValues(alpha: 0.14)),
                  ),
                  child: Icon(
                    Icons.sticky_note_2_rounded,
                    size: 18,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Заметка',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Gilroy',
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                          height: 1.05,
                          letterSpacing: -0.05,
                        ),
                      ),
                      if (!_expanded) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Gilroy',
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.onEdit != null) ...[
                  const SizedBox(width: 8),
                  _TrackTaskIconButton(
                    icon: Icons.edit_outlined,
                    color: accent,
                    onTap: widget.onEdit!,
                  ),
                ],
                const SizedBox(width: 6),
                _TrackTaskChevronButton(expanded: _expanded),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.035),
                        ),
                      ),
                      child: Text(
                        widget.text,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'Gilroy',
                          fontSize: 13.5,
                          height: 1.28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _TrackSpItemsBlock extends StatelessWidget {
  final List<TrackSpItem> items;

  const _TrackSpItemsBlock({required this.items});

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;
    final visibleItems = items.take(3).toList();
    final firstPurchase = items
        .map((item) => item.purchase?.title.trim())
        .whereType<String>()
        .where((title) => title.isNotEmpty)
        .firstOrNull;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.12)),
                ),
                child: Icon(Icons.groups_2_rounded, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstPurchase ?? 'Совместная покупка',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 14.5,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items.length == 1
                          ? 'Трек привязан к товару СП'
                          : 'Трек привязан к товарам СП: ${items.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontSize: 12.5,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < visibleItems.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _TrackSpItemRow(item: visibleItems[i]),
          ],
          if (items.length > visibleItems.length) ...[
            const SizedBox(height: 8),
            Text(
              '+ ещё ${items.length - visibleItems.length} товар(а)',
              style: TextStyle(
                color: accent,
                fontFamily: 'Gilroy',
                fontSize: 12.5,
                height: 1.1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrackSpItemRow extends StatelessWidget {
  final TrackSpItem item;

  const _TrackSpItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;
    final thumbnailUrl = item.media
        .map(
          (media) => (media.thumbnailUrl?.isNotEmpty == true)
              ? media.thumbnailUrl!
              : media.url,
        )
        .where((url) => url.trim().isNotEmpty)
        .firstOrNull;
    final customerName = item.customer?.fullName.trim();
    final priceLabel = _formatSpItemMoney(item);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TrackSpItemPreview(url: thumbnailUrl, trackTitle: item.title),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 13.5,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    if (customerName != null && customerName.isNotEmpty)
                      _TrackSpMiniPill(
                        icon: Icons.person_outline_rounded,
                        label: customerName,
                      ),
                    _TrackSpMiniPill(
                      icon: Icons.inventory_2_outlined,
                      label: '${item.quantity} шт',
                    ),
                    _TrackSpMiniPill(
                      icon: Icons.verified_outlined,
                      label: _spItemStatusLabel(item.status),
                    ),
                    if (priceLabel != null)
                      _TrackSpMiniPill(
                        icon: Icons.payments_outlined,
                        label: priceLabel,
                        highlighted: true,
                      ),
                  ],
                ),
                if ((item.linkComment ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    item.linkComment!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontFamily: 'Gilroy',
                      fontSize: 12,
                      height: 1.18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if ((item.sourceUrl ?? '').trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.link_rounded,
              color: accent.withValues(alpha: 0.72),
              size: 18,
            ),
          ],
        ],
      ),
    );
  }
}

class _TrackSpItemPreview extends StatelessWidget {
  final String? url;
  final String trackTitle;

  const _TrackSpItemPreview({this.url, required this.trackTitle});

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;
    final imageUrl = url?.trim();
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(Icons.shopping_bag_outlined, color: accent, size: 22),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final photo = PhotoItem(
          url: imageUrl,
          date: DateTime.now(),
          trackingNumber: trackTitle,
        );
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => PhotoViewerScreen(
              item: photo,
              allPhotos: [photo],
              initialIndex: 0,
            ),
          ),
        );
      },
      child: Container(
        width: 48,
        height: 48,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(15),
        ),
        child: AppCachedMediaImage(
          url: imageUrl,
          thumbnailSize: 240,
          memCacheWidth: 120,
          memCacheHeight: 120,
          maxWidthDiskCache: 240,
          maxHeightDiskCache: 240,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          filterQuality: FilterQuality.low,
          imageBuilder: (_, imageProvider) => DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
            ),
          ),
          placeholder: (_, _) => Center(
            child: Icon(Icons.shopping_bag_outlined, color: accent, size: 20),
          ),
          errorWidget: (_, _, _) => Center(
            child: Icon(Icons.broken_image_outlined, color: accent, size: 20),
          ),
        ),
      ),
    );
  }
}

class _TrackSpMiniPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;

  const _TrackSpMiniPill({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = context.brandPrimary;
    final color = highlighted ? accent : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted
            ? accent.withValues(alpha: 0.10)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? accent.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.035),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontFamily: 'Gilroy',
                fontSize: 11.5,
                height: 1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String? _formatSpItemMoney(TrackSpItem item) {
  final rubTotal =
      (item.clientPriceRub ?? 0) +
      (item.shippingCostRub ?? 0) +
      (item.additionalExpensesRub ?? 0);
  if (rubTotal > 0) {
    return '${_compactAmount(rubTotal)} ₽';
  }
  if ((item.clientPriceYuan ?? 0) > 0) {
    return '¥${_compactAmount(item.clientPriceYuan!)}';
  }
  return null;
}

String _compactAmount(double value) {
  final formatter = value % 1 == 0
      ? NumberFormat('#,##0', 'ru')
      : NumberFormat('#,##0.##', 'ru');
  return formatter.format(value);
}

String _spItemStatusLabel(String status) {
  switch (status) {
    case 'requested':
      return 'Запрошен';
    case 'need_info':
      return 'Нужны данные';
    case 'approved':
      return 'Подтверждён';
    case 'purchased':
      return 'Выкуплен';
    case 'not_purchased':
      return 'Не выкуплен';
    case 'cancelled':
      return 'Отменён';
    case 'in_transit':
      return 'В пути';
    case 'arrived':
      return 'Прибыл';
    case 'sorted':
      return 'Разобран';
    case 'ready_to_ship':
      return 'Готов к отправке';
    case 'sent_to_customer':
      return 'Отправлен клиенту';
    case 'delivered':
      return 'Доставлен';
    default:
      return status.isEmpty ? 'СП' : status;
  }
}

/// Инлайн блок «О товаре» — всегда развёрнут, под датой трека
class _ProductInfoInline extends StatelessWidget {
  final String name;
  final int? quantity;
  final List<String> imageUrls;
  final String trackCode;
  final VoidCallback? onEdit;

  const _ProductInfoInline({
    required this.name,
    this.quantity,
    required this.imageUrls,
    required this.trackCode,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final hasImages = imageUrls.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Название + количество + карандаш
        Row(
          children: [
            if (name.isNotEmpty)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onEdit,
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (quantity != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$quantity шт',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
            if (onEdit != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onEdit,
                child: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: Colors.black45,
                ),
              ),
            ],
          ],
        ),
        if (hasImages) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              final photo = PhotoItem(
                url: imageUrls.first,
                date: DateTime.now(),
                trackingNumber: trackCode,
              );
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => PhotoViewerScreen(
                    item: photo,
                    allPhotos: [photo],
                    initialIndex: 0,
                  ),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              height: 120,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: AppCachedMediaImage(
                url: imageUrls.first,
                thumbnailSize: 480,
                memCacheWidth: 320,
                memCacheHeight: 240,
                maxWidthDiskCache: 640,
                maxHeightDiskCache: 480,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                useOldImageOnUrlChange: false,
                filterQuality: FilterQuality.low,
                imageBuilder: (_, imageProvider) => DecoratedBox(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: imageProvider,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                placeholder: (_, _) => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                errorWidget: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 24),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Сворачиваемый блок вопроса по треку
class _CollapsibleQuestion extends StatefulWidget {
  final String title;
  final String statusLabel;
  final Color statusColor;
  final String question;
  final String? answer;
  final List<String> answerPhotoUrls;
  final String trackCode;
  final String createdAt;
  final String? answeredAt;
  final bool canCancel;
  final VoidCallback? onCancel;

  const _CollapsibleQuestion({
    required this.title,
    required this.statusLabel,
    required this.statusColor,
    required this.question,
    this.answer,
    this.answerPhotoUrls = const [],
    required this.trackCode,
    required this.createdAt,
    this.answeredAt,
    this.canCancel = false,
    this.onCancel,
  });

  @override
  State<_CollapsibleQuestion> createState() => _CollapsibleQuestionState();
}

class _CollapsibleQuestionState extends State<_CollapsibleQuestion>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.statusColor;
    final preview = widget.question.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _QuestionBadge(color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontFamily: 'Gilroy',
                                fontWeight: FontWeight.w900,
                                fontSize: 14.5,
                                height: 1.05,
                                letterSpacing: -0.05,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 116),
                            child: _TaskStatusBadge(
                              text: widget.statusLabel,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _QuestionMetaPill(
                            icon: CupertinoIcons.clock,
                            text: widget.createdAt,
                            color: AppColors.textSecondary,
                          ),
                          if (widget.answeredAt != null)
                            _QuestionMetaPill(
                              icon: CupertinoIcons.checkmark_alt_circle,
                              text: widget.answeredAt!,
                              color: const Color(0xFF27C47A),
                            ),
                        ],
                      ),
                      if (!_expanded && preview.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontFamily: 'Gilroy',
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                            height: 1.18,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.canCancel) ...[
                  const SizedBox(width: 8),
                  _TrackTaskIconButton(
                    icon: Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    onTap: widget.onCancel,
                  ),
                ],
                const SizedBox(width: 6),
                _TrackTaskChevronButton(expanded: _expanded),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.question.isNotEmpty)
                          _QuestionTextPanel(
                            title: 'Вопрос',
                            text: widget.question,
                          ),
                        if (widget.answer?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          _QuestionTextPanel(
                            title: 'Ответ склада',
                            text: widget.answer!.trim(),
                            muted: true,
                          ),
                        ],
                        if (widget.answerPhotoUrls.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _QuestionAnswerPhotoGrid(
                            urls: widget.answerPhotoUrls,
                            trackCode: widget.trackCode,
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

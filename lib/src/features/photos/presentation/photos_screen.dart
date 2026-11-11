import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../training/presentation/training_target.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_input_decoration.dart';
import '../../../core/ui/app_cached_media_image.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/scroll_to_top_button.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/tutorial_card.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/locale_text.dart';
import '../../clients/application/client_codes_controller.dart';
import '../data/photos_provider.dart';
import '../domain/photo_item.dart';
import 'photo_report_video_badge.dart';
import 'photo_date_sheet.dart';
import 'photo_viewer_screen.dart';

class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  final ScrollController _scrollController = ScrollController();
  PaginatedPhotosNotifier? _photosNotifier;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _search = '';
  DateTime? _date;

  final GlobalKey _statsKey = GlobalKey();
  final GlobalKey _photoGridKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _photosNotifier?.removeListener(_onPhotosChanged);
    super.dispose();
  }

  void _onPhotosChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent * 0.9) {
      if (_photosNotifier?.state.error == null) _photosNotifier?.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientCode = ref.watch(activeClientCodeProvider);
    if (clientCode == null) {
      return const EmptyState(
        icon: Icons.badge_outlined,
        title: 'Выберите код клиента',
        message:
            'Чтобы увидеть фотографии, сначала выберите или добавьте код клиента.',
      );
    }

    // Держим WebSocket-подписку для фонового обновления фото без перезагрузки экрана.
    ref.watch(photosRealtimeBridgeProvider);

    final newNotifier = ref.watch(
      filteredPhotosProvider((
        clientCode: clientCode,
        date: _date == null ? null : DateFormat('yyyy-MM-dd').format(_date!),
        search: _search,
      )),
    );
    if (_photosNotifier != newNotifier) {
      _photosNotifier?.removeListener(_onPhotosChanged);
      _photosNotifier = newNotifier;
      newNotifier.addListener(_onPhotosChanged);
    }
    final photosState = newNotifier.state;

    final bottomPad = AppLayout.bottomScrollPadding(context);
    final topPad = AppLayout.topBarTotalHeight(context);

    Future<void> onRefresh() async {
      await _photosNotifier?.loadInitial();
    }

    return TutorialScreenWrapper(
      screenKey: 'photos',
      steps: [
        TutorialStep(
          icon: Icons.photo_camera_rounded,
          title: 'Фотоотчёты',
          description:
              'Мы фотографируем ваши посылки на складе. Здесь хранятся все снимки и видео по вашим отправлениям.',
          targetKey: _statsKey,
        ),
        TutorialStep(
          icon: Icons.fullscreen_rounded,
          title: 'Просмотр фото',
          description:
              'Нажмите на любое фото для полноэкранного просмотра. Видеофайлы отмечены значком воспроизведения.',
          targetKey: _photoGridKey,
        ),
      ],
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: context.brandPrimary,
        // CustomScrollView + SliverGrid обеспечивают виртуализацию фото-грида:
        // только видимые ячейки держатся в дереве, остальные уничтожаются.
        // Ранее использовался ListView + shrinkWrap:true GridView, который рендерил
        // ВСЕ фото одновременно → OOM crash при большом количестве.
        child: Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, topPad * 0.7 + 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KeyedSubtree(
                          key: _statsKey,
                          child: const _PhotosHeaderSection(),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.045),
                            ),
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
                              Row(
                                children: [
                                  Expanded(
                                    child: AppOutlinedInputFrame(
                                      height: 48,
                                      radius: 16,
                                      fillColor: const Color(0xFFF8FAFC),
                                      borderColor: const Color(0xFFE3E7EE),
                                      builder: (context, focusNode) =>
                                          TextField(
                                            focusNode: focusNode,
                                            controller: _searchController,
                                            style: const TextStyle(
                                              fontFamily: 'Gilroy',
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: tr(
                                                context,
                                                ru: 'Поиск по трек-номеру',
                                                zh: '按运单号搜索',
                                              ),
                                              hintStyle: const TextStyle(
                                                fontFamily: 'Gilroy',
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.textSecondary,
                                              ),
                                              prefixIcon: focusNode.hasFocus
                                                  ? null
                                                  : Icon(
                                                      Icons.search_rounded,
                                                      color:
                                                          context.brandPrimary,
                                                      size: 22,
                                                    ),
                                              suffixIcon:
                                                  _searchController.text.isEmpty
                                                  ? null
                                                  : IconButton(
                                                      tooltip: tr(
                                                        context,
                                                        ru: 'Очистить поиск',
                                                        zh: '清除搜索',
                                                      ),
                                                      icon: const Icon(
                                                        Icons.close_rounded,
                                                        size: 20,
                                                        color: AppColors
                                                            .textSecondary,
                                                      ),
                                                      onPressed: () {
                                                        _searchDebounce
                                                            ?.cancel();
                                                        _searchController
                                                            .clear();
                                                        setState(
                                                          () => _search = '',
                                                        );
                                                      },
                                                    ),
                                              border: InputBorder.none,
                                              contentPadding:
                                                  EdgeInsets.fromLTRB(
                                                    focusNode.hasFocus ? 16 : 0,
                                                    14,
                                                    12,
                                                    14,
                                                  ),
                                              isDense: true,
                                            ),
                                            onChanged: (value) {
                                              setState(() {});
                                              _searchDebounce?.cancel();
                                              _searchDebounce = Timer(
                                                const Duration(
                                                  milliseconds: 350,
                                                ),
                                                () {
                                                  if (!mounted) return;
                                                  setState(
                                                    () =>
                                                        _search = value.trim(),
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: tr(
                                      context,
                                      ru: 'Выбрать дату',
                                      zh: '选择日期',
                                    ),
                                    child: Material(
                                      color: _date == null
                                          ? const Color(0xFFF8FAFC)
                                          : context.brandPrimary.withValues(
                                              alpha: 0.10,
                                            ),
                                      borderRadius: BorderRadius.circular(16),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () async {
                                          final date = await showPhotoDateSheet(
                                            context: context,
                                            initialDate:
                                                _date ?? DateTime.now(),
                                            firstDate: DateTime(2015),
                                            lastDate: DateTime.now(),
                                          );
                                          if (!mounted || date == null) return;
                                          setState(() => _date = date);
                                        },
                                        child: Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            border: Border.all(
                                              color: _date == null
                                                  ? Colors.black.withValues(
                                                      alpha: 0.035,
                                                    )
                                                  : context.brandPrimary
                                                        .withValues(
                                                          alpha: 0.18,
                                                        ),
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.calendar_month_rounded,
                                            size: 21,
                                            color: _date == null
                                                ? AppColors.textSecondary
                                                : context.brandPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_date != null) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: InputChip(
                                    label: Text(
                                      DateFormat('dd.MM.yyyy').format(_date!),
                                    ),
                                    avatar: Icon(
                                      Icons.calendar_month_rounded,
                                      size: 16,
                                      color: context.brandPrimary,
                                    ),
                                    deleteButtonTooltipMessage: tr(
                                      context,
                                      ru: 'Сбросить дату',
                                      zh: '清除日期',
                                    ),
                                    onDeleted: () =>
                                        setState(() => _date = null),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                ..._buildPhotosSlivers(
                  context,
                  photosState,
                  refreshFailed: newNotifier.failedInitialLoad,
                  onRetry: () => newNotifier.retryFailedLoad(),
                ),
                SliverToBoxAdapter(child: SizedBox(height: bottomPad + 16)),
              ],
            ),
            ScrollToTopButton(controller: _scrollController),
          ],
        ),
      ),
    );
  }

  /// Возвращает список slivers для секции фотографий.
  /// Использует SliverGrid вместо shrinkWrap GridView — обеспечивает
  /// виртуализацию: только видимые ячейки держатся в дереве.
  List<Widget> _buildPhotosSlivers(
    BuildContext context,
    PaginatedPhotosState state, {
    required VoidCallback onRetry,
    bool refreshFailed = false,
  }) {
    if (state.isLoading && state.photos.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _PhotosLoadingState(),
          ),
        ),
      ];
    }

    if (state.error != null && state.photos.isEmpty) {
      final errorInfo = ErrorUtils.getErrorInfo(state.error);
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _PhotosErrorState(
              message: errorInfo.message,
              onRetry: onRetry,
            ),
          ),
        ),
      ];
    }

    if (state.photos.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _PhotosEmptyState(),
          ),
        ),
      ];
    }

    final items = state.photos;
    final gallery = photoReportGallery(items);
    final groups = _groupPhotosByDate(items);
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    final crossAxisCount = availableWidth >= 620
        ? 4
        : availableWidth >= 500
        ? 3
        : 2;
    var globalIndex = 0;
    final slivers = <Widget>[];

    for (var groupIndex = 0; groupIndex < groups.length; groupIndex += 1) {
      final group = groups[groupIndex];
      final startIndex = globalIndex;
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, groupIndex == 0 ? 0 : 20, 16, 10),
            child: _PhotoDateDivider(
              date: group.date,
              count: group.photos.length,
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          key: groupIndex == 0 ? _photoGridKey : null,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = group.photos[index];
                return TrainingTarget(
                  id: startIndex + index == 0
                      ? 'photos.open'
                      : 'photos.open.${startIndex + index}',
                  child: _PhotoThumbnail(
                    item: item,
                    onOpenVideos: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (_) => PhotoViewerScreen(
                              item: item.reportVideos.first,
                              allPhotos: gallery,
                              initialIndex: photoReportGalleryIndex(
                                gallery,
                                item.reportVideos.first,
                              ),
                            ),
                          ),
                        ),
                    onOpen: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (_) => PhotoViewerScreen(
                              item: item,
                              allPhotos: gallery,
                              initialIndex: photoReportGalleryIndex(
                                gallery,
                                item,
                              ),
                            ),
                          ),
                        ),
                  ),
                );
              },
              childCount: group.photos.length,
              addAutomaticKeepAlives: false,
              addSemanticIndexes: false,
            ),
          ),
        ),
      );
      globalIndex += group.photos.length;
    }

    slivers.addAll([
      if (state.isLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      if (!state.isLoading && !state.hasMore && items.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _PhotosEndCard(count: items.length),
          ),
        ),
    ]);

    if (state.error != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _PhotosErrorState(
              message: tr(
                context,
                ru: refreshFailed
                    ? 'Не удалось обновить фотографии. Ранее загруженные снимки доступны.'
                    : 'Не удалось загрузить следующие фотографии. Уже загруженные снимки доступны.',
                zh: refreshFailed
                    ? '无法刷新照片，先前加载的照片仍然可用。'
                    : '无法加载更多照片，已加载的照片仍然可用。',
              ),
              onRetry: onRetry,
            ),
          ),
        ),
      );
    }
    return slivers;
  }

  List<_PhotoDateGroup> _groupPhotosByDate(List<PhotoItem> items) {
    final groups = <_PhotoDateGroup>[];
    for (final item in items) {
      final day = DateTime(item.date.year, item.date.month, item.date.day);
      if (groups.isEmpty || !_isSameDay(groups.last.date, day)) {
        groups.add(_PhotoDateGroup(date: day, photos: [item]));
      } else {
        groups.last.photos.add(item);
      }
    }
    return groups;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _PhotoDateGroup {
  final DateTime date;
  final List<PhotoItem> photos;

  _PhotoDateGroup({required this.date, required this.photos});
}

class _PhotoDateDivider extends StatelessWidget {
  final DateTime date;
  final int count;

  const _PhotoDateDivider({required this.date, required this.count});

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('d MMMM yyyy', 'ru').format(date);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.black.withValues(alpha: 0.045)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 16,
                spreadRadius: -8,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_rounded,
                size: 14,
                color: context.brandPrimary,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Gilroy',
                  fontSize: 13,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.05,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: context.brandPrimary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontFamily: 'Gilroy',
                    fontSize: 11.5,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: context.brandPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  context.brandPrimary.withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotosHeaderSection extends StatelessWidget {
  const _PhotosHeaderSection();

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
            const Positioned.fill(child: _PhotosHeaderGlowBackdrop()),
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
                      Icons.photo_library_rounded,
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
                          'Фотоотчёты',
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
                          'Снимки и видео со склада по вашим посылкам',
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

class _PhotosHeaderGlowBackdrop extends StatefulWidget {
  const _PhotosHeaderGlowBackdrop();

  @override
  State<_PhotosHeaderGlowBackdrop> createState() =>
      _PhotosHeaderGlowBackdropState();
}

class _PhotosHeaderGlowBackdropState extends State<_PhotosHeaderGlowBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat(reverse: true);
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
                    child: _PhotosHeaderGlowCircle(
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
                    child: _PhotosHeaderGlowCircle(
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
                    child: _PhotosHeaderGlowCircle(
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

class _PhotosHeaderGlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _PhotosHeaderGlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _PhotosLoadingState extends StatelessWidget {
  const _PhotosLoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.045)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            spreadRadius: -10,
            offset: const Offset(0, 10),
          ),
        ],
      ),
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
                  Icons.photo_camera_rounded,
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
                      'Загружаем фотоотчёты',
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
                      'Подготовим последние снимки со склада',
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
          Row(
            children: const [
              Expanded(child: _PhotoSkeletonTile()),
              SizedBox(width: 10),
              Expanded(child: _PhotoSkeletonTile()),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              Expanded(child: _PhotoSkeletonTile()),
              SizedBox(width: 10),
              Expanded(child: _PhotoSkeletonTile()),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoSkeletonTile extends StatelessWidget {
  const _PhotoSkeletonTile();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF1F3F7),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(context.brandPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotosErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _PhotosErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _PhotosStateCard(
      icon: Icons.cloud_off_rounded,
      title: 'Не удалось загрузить фото',
      message: message,
      iconColor: Colors.redAccent,
      actionLabel: 'Повторить',
      onAction: onRetry,
    );
  }
}

class _PhotosEmptyState extends StatelessWidget {
  const _PhotosEmptyState();

  @override
  Widget build(BuildContext context) {
    return const _PhotosStateCard(
      icon: Icons.photo_library_outlined,
      title: 'Фотоотчётов пока нет',
      message:
          'Когда склад загрузит снимки или видео по посылкам, они появятся здесь.',
    );
  }
}

class _PhotosStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color? iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _PhotosStateCard({
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.045)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            spreadRadius: -10,
            offset: const Offset(0, 10),
          ),
        ],
      ),
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

class _PhotosEndCard extends StatelessWidget {
  final int count;

  const _PhotosEndCard({required this.count});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all_rounded, color: context.brandPrimary, size: 16),
            const SizedBox(width: 7),
            Text(
              'Все материалы загружены ($count)',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumbnail extends StatelessWidget {
  final PhotoItem item;
  final VoidCallback onOpen;
  final VoidCallback onOpenVideos;

  const _PhotoThumbnail({
    required this.item,
    required this.onOpen,
    required this.onOpenVideos,
  });

  @override
  Widget build(BuildContext context) {
    final metaLabel = _metaLabel;

    return Semantics(
      button: true,
      label: item.isVideo ? 'Открыть видеоотчёт' : 'Открыть фотоотчёт',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.075),
                  blurRadius: 18,
                  spreadRadius: -10,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.isVideo)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            context.brandPrimary.withValues(alpha: 0.88),
                            Colors.black.withValues(alpha: 0.56),
                          ],
                        ),
                      ),
                    )
                  else
                    AppCachedMediaImage(
                      url: item.url,
                      thumbnailSize: 720,
                      memCacheWidth: 420,
                      memCacheHeight: 420,
                      maxWidthDiskCache: 720,
                      maxHeightDiskCache: 720,
                      fadeInDuration: const Duration(milliseconds: 120),
                      fadeOutDuration: Duration.zero,
                      useOldImageOnUrlChange: false,
                      filterQuality: FilterQuality.medium,
                      imageBuilder: (_, imageProvider) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: imageProvider,
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                      placeholder: (_, _) {
                        return Container(
                          color: const Color(0xFFF1F3F7),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  context.brandPrimary,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      errorWidget: (_, _, error) {
                        return Container(
                          color: const Color(0xFFF1F3F7),
                          child: Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.72,
                              ),
                              size: 28,
                            ),
                          ),
                        );
                      },
                    ),
                  if (!item.isVideo && metaLabel != null)
                    const Positioned.fill(child: _PhotoBottomGradient()),
                  if (item.isVideo)
                    Center(
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.36),
                          ),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  if (item.reportVideos.isNotEmpty)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: PhotoReportVideoBadge(
                        count: item.reportVideos.length,
                        onPressed: onOpenVideos,
                      ),
                    ),
                  if (metaLabel != null)
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.38),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          metaLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Gilroy',
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? get _metaLabel {
    final tracking = item.trackingNumber?.trim();
    if (tracking != null && tracking.isNotEmpty) return 'Трек $tracking';
    final assembly = item.assemblyNumber?.trim();
    if (assembly != null && assembly.isNotEmpty) return 'Сборка $assembly';
    return null;
  }
}

class _PhotoBottomGradient extends StatelessWidget {
  const _PhotoBottomGradient();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.42)],
          stops: const [0.45, 1],
        ),
      ),
    );
  }
}

import '../../../core/services/analytics_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/persistence/shared_preferences_provider.dart';
import '../../auth/data/auth_provider.dart';
import '../../../core/ui/app_input_decoration.dart';
import '../../../core/ui/sheet_handle.dart';
import '../../../core/ui/unsaved_changes_guard.dart';
import '../../../core/utils/locale_text.dart';
import '../../clients/application/client_codes_controller.dart';
import '../../add_tracks/data/add_tracks_repository.dart';
import '../../add_tracks/data/track_tracking_check_repository.dart';
import '../../add_tracks/domain/add_tracks_result.dart';
import '../data/tracks_provider.dart';
import '../../training/presentation/training_target.dart';

/// Модальное окно для добавления треков
Future<void> showAddTracksDialog(BuildContext context, WidgetRef ref) async {
  AnalyticsService.trackFunnel(WorkflowAction.trackAdd, WorkflowStage.viewed);
  return showBlurredModalBottomSheet(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.22),
    builder: (context) => _AddTracksDialog(),
  );
}

class _AddTracksDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AddTracksDialog> createState() => _AddTracksDialogState();
}

class _AddTracksDialogState extends ConsumerState<_AddTracksDialog> {
  final _ctrl = TextEditingController();
  final List<_UnconfirmedTrackDraft> _reviewDrafts = [];
  AddTracksResult? _result;
  String? _error;
  bool _submitting = false;
  int _addedTotal = 0;
  SharedPreferences? _draftPrefs;
  String? _draftKey;
  String? _draftClientCode;
  int? _draftClientId;
  Timer? _draftTimer;
  bool _draftCompleted = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    _draftClientCode = ref.read(activeClientCodeProvider);
    _draftClientId = auth.clientId;
    if (auth.clientId != null && _draftClientCode != null) {
      _draftKey =
          'track_input_draft:${Uri.encodeComponent(auth.userDomain ?? '')}:${auth.clientId}:${Uri.encodeComponent(_draftClientCode!)}';
      try {
        _draftPrefs = ref.read(sharedPreferencesProvider);
        _ctrl.text = _draftPrefs?.getString(_draftKey!) ?? '';
      } catch (_) {
        /* Closing is still guarded when storage is unavailable. */
      }
    }
    _ctrl.addListener(_scheduleDraft);
  }

  void _scheduleDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 300), _persistDraft);
  }

  void _persistDraft() {
    final key = _draftKey;
    final prefs = _draftPrefs;
    if (key == null || prefs == null) return;
    final text = _reviewDrafts.isNotEmpty
        ? _reviewTrackNumbers().join('\n')
        : _ctrl.text;
    final write = _draftCompleted || text.trim().isEmpty
        ? prefs.remove(key)
        : prefs.setString(key, text);
    unawaited(write.catchError((_) => false));
  }

  void _discardDraft() {
    _draftCompleted = true;
    _persistDraft();
  }

  final List<SkippedTrack> _skippedTotal = [];

  @override
  void dispose() {
    _draftTimer?.cancel();
    _persistDraft();
    _ctrl.removeListener(_scheduleDraft);
    _ctrl.dispose();
    for (final draft in _reviewDrafts) {
      draft.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!mounted) return;

    final clientCode = ref.read(activeClientCodeProvider);
    if (clientCode != _draftClientCode ||
        ref.read(authProvider).clientId != _draftClientId) {
      setState(
        () => _error = tr(
          context,
          ru: 'Аккаунт или код клиента изменился. Закройте форму и откройте её для нужного кода.',
          zh: '账号或客户代码已变更，请关闭表单并为正确的客户代码重新打开。',
        ),
      );
      return;
    }
    if (clientCode == null) {
      setState(() {
        _error = 'Выберите код клиента';
      });
      return;
    }

    final txt = _ctrl.text.trim();
    if (txt.isEmpty) {
      setState(() {
        _error = 'Введите трек-номера';
      });
      return;
    }

    final trackNumbers = _parseTrackNumbers(txt);
    if (trackNumbers.isEmpty) {
      setState(() => _error = 'Введите хотя бы один трек-номер');
      return;
    }

    _addedTotal = 0;
    _skippedTotal.clear();
    _result = null;
    await _checkAndAdd(clientCode, trackNumbers);
  }

  List<String> _parseTrackNumbers(String text) {
    return text
        .split(RegExp(r'[,\n;]'))
        .map((value) => value.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  List<String> _reviewTrackNumbers() {
    return _reviewDrafts
        .map((draft) => draft.controller.text.trim().toUpperCase())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _checkAndAdd(
    String clientCode,
    List<String> trackNumbers,
  ) async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final checkResult = await ref
          .read(trackTrackingCheckRepositoryProvider)
          .check(clientCode: clientCode, trackCodes: trackNumbers);
      if (!mounted) return;

      final trackable = checkResult.items
          .where((item) => item.status == TrackTrackingStatus.trackable)
          .map((item) => item.code)
          .toList();
      final existing = checkResult.items.where(
        (item) => item.status == TrackTrackingStatus.existing,
      );
      final unconfirmed = checkResult.items.where(
        (item) => item.status == TrackTrackingStatus.unconfirmed,
      );

      for (final item in existing) {
        _skippedTotal.add(
          SkippedTrack(
            code: item.code,
            reason: tr(context, ru: 'Уже существует в базе', zh: '已存在于系统中'),
          ),
        );
      }

      if (trackable.isNotEmpty) {
        await _addTracks(clientCode, trackable);
        if (!mounted) return;
      }

      _replaceReviewDrafts(
        unconfirmed
            .map(
              (item) => _UnconfirmedTrackDraft(
                code: item.code,
                reason: item.reason ?? TrackTrackingReason.checkUnavailable,
              ),
            )
            .toList(),
      );

      setState(() {
        _submitting = false;
        _result = AddTracksResult(
          added: _addedTotal,
          skipped: List.unmodifiable(_skippedTotal),
        );
        if (_addedTotal > 0) _ctrl.clear();
      });

      if (_reviewDrafts.isEmpty) {
        await _closeAfterSuccess();
      }
    } catch (error, stackTrace) {
      _handleError(error, stackTrace);
    }
  }

  Future<void> _addTracks(String clientCode, List<String> trackNumbers) async {
    final result = await ref
        .read(addTracksRepositoryProvider)
        .addTracks(clientCode: clientCode, trackCodes: trackNumbers);
    _addedTotal += result.added;
    _skippedTotal.addAll(result.skipped);
    if (result.added > 0) {
      ref.invalidate(paginatedTracksProvider(clientCode));
    }
  }

  Future<void> _recheckReview() async {
    final clientCode = ref.read(activeClientCodeProvider);
    if (clientCode == null) return;
    final trackNumbers = _reviewTrackNumbers();
    if (trackNumbers.isEmpty) {
      setState(
        () => _error = tr(
          context,
          ru: 'Оставьте хотя бы один трек-номер или закройте окно',
          zh: '请至少保留一个运单号，或关闭窗口',
        ),
      );
      return;
    }
    await _checkAndAdd(clientCode, trackNumbers);
  }

  Future<void> _confirmReview() async {
    final clientCode = ref.read(activeClientCodeProvider);
    if (clientCode == null) return;
    final trackNumbers = _reviewTrackNumbers();
    if (trackNumbers.isEmpty) {
      setState(
        () => _error = tr(
          context,
          ru: 'Нет трек-номеров для добавления',
          zh: '没有可添加的运单号',
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _addTracks(clientCode, trackNumbers);
      if (!mounted) return;
      _replaceReviewDrafts(const []);
      setState(() {
        _submitting = false;
        _result = AddTracksResult(
          added: _addedTotal,
          skipped: List.unmodifiable(_skippedTotal),
        );
      });
      await _closeAfterSuccess();
    } catch (error, stackTrace) {
      _handleError(error, stackTrace);
    }
  }

  void _replaceReviewDrafts(List<_UnconfirmedTrackDraft> drafts) {
    for (final draft in _reviewDrafts) {
      draft.controller.dispose();
    }
    _reviewDrafts
      ..clear()
      ..addAll(drafts);
    for (final draft in _reviewDrafts) {
      draft.controller.addListener(_scheduleDraft);
    }
    _scheduleDraft();
  }

  void _removeReviewDraft(int index) {
    setState(() {
      _reviewDrafts.removeAt(index).controller.dispose();
      _error = null;
    });
  }

  Future<void> _closeAfterSuccess() async {
    if (_addedTotal <= 0 || !mounted) return;
    _draftCompleted = true;
    _persistDraft();
    final route = ModalRoute.of(context);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted && route != null && route.isCurrent) {
      Navigator.of(context).pop();
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    debugPrint('❌ Error adding tracks from dialog: $error');
    debugPrint('Stack trace: $stackTrace');
    if (!mounted) return;

    final errorMessage = error.toString().replaceFirst('Exception: ', '');
    setState(() {
      _submitting = false;
      _error = errorMessage;
    });
    AppToast.showFromSnackBar(
      context,
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${tr(context, ru: 'Ошибка', zh: '错误')}: $errorMessage',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: _ctrl,
        builder: (_, value, _) => UnsavedChangesGuard(
          hasChanges: value.text.trim().isNotEmpty || _reviewDrafts.isNotEmpty,
          isBusy: _submitting,
          onDiscard: _discardDraft,
          child: _buildContent(context),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Error building AddTracksDialog: $e');
      debugPrint('Stack trace: $stackTrace');

      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'Ошибка загрузки',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Произошла ошибка при загрузке формы добавления треков.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF666666), fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    final clientCode = ref.watch(activeClientCodeProvider);
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final bottomPadding = mediaQuery.padding.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.9),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          const Center(
            child: TrainingTarget(
              id: 'track.sheet.dismiss-handle',
              child: SizedBox(width: 42, child: SheetHandle()),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 18 + bottomPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AddTracksHeader(
                    clientCode: clientCode,
                    onClose: _submitting
                        ? null
                        : () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: 14),
                  if (clientCode != null) ...[
                    if (_reviewDrafts.isEmpty) const _AddTracksHintCard(),
                    const SizedBox(height: 12),
                    if (_reviewDrafts.isEmpty)
                      TrainingTarget(
                        id: 'tracks.add.form',
                        child: _AddTracksInputCard(
                          controller: _ctrl,
                          enabled: !_submitting,
                          onChanged: () {
                            if (_error != null || _result != null) {
                              setState(() {
                                _error = null;
                                _result = null;
                              });
                            }
                          },
                        ),
                      )
                    else
                      _UnconfirmedTracksCard(
                        drafts: _reviewDrafts,
                        enabled: !_submitting,
                        addedCount: _addedTotal,
                        onRemove: _removeReviewDraft,
                      ),
                    if (_result != null) ...[
                      const SizedBox(height: 12),
                      _AddTracksResultCard(result: _result!),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _AddTracksFeedbackCard(
                        icon: Icons.error_outline_rounded,
                        title: 'Не удалось добавить',
                        message: _error!,
                        color: Colors.redAccent,
                      ),
                    ],
                    const SizedBox(height: 14),
                    _AddTracksPrimaryButton(
                      loading: _submitting,
                      onTap: _submitting
                          ? null
                          : _reviewDrafts.isEmpty
                          ? _submit
                          : _recheckReview,
                      icon: _reviewDrafts.isEmpty
                          ? Icons.fact_check_rounded
                          : Icons.refresh_rounded,
                      label: _reviewDrafts.isEmpty
                          ? tr(context, ru: 'Проверить и добавить', zh: '检查并添加')
                          : tr(
                              context,
                              ru: 'Проверить исправления',
                              zh: '检查修改',
                            ),
                    ),
                    if (_reviewDrafts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _AddTracksSecondaryButton(
                        enabled: !_submitting,
                        onTap: _confirmReview,
                      ),
                    ],
                  ] else ...[
                    const _AddTracksFeedbackCard(
                      icon: Icons.badge_outlined,
                      title: 'Код клиента не выбран',
                      message: 'Сначала выберите код клиента в верхнем меню.',
                      color: AppColors.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTracksHeader extends StatelessWidget {
  final String? clientCode;
  final VoidCallback? onClose;

  const _AddTracksHeader({required this.clientCode, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: context.brandPrimary.withValues(alpha: 0.18),
            blurRadius: 22,
            spreadRadius: -12,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, ru: 'Добавить треки', zh: '添加运单号'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Gilroy',
                    fontSize: 21,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  tr(
                    context,
                    ru: 'Проверим отслеживание перед добавлением',
                    zh: '添加前先检查物流信息',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xE6FFFFFF),
                    fontFamily: 'Gilroy',
                    fontSize: 12.8,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (clientCode != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.badge_outlined,
                          color: Colors.white,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Код $clientCode',
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Gilroy',
                            fontSize: 12.5,
                            height: 1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: tr(context, ru: 'Закрыть', zh: '关闭'),
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _AddTracksHintCard extends StatelessWidget {
  const _AddTracksHintCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: context.brandPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.content_paste_rounded,
              color: context.brandPrimary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, ru: 'Как вставлять номера', zh: '如何填写运单号'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 14,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  tr(
                    context,
                    ru: 'До 50 номеров: по одному в строке или через запятую. Перед добавлением проверим историю доставки.',
                    zh: '最多50个：每行一个或用逗号分隔。添加前会检查物流记录。',
                  ),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
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

class _AddTracksInputCard extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  const _AddTracksInputCard({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppOutlinedInputFrame(
      radius: 18,
      fillColor: const Color(0xFFF8FAFC),
      borderColor: const Color(0xFFE3E7EE),
      enabled: enabled,
      builder: (context, focusNode) => TextField(
        focusNode: focusNode,
        controller: controller,
        maxLines: 8,
        enabled: enabled,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          height: 1.35,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          hintText: 'ABC123456789\nDEF987654321\n...',
          hintStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.35,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Icon(
              Icons.local_shipping_rounded,
              color: context.brandPrimary,
              size: 22,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 44,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(0, 14, 14, 14),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _UnconfirmedTrackDraft {
  final TextEditingController controller;
  final TrackTrackingReason reason;

  _UnconfirmedTrackDraft({required String code, required this.reason})
    : controller = TextEditingController(text: code);
}

class _UnconfirmedTracksCard extends StatelessWidget {
  final List<_UnconfirmedTrackDraft> drafts;
  final bool enabled;
  final int addedCount;
  final ValueChanged<int> onRemove;

  const _UnconfirmedTracksCard({
    required this.drafts,
    required this.enabled,
    required this.addedCount,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF3C760)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.manage_search_rounded,
                color: Color(0xFFC98700),
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        context,
                        ru: 'Проверьте эти трек-номера',
                        zh: '请检查这些运单号',
                      ),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 15,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr(
                        context,
                        ru: 'Сервис пока не видит историю доставки. Исправьте номер и проверьте снова. Если номер новый и ещё не появился у перевозчика, добавьте его без проверки.',
                        zh: '服务暂未查到物流记录。请修改后重新检查；如果运单号刚创建、承运商尚未收录，也可以确认后直接添加。',
                      ),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (addedCount > 0) ...[
                      const SizedBox(height: 7),
                      Text(
                        tr(
                          context,
                          ru: 'Уже добавлено автоматически: $addedCount',
                          zh: '已自动添加：$addedCount',
                        ),
                        style: TextStyle(
                          color: context.brandPrimary,
                          fontFamily: 'Gilroy',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < drafts.length; index++) ...[
            _UnconfirmedTrackField(
              key: ValueKey('unconfirmed-track-$index'),
              controller: drafts[index].controller,
              reason: drafts[index].reason,
              enabled: enabled,
              onRemove: () => onRemove(index),
            ),
            if (index != drafts.length - 1) const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}

class _UnconfirmedTrackField extends StatelessWidget {
  final TextEditingController controller;
  final TrackTrackingReason reason;
  final bool enabled;
  final VoidCallback onRemove;

  const _UnconfirmedTrackField({
    super.key,
    required this.controller,
    required this.reason,
    required this.enabled,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final reasonText = switch (reason) {
      TrackTrackingReason.noTrackingData => tr(
        context,
        ru: 'История доставки пока не найдена',
        zh: '暂未找到物流记录',
      ),
      TrackTrackingReason.carrierNotRecognized => tr(
        context,
        ru: 'Служба доставки не определена',
        zh: '无法识别承运商',
      ),
      TrackTrackingReason.checkUnavailable => tr(
        context,
        ru: 'Не удалось проверить сейчас',
        zh: '暂时无法检查',
      ),
      TrackTrackingReason.alreadyExists => tr(
        context,
        ru: 'Уже существует в базе',
        zh: '已存在于系统中',
      ),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE7D39B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
              IconButton(
                tooltip: tr(context, ru: 'Убрать номер', zh: '移除运单号'),
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppColors.textSecondary,
              ),
            ],
          ),
          Text(
            reasonText,
            style: const TextStyle(
              color: Color(0xFF9C6A00),
              fontFamily: 'Gilroy',
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTracksResultCard extends StatelessWidget {
  final AddTracksResult result;

  const _AddTracksResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final success = result.added > 0;
    final color = success ? const Color(0xFF27C47A) : Colors.orangeAccent;

    return _AddTracksFeedbackCard(
      icon: success ? Icons.check_circle_rounded : Icons.warning_rounded,
      title: success ? 'Добавлено: ${result.added}' : 'Ничего не добавлено',
      message: _message,
      color: color,
    );
  }

  String get _message {
    if (result.skipped.isEmpty) return 'Список треков обновится автоматически.';
    final skippedPreview = result.skipped
        .take(3)
        .map((item) => '${item.code}: ${item.reason}')
        .join('\n');
    final tail = result.skipped.length > 3
        ? '\n... ещё ${result.skipped.length - 3}'
        : '';
    return 'Пропущено: ${result.skipped.length}\n$skippedPreview$tail';
  }
}

class _AddTracksFeedbackCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  const _AddTracksFeedbackCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = color.computeLuminance() > 0.58
        ? AppColors.textPrimary
        : color;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontFamily: 'Gilroy',
                    fontSize: 14,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontFamily: 'Gilroy',
                    fontSize: 12.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
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

class _AddTracksPrimaryButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  final IconData icon;
  final String label;

  const _AddTracksPrimaryButton({
    required this.loading,
    required this.onTap,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            gradient: onTap == null ? null : context.brandGradient,
            color: onTap == null ? const Color(0xFFE5E7EB) : null,
            borderRadius: BorderRadius.circular(18),
            boxShadow: onTap == null
                ? null
                : [
                    BoxShadow(
                      color: context.brandPrimary.withValues(alpha: 0.20),
                      blurRadius: 16,
                      spreadRadius: -9,
                      offset: const Offset(0, 9),
                    ),
                  ],
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: Colors.white, size: 21),
                      const SizedBox(width: 7),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Gilroy',
                          fontSize: 15,
                          height: 1,
                          fontWeight: FontWeight.w900,
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

class _AddTracksSecondaryButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _AddTracksSecondaryButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
        label: Text(
          tr(context, ru: 'Всё указано верно — добавить', zh: '信息无误，直接添加'),
          style: const TextStyle(
            fontFamily: 'Gilroy',
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.brandPrimary,
          side: BorderSide(color: context.brandPrimary.withValues(alpha: 0.42)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

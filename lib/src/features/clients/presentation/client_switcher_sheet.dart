import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/animated_hero_glow_backdrop.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/sheet_handle.dart';
import '../../../core/utils/locale_text.dart';
import '../../../core/utils/error_utils.dart';
import '../../assemblies/data/assemblies_provider.dart';
import '../../invoices/data/invoices_provider.dart';
import '../../tracks/data/tracks_provider.dart';
import '../application/client_codes_controller.dart';

class ClientSwitcherSheet extends ConsumerStatefulWidget {
  const ClientSwitcherSheet({super.key});

  @override
  ConsumerState<ClientSwitcherSheet> createState() =>
      _ClientSwitcherSheetState();
}

class _ClientSwitcherSheetState extends ConsumerState<ClientSwitcherSheet> {
  String? _selectingCode;

  Future<void> _selectCode(String code, bool selected) async {
    if (_selectingCode != null) return;
    if (selected) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _selectingCode = code);
    try {
      await ref.read(clientCodesControllerProvider.notifier).selectClient(code);
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _selectingCode = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(clientCodesControllerProvider);
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 34,
            spreadRadius: -12,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: asyncState.when(
          loading: () => _ClientSwitcherLoading(bottomSafe: bottomSafe),
          error: (e, _) {
            final errorInfo = ErrorUtils.getErrorInfo(e);
            return Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottomSafe),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SheetHandle(),
                  const SizedBox(height: 12),
                  EmptyState(
                    icon: errorInfo.icon,
                    title: errorInfo.title,
                    message: errorInfo.message,
                    actionLabel: tr(context, ru: 'Повторить', zh: '重试'),
                    onAction: () =>
                        ref.invalidate(clientCodesControllerProvider),
                  ),
                ],
              ),
            );
          },
          data: (state) {
            final activeCode = state.activeCode;
            final codes = state.codes;

            return GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  const SheetHandle(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: _ClientCodeSheetHeader(
                      activeCode: activeCode,
                      codesCount: codes.length,
                    ),
                  ),
                  if (codes.isEmpty)
                    Flexible(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          14,
                          16,
                          24 + bottomSafe,
                        ),
                        child: const _ClientCodeEmptyCard(),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 14),
                    Flexible(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          24 + bottomSafe,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final code in codes) ...[
                              _ClientCodeOptionCard(
                                code: code,
                                selected: code == activeCode,
                                loading: _selectingCode == code,
                                disabled: _selectingCode != null,
                                onTap: () =>
                                    _selectCode(code, code == activeCode),
                              ),
                              if (code != codes.last) const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ClientSwitcherLoading extends StatelessWidget {
  final double bottomSafe;

  const _ClientSwitcherLoading({required this.bottomSafe});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 28 + bottomSafe),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHandle(),
          SizedBox(height: 28),
          CircularProgressIndicator(),
          SizedBox(height: 18),
          Text(
            'Загружаем коды клиента…',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientCodeSheetHeader extends StatelessWidget {
  final String? activeCode;
  final int codesCount;

  const _ClientCodeSheetHeader({
    required this.activeCode,
    required this.codesCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: context.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: context.brandPrimary.withValues(alpha: 0.22),
            blurRadius: 24,
            spreadRadius: -10,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            const Positioned.fill(child: AnimatedHeroGlowBackdrop()),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                        ),
                        child: const Icon(
                          Icons.badge_rounded,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Код клиента',
                              style: TextStyle(
                                color: Colors.white,
                                fontFamily: 'Gilroy',
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                height: 1.06,
                                letterSpacing: -0.35,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Выберите аккаунт для работы в кабинете',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(0xE6FFFFFF),
                                fontFamily: 'Gilroy',
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _HeaderPill(
                        icon: Icons.check_circle_rounded,
                        label: activeCode == null
                            ? 'Не выбран'
                            : 'Активен $activeCode',
                      ),
                      _HeaderPill(
                        icon: Icons.layers_rounded,
                        label: '$codesCount ${_codesWord(codesCount)}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _codesWord(int value) {
    final mod10 = value % 10;
    final mod100 = value % 100;
    if (mod10 == 1 && mod100 != 11) return 'код';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'кода';
    }
    return 'кодов';
  }
}

class _HeaderPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeaderPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Gilroy',
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientCodeOptionCard extends ConsumerWidget {
  final String code;
  final bool selected;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  const _ClientCodeOptionCard({
    required this.code,
    required this.selected,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksCountAsync = ref.watch(tracksCountProvider(code));
    final assembliesCountAsync = ref.watch(assembliesCountProvider(code));
    final invoicesCountAsync = ref.watch(invoicesCountProvider(code));

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: disabled && !loading ? 0.56 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? context.brandPrimary.withValues(alpha: 0.42)
                    : Colors.black.withValues(alpha: 0.045),
                width: selected ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: selected
                      ? context.brandPrimary.withValues(alpha: 0.14)
                      : Colors.black.withValues(alpha: 0.045),
                  blurRadius: selected ? 22 : 16,
                  spreadRadius: -8,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: selected ? context.brandGradient : null,
                        color: selected
                            ? null
                            : context.brandPrimary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Center(
                        child: loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                selected
                                    ? Icons.check_rounded
                                    : Icons.badge_outlined,
                                color: selected
                                    ? Colors.white
                                    : context.brandPrimary,
                                size: selected ? 23 : 21,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontFamily: 'Gilroy',
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              height: 1.05,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            selected
                                ? 'Сейчас используется'
                                : 'Переключиться на код',
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
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (selected)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: context.brandPrimary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Активен',
                          style: TextStyle(
                            color: context.brandPrimary,
                            fontFamily: 'Gilroy',
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            height: 1,
                          ),
                        ),
                      )
                    else
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondary.withValues(alpha: 0.72),
                        size: 24,
                      ),
                  ],
                ),
                const SizedBox(height: 11),
                _ClientCodeStatsRow(
                  selected: selected,
                  tracksCountAsync: tracksCountAsync,
                  assembliesCountAsync: assembliesCountAsync,
                  invoicesCountAsync: invoicesCountAsync,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientCodeStatsRow extends StatelessWidget {
  final bool selected;
  final AsyncValue<int> tracksCountAsync;
  final AsyncValue<int> assembliesCountAsync;
  final AsyncValue<int> invoicesCountAsync;

  const _ClientCodeStatsRow({
    required this.selected,
    required this.tracksCountAsync,
    required this.assembliesCountAsync,
    required this.invoicesCountAsync,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ClientCodeStatChip(
            icon: Icons.local_shipping_rounded,
            label: 'Треки',
            value: _formatAsyncCount(tracksCountAsync),
            selected: selected,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: _ClientCodeStatChip(
            icon: Icons.inventory_2_rounded,
            label: 'Сборки',
            value: _formatAsyncCount(assembliesCountAsync),
            selected: selected,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: _ClientCodeStatChip(
            icon: Icons.receipt_long_rounded,
            label: 'Счета',
            value: _formatAsyncCount(invoicesCountAsync),
            selected: selected,
          ),
        ),
      ],
    );
  }

  static String _formatAsyncCount(AsyncValue<int> value) {
    return value.when(
      data: _compactCount,
      loading: () => '…',
      error: (error, stackTrace) => '—',
    );
  }

  static String _compactCount(int value) {
    if (value >= 1000000) {
      final formatted = (value / 1000000).toStringAsFixed(1);
      return '${formatted.replaceAll('.0', '')}м';
    }
    if (value >= 1000) {
      final formatted = (value / 1000).toStringAsFixed(1);
      return '${formatted.replaceAll('.0', '')}к';
    }
    return value.toString();
  }
}

class _ClientCodeStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool selected;

  const _ClientCodeStatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = selected
        ? context.brandPrimary
        : AppColors.textSecondary.withValues(alpha: 0.82);

    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      decoration: BoxDecoration(
        color: selected
            ? context.brandPrimary.withValues(alpha: 0.08)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: selected
              ? context.brandPrimary.withValues(alpha: 0.13)
              : Colors.black.withValues(alpha: 0.035),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accentColor, size: 13),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accentColor,
                fontFamily: 'Gilroy',
                fontWeight: FontWeight.w800,
                fontSize: 10.5,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontWeight: FontWeight.w900,
              fontSize: 12,
              height: 1,
              letterSpacing: -0.05,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientCodeEmptyCard extends StatelessWidget {
  const _ClientCodeEmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.045)),
      ),
      child: const Column(
        children: [
          Icon(Icons.badge_outlined, color: AppColors.textSecondary, size: 34),
          SizedBox(height: 10),
          Text(
            'Коды клиента пока не найдены',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'После привязки кода он появится в этом списке.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontFamily: 'Gilroy',
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

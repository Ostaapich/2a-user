import 'package:flutter/material.dart';

import '../utils/locale_text.dart';

Future<bool> confirmDiscardChanges(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            tr(context, ru: 'Не сохранять изменения?', zh: '放弃未保存的更改？'),
          ),
          content: Text(
            tr(
              context,
              ru: 'Введённые данные будут потеряны. Можно вернуться к редактированию.',
              zh: '填写的内容将丢失。您可以返回继续编辑。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                tr(context, ru: 'Продолжить редактирование', zh: '继续编辑'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr(context, ru: 'Не сохранять', zh: '放弃更改')),
            ),
          ],
        ),
      ) ??
      false;
}

/// Guards back/maybePop. Explicit cancel/X handlers must use maybePop or call
/// [confirmDiscardChanges]; successful saves may still pop the route directly.
/// Form sheets should additionally disable drag/barrier dismissal.
class UnsavedChangesGuard extends StatefulWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.hasChanges,
    this.isBusy = false,
    this.onDiscard,
    required this.child,
  });

  final bool hasChanges;
  final bool isBusy;
  final VoidCallback? onDiscard;
  final Widget child;

  @override
  State<UnsavedChangesGuard> createState() => _UnsavedChangesGuardState();
}

class _UnsavedChangesGuardState extends State<UnsavedChangesGuard> {
  bool _confirming = false;

  Future<void> _onPop(bool didPop, Object? result) async {
    if (didPop || widget.isBusy || _confirming) return;
    _confirming = true;
    final discard = !widget.hasChanges || await confirmDiscardChanges(context);
    if (!mounted) return;
    _confirming = false;
    if (discard && !widget.isBusy) {
      if (widget.hasChanges) widget.onDiscard?.call();
      if (!mounted) return;
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !widget.hasChanges && !widget.isBusy,
    onPopInvokedWithResult: _onPop,
    child: widget.child,
  );
}

/// Captures the form values on first display and observes text edits.
class UnsavedFormGuard extends StatefulWidget {
  const UnsavedFormGuard({
    super.key,
    required this.controllers,
    this.extraState = '',
    this.isBusy = false,
    required this.child,
  });
  final List<TextEditingController> controllers;
  final String extraState;
  final bool isBusy;
  final Widget child;
  @override
  State<UnsavedFormGuard> createState() => _UnsavedFormGuardState();
}

class _UnsavedFormGuardState extends State<UnsavedFormGuard> {
  late final String _initialExtra = widget.extraState;
  final _initial = <TextEditingController, String>{};
  @override
  Widget build(BuildContext context) {
    for (final controller in widget.controllers) {
      _initial.putIfAbsent(controller, () => controller.text);
    }
    return ListenableBuilder(
      listenable: Listenable.merge(widget.controllers),
      builder: (context, _) => UnsavedChangesGuard(
        hasChanges:
            widget.extraState != _initialExtra ||
            widget.controllers.any((c) => c.text != _initial[c]),
        isBusy: widget.isBusy,
        child: widget.child,
      ),
    );
  }
}

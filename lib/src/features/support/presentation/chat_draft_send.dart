import 'package:flutter/widgets.dart';

/// Keeps the submitted composer snapshot separate from edits made while sending.
Future<bool> sendChatDraft({
  required TextEditingController controller,
  required String text,
  required Future<bool> Function() send,
  required bool Function() isMounted,
}) async {
  final originalDraft = controller.text;
  final matchesComposer = originalDraft.trim() == text.trim();
  final success = await send();
  if (success &&
      isMounted() &&
      matchesComposer &&
      controller.text == originalDraft) {
    controller.clear();
  }
  return success;
}

/// Ephemeral assistant activity; it is never a chat message or saved history.
class SupportAiActivity {
  const SupportAiActivity({
    this.conversationId,
    required this.isTyping,
    this.messageId,
    this.expiresAt,
  });

  final int? conversationId;
  final bool isTyping;
  final int? messageId;
  final DateTime? expiresAt;

  static SupportAiActivity? fromJson(Object? value) {
    if (value is! Map) return null;
    final conversation = value['conversationId'];
    final typing = value['isTyping'];
    final message = value['messageId'];
    final expiry = value['expiresAt'];
    if (typing is! bool ||
        (conversation != null && (conversation is! int || conversation <= 0)) ||
        (message != null && (message is! int || message <= 0))) {
      return null;
    }
    final date = expiry is String ? DateTime.tryParse(expiry) : null;
    if (typing && (conversation == null || message == null || date == null)) {
      return null;
    }
    return SupportAiActivity(
      conversationId: conversation as int?,
      isTyping: typing,
      messageId: message as int?,
      expiresAt: date,
    );
  }
}

/// Monotonic request IDs prevent old events/responses from reviving a reply.
class SupportAiActivityTracker {
  SupportAiActivity? activity;
  int _closedThrough = 0;
  int _latestRequest = 0;

  bool isTyping(DateTime now) =>
      activity?.isTyping == true && activity!.expiresAt!.isAfter(now);

  void apply(SupportAiActivity update, int conversationId, DateTime now) {
    if (update.conversationId != conversationId &&
        !(update.conversationId == null && !update.isTyping)) {
      return;
    }
    final request = update.messageId;
    if (request != null && request < _latestRequest) return;
    if (!update.isTyping) {
      _close(request ?? activity?.messageId ?? 0);
      return;
    }
    if (request == null ||
        request <= _closedThrough ||
        !update.expiresAt!.isAfter(now) ||
        update.expiresAt!.difference(now) > const Duration(minutes: 6)) {
      return;
    }
    _latestRequest = request;
    activity = update;
  }

  void observeReply({
    required int messageId,
    int? replyToMessageId,
    required bool isHuman,
  }) {
    final request = isHuman ? messageId - 1 : replyToMessageId;
    if (request == null) return;
    if (request > _closedThrough) _closedThrough = request;
    if ((activity?.messageId ?? 0) <= _closedThrough) activity = null;
  }

  void _close(int request) {
    if (request > _closedThrough) _closedThrough = request;
    if ((activity?.messageId ?? 0) <= request) activity = null;
  }

  /// Leaving a tab is not a completion; a canonical refresh may restore it.
  void hide() => activity = null;
}

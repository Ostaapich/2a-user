import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/support/data/support_ai_activity.dart';

void main() {
  final now = DateTime.utc(2026, 11, 19, 12);
  Map<String, dynamic> active(int id, {int conversation = 7}) => {
    'conversationId': conversation,
    'isTyping': true,
    'messageId': id,
    'expiresAt': now.add(const Duration(seconds: 50)).toIso8601String(),
  };
  test(
    'activity requires exact types, a positive message and a bounded future expiry',
    () {
      expect(SupportAiActivity.fromJson(active(10))?.messageId, 10);
      for (final bad in [
        {...active(10), 'isTyping': 'true'},
        {...active(10), 'messageId': 0},
        {...active(10), 'expiresAt': 'bad'},
        {...active(10), 'conversationId': -1},
      ]) {
        expect(SupportAiActivity.fromJson(bad), isNull);
      }
    },
  );
  test('another chat and an expired event cannot activate typing', () {
    final state = SupportAiActivityTracker();
    state.apply(
      SupportAiActivity.fromJson(active(10, conversation: 8))!,
      7,
      now,
    );
    expect(state.isTyping(now), false);
    state.apply(
      SupportAiActivity.fromJson(active(10))!,
      7,
      now.add(const Duration(minutes: 1)),
    );
    expect(state.isTyping(now), false);
  });
  test(
    'a stop closes the current request and late starts cannot revive it',
    () {
      final state = SupportAiActivityTracker();
      state.apply(SupportAiActivity.fromJson(active(10))!, 7, now);
      expect(state.isTyping(now), true);
      state.apply(
        const SupportAiActivity(conversationId: 7, isTyping: false),
        7,
        now,
      );
      state.apply(SupportAiActivity.fromJson(active(10))!, 7, now);
      expect(state.isTyping(now), false);
      state.apply(SupportAiActivity.fromJson(active(11))!, 7, now);
      expect(state.isTyping(now), true);
    },
  );
  test('older stop and older AI reply cannot hide the newer request', () {
    final state = SupportAiActivityTracker();
    state.apply(SupportAiActivity.fromJson(active(11))!, 7, now);
    state.apply(
      const SupportAiActivity(
        conversationId: 7,
        isTyping: false,
        messageId: 10,
      ),
      7,
      now,
    );
    state.observeReply(messageId: 12, replyToMessageId: 10, isHuman: false);
    expect(state.isTyping(now), true);
    state.observeReply(messageId: 13, replyToMessageId: 11, isHuman: false);
    expect(state.isTyping(now), false);
  });
  test(
    'reply arriving before HTTP/start activity permanently closes that request',
    () {
      final state = SupportAiActivityTracker();
      state.observeReply(messageId: 12, replyToMessageId: 10, isHuman: false);
      state.apply(SupportAiActivity.fromJson(active(10))!, 7, now);
      expect(state.isTyping(now), false);
    },
  );
  test(
    'human takeover closes earlier requests and future client messages can still progress',
    () {
      final state = SupportAiActivityTracker();
      state.observeReply(messageId: 20, isHuman: true);
      state.apply(SupportAiActivity.fromJson(active(19))!, 7, now);
      expect(state.isTyping(now), false);
      state.apply(SupportAiActivity.fromJson(active(21))!, 7, now);
      expect(state.isTyping(now), true);
    },
  );
  test('temporary hiding offscreen does not complete a live request', () {
    final state = SupportAiActivityTracker();
    state.apply(SupportAiActivity.fromJson(active(10))!, 7, now);
    state.hide();
    expect(state.isTyping(now), false);
    state.apply(SupportAiActivity.fromJson(active(10))!, 7, now);
    expect(state.isTyping(now), true);
    expect(state.isTyping(now.add(const Duration(seconds: 51))), false);
  });
}

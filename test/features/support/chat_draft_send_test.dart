import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/support/presentation/chat_draft_send.dart';

void main() {
  test(
    'acknowledgement clears a submitted composer containing outer whitespace',
    () async {
      final controller = TextEditingController(text: '  Message  ');
      addTearDown(controller.dispose);
      await sendChatDraft(
        controller: controller,
        text: 'Message',
        send: () async => true,
        isMounted: () => true,
      );
      expect(controller.text, isEmpty);
    },
  );

  test('failed send retains the complete message for retry', () async {
    final controller = TextEditingController(
      text: 'Payment details and question',
    );
    addTearDown(controller.dispose);
    final result = await sendChatDraft(
      controller: controller,
      text: controller.text,
      send: () async => false,
      isMounted: () => true,
    );
    expect(result, isFalse);
    expect(controller.text, 'Payment details and question');
  });

  test(
    'success clears only the submitted draft after acknowledgement',
    () async {
      final controller = TextEditingController(text: 'Message');
      addTearDown(controller.dispose);
      final response = Completer<bool>();
      final pending = sendChatDraft(
        controller: controller,
        text: controller.text,
        send: () => response.future,
        isMounted: () => true,
      );
      expect(controller.text, 'Message');
      response.complete(true);
      expect(await pending, isTrue);
      expect(controller.text, isEmpty);
    },
  );

  test('acknowledgement does not erase a newly edited draft', () async {
    final controller = TextEditingController(text: 'First message');
    addTearDown(controller.dispose);
    final response = Completer<bool>();
    final pending = sendChatDraft(
      controller: controller,
      text: controller.text,
      send: () => response.future,
      isMounted: () => true,
    );
    controller.text = 'Next message';
    response.complete(true);
    await pending;
    expect(controller.text, 'Next message');
  });

  test(
    'automatic invoice message does not erase another composer draft',
    () async {
      final controller = TextEditingController(text: 'My unsent question');
      addTearDown(controller.dispose);
      await sendChatDraft(
        controller: controller,
        text: 'Invoice automatically attached',
        send: () async => true,
        isMounted: () => true,
      );
      expect(controller.text, 'My unsent question');
    },
  );
}

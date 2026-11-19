import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogistic_shared/twoalogistic_shared.dart';
import 'package:twoalogisticcabineuser/src/core/models/chat_history_page.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:twoalogisticcabineuser/src/core/services/websocket_provider.dart';
import 'package:twoalogisticcabineuser/src/features/support/data/chat_provider.dart';
import 'package:twoalogisticcabineuser/src/features/support/data/support_ai_activity.dart';
import '../../../helpers/mock_data.dart';

class _Socket extends WebSocketService {
  _Socket() : super(serverUrl: 'http://127.0.0.1:1');
  final events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final incoming = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  @override
  Stream<Map<String, dynamic>> get typing => events.stream;
  @override
  Stream<Map<String, dynamic>> get messages => incoming.stream;
  @override
  Stream<Map<String, dynamic>> get messageEdited => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get messageDeleted => const Stream.empty();
  @override
  SocketConnectionStatus get currentStatus => SocketConnectionStatus.connected;
  @override
  void joinConversation(int conversationId) {}
  @override
  void leaveConversation(int conversationId) {}
  @override
  void sendPresence(int conversationId, bool isOpen) {}
  @override
  void dispose() {
    events.close();
    incoming.close();
    super.dispose();
  }
}

class _Repository extends ChatRepository {
  _Repository() : super(ApiClient());
  SupportAiActivity? activity;
  Future<SupportAiActivity?> Function()? fetch;
  int reads = 0;
  bool rejectSend = false;
  @override
  Future<SupportAiActivity?> fetchAiActivity({
    required int conversationId,
  }) async {
    reads++;
    return fetch == null ? activity : await fetch!();
  }

  @override
  Future<ChatHistoryPage> getHistoryPage({int? beforeMessageId}) async =>
      ChatHistoryPage(
        MockData.createMockConversation(
          id: 7,
          messages: [MockData.createMockMessage(id: 10, conversationId: 7)],
        ),
      );
  @override
  Future<List<ChatMessage>> getNewMessages(
    int conversationId,
    int afterMessageId,
  ) async => [];
  @override
  Future<ChatMessage> sendMessage(
    String content, {
    String contentType = 'text',
    List<int>? attachmentIds,
  }) async {
    if (rejectSend) throw Exception('rejected');
    return MockData.createMockMessage(
      id: 11,
      conversationId: 7,
      content: content,
    );
  }
}

SupportAiActivity active(
  int id, {
  Duration duration = const Duration(seconds: 45),
}) => SupportAiActivity(
  conversationId: 7,
  isTyping: true,
  messageId: id,
  expiresAt: DateTime.now().add(duration),
);
Map<String, dynamic> event(
  int id, {
  bool typing = true,
  int conversation = 7,
  int user = 0,
}) => {
  'conversationId': conversation,
  'isTyping': typing,
  'messageId': id,
  'expiresAt': DateTime.now()
      .add(const Duration(seconds: 45))
      .toIso8601String(),
  'userId': user,
  'userType': 'employee',
  'isAssistant': true,
};
void main() {
  testWidgets(
    'successful send uses canonical activity and support reply stops it before delayed HTTP can revive it',
    (tester) async {
      final socket = _Socket(), repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          webSocketServiceProvider.overrideWithValue(socket),
          chatRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });
      final controller = container.read(chatControllerProvider.notifier);
      controller.setRealtimeActive(true);
      await controller.loadConversation();
      await tester.pump();
      repository.activity = active(11);
      expect(await controller.sendMessage('Question'), true);
      await tester.pump();
      expect(container.read(chatControllerProvider).isAssistantTyping, true);
      final delayed = Completer<SupportAiActivity?>();
      repository.fetch = () => delayed.future;
      socket.events.add(event(11));
      await tester.pump();
      final reply = MockData.createMockMessage(
        id: 12,
        conversationId: 7,
        senderType: 'employee',
        senderId: 0,
      ).toJson()..['replyToMessageId'] = 11;
      socket.incoming.add(reply);
      await tester.pump();
      expect(container.read(chatControllerProvider).isAssistantTyping, false);
      delayed.complete(active(11));
      await tester.pump();
      expect(container.read(chatControllerProvider).isAssistantTyping, false);
    },
  );
  testWidgets(
    'expiry, offscreen lifecycle and disposal cancel polling and allow canonical restoration',
    (tester) async {
      final socket = _Socket(), repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          webSocketServiceProvider.overrideWithValue(socket),
          chatRepositoryProvider.overrideWithValue(repository),
        ],
      );
      final controller = container.read(chatControllerProvider.notifier);
      repository.activity = active(10);
      controller.setRealtimeActive(true);
      await controller.loadConversation();
      await tester.pump();
      expect(container.read(chatControllerProvider).isAssistantTyping, true);
      controller.setRealtimeActive(false);
      final reads = repository.reads;
      await tester.pump(const Duration(seconds: 10));
      expect(repository.reads, reads);
      expect(container.read(chatControllerProvider).isAssistantTyping, false);
      repository.activity = active(
        10,
        duration: const Duration(milliseconds: 50),
      );
      controller.setRealtimeActive(true);
      await tester.pump();
      expect(container.read(chatControllerProvider).isAssistantTyping, true);
      await tester.pump(const Duration(milliseconds: 60));
      expect(container.read(chatControllerProvider).isAssistantTyping, false);
      container.dispose();
      socket.dispose();
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'foreign/human typing is ignored and failed send never invents assistant activity',
    (tester) async {
      final socket = _Socket(), repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          webSocketServiceProvider.overrideWithValue(socket),
          chatRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });
      final controller = container.read(chatControllerProvider.notifier);
      controller.setRealtimeActive(true);
      await controller.loadConversation();
      await tester.pump();
      socket.events.add(event(10, conversation: 8));
      socket.events.add(event(10, user: 9));
      await tester.pump();
      expect(container.read(chatControllerProvider).isAssistantTyping, false);
      repository.rejectSend = true;
      expect(await controller.sendMessage('Question'), false);
      expect(container.read(chatControllerProvider).isAssistantTyping, false);
    },
  );
  testWidgets(
    'visible activity polls and a canonical stop recovers a lost WebSocket reply',
    (tester) async {
      final socket = _Socket(), repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          webSocketServiceProvider.overrideWithValue(socket),
          chatRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });
      final controller = container.read(chatControllerProvider.notifier);
      repository.activity = active(10);
      controller.setRealtimeActive(true);
      await controller.loadConversation();
      await tester.pump();
      final before = repository.reads;
      repository.activity = const SupportAiActivity(
        conversationId: 7,
        isTyping: false,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(repository.reads, before + 1);
      expect(container.read(chatControllerProvider).isAssistantTyping, false);
      await tester.pump(const Duration(seconds: 6));
      expect(repository.reads, before + 1);
    },
  );
  testWidgets(
    'slow canonical fetches coalesce polling and drain one pending refresh without starving the stop',
    (tester) async {
      final socket = _Socket(), repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          webSocketServiceProvider.overrideWithValue(socket),
          chatRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(() {
        container.dispose();
        socket.dispose();
      });
      final controller = container.read(chatControllerProvider.notifier);
      repository.activity = active(10);
      controller.setRealtimeActive(true);
      await controller.loadConversation();
      await tester.pump();
      final before = repository.reads;
      final delayed = Completer<SupportAiActivity?>();
      repository.fetch = () => delayed.future;
      await tester.pump(const Duration(seconds: 3));
      expect(repository.reads, before + 1);
      await tester.pump(const Duration(seconds: 6));
      expect(
        repository.reads,
        before + 1,
        reason: 'periodic hints do not overlap the slow HTTP request',
      );
      repository.fetch = () async =>
          const SupportAiActivity(conversationId: 7, isTyping: false);
      delayed.complete(
        const SupportAiActivity(conversationId: 7, isTyping: false),
      );
      await tester.pump();
      expect(container.read(chatControllerProvider).isAssistantTyping, false);
      expect(
        repository.reads,
        before + 2,
        reason: 'one coalesced canonical refresh follows completion',
      );
      await tester.pump(const Duration(seconds: 6));
      expect(repository.reads, before + 2);
    },
  );
}

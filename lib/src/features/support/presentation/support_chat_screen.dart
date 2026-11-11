import 'package:twoalogisticcabineuser/src/core/media/authenticated_media.dart';
import '../../training/presentation/training_target.dart';
// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'chat_draft_send.dart';
import 'package:twoalogisticcabineuser/src/core/ui/app_toast.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/ui/tutorial_card.dart';

import '../../../core/ui/app_background.dart';
import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_input_decoration.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/ui/app_keyboard_dismiss.dart';
import '../../../core/ui/fullscreen_image_overlay.dart';
import '../../../core/ui/pdf_preview_overlay.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/chat_presence_service.dart';
import '../../../core/network/api_config.dart';
import '../../../core/utils/file_download_helper.dart';
import '../../../core/utils/safe_url_launcher.dart';
import '../../notifications/application/notifications_controller.dart';
import '../../notifications/domain/notification_item.dart';
import '../../shell/application/shell_branch_provider.dart';
import '../data/chat_provider.dart';
import 'package:twoalogistic_shared/twoalogistic_shared.dart';
import 'package:twoalogisticcabineuser/src/core/ui/blurred_modal_bottom_sheet.dart';
import '../../../core/utils/locale_text.dart';

class SupportChatScreen extends ConsumerStatefulWidget {
  final String? initialMessage;

  const SupportChatScreen({super.key, this.initialMessage});

  @override
  ConsumerState<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen>
    with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isDisposed = false;
  late final IsChatScreenOpenNotifier _screenOpenNotifier;
  late final ChatPresenceService _chatPresenceService;
  late final PushNotificationService _notificationService;
  late final ChatController _chatController;

  // Локальный флаг защиты от двойной отправки (синхронный, выставляется раньше isSending в контроллере)
  bool _isSendingLocally = false;

  final GlobalKey _messagesAreaKey = GlobalKey();
  final GlobalKey _inputAreaKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _screenOpenNotifier = ref.read(isChatScreenOpenProvider.notifier);
    _chatPresenceService = ref.read(chatPresenceServiceProvider);
    _notificationService = ref.read(pushNotificationServiceProvider);
    _chatController = ref.read(chatControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    _initNotifications();

    // Загружаем чат и открываем presence
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _isDisposed) return;
      final isActive =
          ref.read(activeShellBranchIndexProvider) == ShellBranchIndex.support;
      _screenOpenNotifier.set(isActive);
      _chatController.setRealtimeActive(isActive);
      if (isActive) {
        unawaited(
          ref.read(notificationsControllerProvider.notifier).markTypesRead({
            NotificationType.chatMessage,
          }),
        );
      }
      await _chatController.loadConversation();
      if (!mounted || _isDisposed) return;

      // Если есть начальное сообщение - устанавливаем его в текстовое поле
      if (widget.initialMessage != null && widget.initialMessage!.isNotEmpty) {
        _textController.text = widget.initialMessage!;
      }

      // Уведомляем сервер что чат открыт (для блокировки push-уведомлений)
      if (isActive) {
        await _notifyServerChatOpened();
      }
    });

    // Очищаем уведомления при открытии чата
  }

  /// Уведомить сервер что чат открыт
  Future<void> _notifyServerChatOpened() async {
    final chatState = ref.read(chatControllerProvider);
    final conversationId = chatState.conversation?.id;
    await _chatPresenceService.openChat(
      ChatType.support,
      conversationId: conversationId,
    );
  }

  Future<void> _initNotifications() async {
    await _notificationService.initialize();
  }

  void _setScreenActive(bool isActive) {
    if (_isDisposed) return;
    _screenOpenNotifier.set(isActive);
    _chatController.setRealtimeActive(isActive);

    if (isActive) {
      unawaited(
        ref.read(notificationsControllerProvider.notifier).markTypesRead({
          NotificationType.chatMessage,
        }),
      );
      unawaited(_notifyServerChatOpened());
      return;
    }

    unawaited(_chatPresenceService.closeChat(ChatType.support));
  }

  @override
  void dispose() {
    _isDisposed = true;

    try {
      _screenOpenNotifier.set(false);
      _chatController.setRealtimeActive(false);
      unawaited(_chatPresenceService.closeChat(ChatType.support));
    } catch (_) {}

    // Не используем ref в dispose() - это небезопасно
    // ref.read() выполняется асинхронно при деактивации виджета

    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _isDisposed) return;
    if (ref.read(activeShellBranchIndexProvider) != ShellBranchIndex.support) {
      return;
    }
    debugPrint('App lifecycle state changed to: $state');

    if (state == AppLifecycleState.resumed) {
      // Обновляем сообщения при возврате в приложение
      _chatController.pollNewMessages();
      // Уведомляем сервер что чат снова открыт
      _notifyServerChatOpened();
    } else if (state == AppLifecycleState.paused) {
      // Уведомляем сервер что приложение ушло в фон
      ref.read(chatPresenceServiceProvider).onAppPaused();
    }
  }

  Future<void> _handleMessageSend(String text) async {
    if (_isSendingLocally) return;

    final chatState = ref.read(chatControllerProvider);
    if (chatState.isSending) return;

    final pendingAttachments = chatState.pendingAttachments;

    // Если нет текста и нет вложений - ничего не делаем
    if (text.trim().isEmpty && pendingAttachments.isEmpty) return;

    setState(() => _isSendingLocally = true);
    try {
      HapticFeedback.lightImpact();
      // Собираем ID вложений
      final attachmentIds = pendingAttachments.map((a) => a.id).toList();

      final success = await sendChatDraft(
        controller: _textController,
        text: text,
        isMounted: () => mounted,
        send: () => ref
            .read(chatControllerProvider.notifier)
            .sendMessage(
              text.isEmpty ? tr(context, ru: 'Файл', zh: '文件') : text,
              attachmentIds: attachmentIds,
            ),
      );

      if (!mounted) return;
      if (success) {
        // Очищаем pending attachments
        ref.read(chatControllerProvider.notifier).clearPendingAttachments();
        // Прокрутка вниз после отправки
        _scrollToBottom();
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingLocally = false);
      } else {
        _isSendingLocally = false;
      }
    }
  }

  /// Показать диалог выбора типа вложения
  void _showAttachmentPicker() {
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    showBlurredModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (sheetContext) => _SupportAttachmentPickerSheet(
        onCamera: () {
          Navigator.pop(sheetContext);
          _pickImageFromCamera();
        },
        onGallery: () {
          Navigator.pop(sheetContext);
          _pickImageFromGallery();
        },
        onDocument: () {
          Navigator.pop(sheetContext);
          _pickDocumentFile();
        },
      ),
    );
  }

  /// Выбрать изображение с камеры
  Future<void> _pickImageFromCamera() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
        requestFullMetadata: false, // Конвертирует HEIC в JPEG на iOS
      );
      if (image != null) {
        // Читаем bytes напрямую из XFile для избежания проблем с iOS sandbox
        final bytes = await image.readAsBytes();
        final fileName = image.name.isNotEmpty
            ? image.name
            : 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _uploadFileFromBytes(bytes, fileName);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar(
          tr(context, ru: 'Ошибка при съёмке: $e', zh: '拍照错误：$e'),
        );
      }
    }
  }

  /// Выбрать изображение из галереи
  Future<void> _pickImageFromGallery() async {
    debugPrint('📷 [Gallery] Starting image picker via file_picker...');
    try {
      // Используем file_picker вместо image_picker для обхода проблемы с HDR на iOS
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        allowCompression: false,
        compressionQuality: 0,
      );

      debugPrint(
        '📷 [Gallery] file_picker returned: ${result != null ? "file selected" : "null/cancelled"}',
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        debugPrint('📷 [Gallery] File name: ${file.name}');
        debugPrint('📷 [Gallery] File size: ${file.size}');

        final bytes = await file.xFile.readAsBytes();

        if (bytes.isEmpty) {
          debugPrint('📷 [Gallery] ERROR: could not read file bytes');
          if (mounted) {
            _showErrorSnackbar(
              tr(context, ru: 'Не удалось прочитать файл', zh: '无法读取文件'),
            );
          }
          return;
        }

        debugPrint('📷 [Gallery] Bytes read: ${bytes.length}');

        // Определяем имя файла
        String fileName = file.name;
        if (fileName.isEmpty) {
          fileName = 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        }

        debugPrint('📷 [Gallery] Uploading ${bytes.length} bytes as $fileName');
        await _uploadFileFromBytes(bytes, fileName);
        debugPrint('📷 [Gallery] Upload completed');
      }
    } catch (e, stack) {
      debugPrint('📷 [Gallery] ERROR: $e');
      debugPrint('📷 [Gallery] Stack: $stack');
      if (mounted) {
        _showErrorSnackbar(
          tr(context, ru: 'Ошибка при выборе изображения: $e', zh: '选择图片错误：$e'),
        );
      }
    }
  }

  /// Выбрать документ (PDF, Word, Excel и др.)
  Future<void> _pickDocumentFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'csv',
          'ppt',
          'pptx',
          'txt',
          'rtf',
          'zip',
          'rar',
          '7z',
        ],
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;

        final bytes = await file.xFile.readAsBytes();

        if (bytes.isEmpty) {
          if (mounted) {
            _showErrorSnackbar(
              tr(context, ru: 'Не удалось прочитать файл', zh: '无法读取文件'),
            );
          }
          return;
        }

        // Проверка размера (10MB)
        if (bytes.length > 10 * 1024 * 1024) {
          if (mounted) {
            _showErrorSnackbar(
              tr(
                context,
                ru: 'Файл слишком большой. Максимум 10 МБ',
                zh: '文件太大。最大 10 MB',
              ),
            );
          }
          return;
        }

        final fileName = file.name.isNotEmpty
            ? file.name
            : 'document_${DateTime.now().millisecondsSinceEpoch}';

        await _uploadFileFromBytes(bytes, fileName);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar(
          tr(context, ru: 'Ошибка при выборе файла: $e', zh: '选择文件错误：$e'),
        );
      }
    }
  }

  /// Загрузить файл из bytes на сервер (для iOS)
  Future<void> _uploadFileFromBytes(Uint8List bytes, String fileName) async {
    debugPrint(
      '📤 [Upload] _uploadFileFromBytes called with ${bytes.length} bytes, fileName: $fileName',
    );

    final chatState = ref.read(chatControllerProvider);
    final conversationId = chatState.conversation?.id;

    debugPrint('📤 [Upload] conversationId: $conversationId');

    if (conversationId == null) {
      debugPrint('📤 [Upload] ERROR: conversationId is null!');
      if (mounted) {
        _showErrorSnackbar(
          tr(context, ru: 'Чат не инициализирован', zh: '聊天未初始化'),
        );
      }
      return;
    }

    if (bytes.isEmpty) {
      debugPrint('📤 [Upload] ERROR: bytes are empty!');
      if (mounted) {
        _showErrorSnackbar(tr(context, ru: 'Файл пустой', zh: '文件为空'));
      }
      return;
    }

    debugPrint('📤 [Upload] Calling controller.uploadFileFromBytes...');
    final result = await ref
        .read(chatControllerProvider.notifier)
        .uploadFileFromBytes(bytes, fileName);

    debugPrint(
      '📤 [Upload] Result: ${result != null ? "success" : "null/error"}',
    );
    if (result == null && mounted) {
      _showErrorSnackbar(
        tr(context, ru: 'Ошибка при загрузке файла', zh: '上传文件错误'),
      );
    }
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    AppToast.showFromSnackBar(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.fixed,
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Хранение контекста Showcase для вызова next()

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(activeShellBranchIndexProvider, (previous, next) {
      if (previous == next) return;
      _setScreenActive(next == ShellBranchIndex.support);
    });

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final shellBottomInset = AppLayout.bottomBarObstruction(context) + 18;
    final keyboardBottomInset = keyboardInset + 10;
    final composerBottomInset =
        AppKeyboardDismissRegion.isKeyboardVisibleOf(context)
        ? keyboardBottomInset
        : shellBottomInset;

    return TutorialScreenWrapper(
      screenKey: 'support',
      steps: [
        TutorialStep(
          icon: Icons.support_agent_rounded,
          title: 'Чат поддержки',
          description:
              'Напишите нам любой вопрос. Менеджер ответит в рабочее время. История сообщений сохраняется.',
          targetKey: _messagesAreaKey,
        ),
        TutorialStep(
          icon: Icons.attach_file_rounded,
          title: 'Вложения',
          description:
              'Прикрепите фото или файл к сообщению — это поможет быстрее разобраться с вопросом.',
          targetKey: _inputAreaKey,
        ),
        TutorialStep(
          icon: Icons.send_rounded,
          title: 'Отправка',
          description:
              'Введите текст и нажмите кнопку отправки. Можно также отправить голосовое сообщение.',
          targetKey: _inputAreaKey,
        ),
      ],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            const Positioned.fill(child: AppBackground()),
            SafeArea(
              top: false, // Контент скроллится под топ-меню
              bottom: false,
              child: KeyedSubtree(
                key: _messagesAreaKey,
                child: _buildMessagesList(),
              ),
            ),
          ],
        ),
        bottomNavigationBar: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: composerBottomInset),
          child: _buildInputField(),
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    final chatState = ref.watch(chatControllerProvider);

    if (chatState.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(context.brandPrimary),
        ),
      );
    }

    if (chatState.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              chatState.error!,
              style: const TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref.read(chatControllerProvider.notifier).loadConversation();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.brandPrimary,
              ),
              child: Text(
                tr(context, ru: 'Повторить', zh: '重试'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    final messages = chatState.messages;

    if (messages.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: EdgeInsets.fromLTRB(
        16,
        AppLayout.topBarTotalHeight(context) + 8,
        16,
        10,
      ),
      itemCount: messages.length + (chatState.hasMoreHistory ? 1 : 0),
      addAutomaticKeepAlives: false,
      addSemanticIndexes: false,
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return TextButton(
            onPressed: chatState.isLoadingHistory
                ? null
                : () => ref
                      .read(chatControllerProvider.notifier)
                      .loadOlderMessages(),
            child: Text(
              tr(
                context,
                ru: chatState.isLoadingHistory
                    ? 'Загрузка…'
                    : chatState.historyError
                    ? 'Не удалось загрузить. Повторить'
                    : 'Предыдущие сообщения',
                zh: chatState.isLoadingHistory
                    ? '加载中…'
                    : chatState.historyError
                    ? '加载失败，重试'
                    : '更早的消息',
              ),
            ),
          );
        }
        final message = messages[messages.length - 1 - index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isMe = message.isFromClient;
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    // Используем реальное имя из сообщения
    final authorName = message.senderName;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Имя автора сообщения
          Padding(
            padding: EdgeInsets.only(
              left: isMe ? 0 : 40,
              right: isMe ? 40 : 0,
              bottom: 4,
            ),
            child: Text(
              authorName,
              style: const TextStyle(
                fontFamily: 'Gilroy',
                fontSize: 12.2,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),

          // Сообщение
          Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [context.brandPrimary, context.brandSecondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: context.brandPrimary.withValues(alpha: 0.16),
                        blurRadius: 14,
                        spreadRadius: -8,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 8),
              ],

              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.74,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    gradient: isMe
                        ? LinearGradient(
                            colors: [
                              context.brandPrimary,
                              context.brandSecondary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isMe ? null : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(22),
                      topRight: const Radius.circular(22),
                      bottomLeft: Radius.circular(isMe ? 22 : 6),
                      bottomRight: Radius.circular(isMe ? 6 : 22),
                    ),
                    border: isMe
                        ? null
                        : Border.all(
                            color: Colors.black.withValues(alpha: 0.035),
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.055),
                        blurRadius: 22,
                        spreadRadius: -14,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Цитата (reply)
                      if (message.replyToMessageId != null)
                        GestureDetector(
                          onTap: () =>
                              _scrollToMessage(message.replyToMessageId!),
                          child: _buildReplyQuote(message, isMe),
                        ),

                      // Отображаем вложения
                      if (message.attachments.isNotEmpty)
                        _buildMessageAttachments(message.attachments, isMe),

                      // Текст сообщения (если это не просто "Файл")
                      if (message.content.isNotEmpty &&
                          message.content != 'Файл')
                        SelectionArea(
                          child: MarkdownBody(
                            data: message.content.replaceAll('\n', '  \n'),
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                fontFamily: 'Gilroy',
                                fontSize: 15,
                                height: 1.4,
                                color: isMe ? Colors.white : Colors.black87,
                              ),
                              strong: TextStyle(
                                fontFamily: 'Gilroy',
                                fontSize: 15,
                                height: 1.4,
                                fontWeight: FontWeight.bold,
                                color: isMe ? Colors.white : Colors.black87,
                              ),
                              em: TextStyle(
                                fontFamily: 'Gilroy',
                                fontSize: 15,
                                height: 1.4,
                                fontStyle: FontStyle.italic,
                                color: isMe ? Colors.white : Colors.black87,
                              ),
                              a: TextStyle(
                                fontFamily: 'Gilroy',
                                fontSize: 15,
                                height: 1.4,
                                color: isMe
                                    ? Colors.white
                                    : context.brandPrimary,
                                decoration: TextDecoration.underline,
                              ),
                              code: TextStyle(
                                fontFamily: 'Gilroy',
                                fontSize: 14,
                                color: isMe ? Colors.white : Colors.black87,
                                backgroundColor: isMe
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : Colors.grey.withValues(alpha: 0.2),
                              ),
                              listBullet: TextStyle(
                                fontFamily: 'Gilroy',
                                fontSize: 15,
                                color: isMe ? Colors.white : Colors.black87,
                              ),
                            ),
                            onTapLink: (text, href, title) {
                              launchSafeExternalUrl(href);
                            },
                          ),
                        ),
                      if (message.content.isNotEmpty &&
                          message.content != 'Файл')
                        const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.isEdited) ...[
                            Text(
                              'изм.',
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: isMe ? Colors.white54 : Colors.black38,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            dateFormat.format(message.createdAt.toLocal()),
                            style: TextStyle(
                              fontFamily: 'Gilroy',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isMe ? Colors.white70 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              if (isMe) ...[
                const SizedBox(width: 8),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.035),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.055),
                        blurRadius: 14,
                        spreadRadius: -8,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    color: context.brandPrimary,
                    size: 17,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Отображение вложений в сообщении
  void _scrollToMessage(int messageId) {
    final messages = ref.read(chatControllerProvider).messages;
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index < 0 || !_scrollController.hasClients) return;
    final reversedIndex = messages.length - 1 - index;
    final offset = reversedIndex * 80.0;
    _scrollController.animateTo(
      offset.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Widget _buildReplyQuote(ChatMessage message, bool isMe) {
    final chatState = ref.read(chatControllerProvider);
    final replyMsg = chatState.messages
        .where((m) => m.id == message.replyToMessageId)
        .firstOrNull;
    if (replyMsg == null) return const SizedBox.shrink();

    final senderLabel = replyMsg.isFromClient ? 'Вы' : replyMsg.senderName;
    final quoteText = replyMsg.content.length > 60
        ? '${replyMsg.content.substring(0, 60)}...'
        : replyMsg.content;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isMe
                ? Colors.white.withValues(alpha: 0.6)
                : context.brandPrimary,
            width: 2.5,
          ),
        ),
        color: isMe
            ? Colors.white.withValues(alpha: 0.12)
            : context.brandPrimary.withValues(alpha: 0.08),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            senderLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isMe
                  ? Colors.white.withValues(alpha: 0.8)
                  : context.brandPrimary,
            ),
          ),
          Text(
            quoteText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: isMe
                  ? Colors.white.withValues(alpha: 0.6)
                  : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageAttachments(List<ChatAttachment> attachments, bool isMe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: attachments.map((attachment) {
        final isImage = attachment.fileType.startsWith('image/');
        final isPdf = _isPdfAttachment(
          attachment.fileName,
          attachment.fileType,
        );
        final fullUrl = ApiConfig.getMediaUrl(attachment.url);
        final previewSize = (MediaQuery.sizeOf(context).width * 0.56)
            .clamp(190.0, 230.0)
            .toDouble();
        final previewBg = isMe
            ? Colors.white.withValues(alpha: 0.16)
            : const Color(0xFFF8FAFC);

        if (isImage) {
          return GestureDetector(
            onTap: () => _showFullImage(fullUrl, attachment.fileName),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: previewSize,
                  height: previewSize,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: previewBg),
                      AuthenticatedCachedImage(
                        imageUrl: fullUrl,
                        width: previewSize,
                        height: previewSize,
                        fit: BoxFit.contain,
                        memCacheWidth: 420,
                        memCacheHeight: 420,
                        maxWidthDiskCache: 900,
                        maxHeightDiskCache: 900,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        filterQuality: FilterQuality.medium,
                        placeholder: (context, url) => ColoredBox(
                          color: previewBg,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => ColoredBox(
                          color: previewBg,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image,
                                color: isMe ? Colors.white70 : Colors.black45,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Ошибка загрузки',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isMe ? Colors.white70 : Colors.black45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildImageDownloadButton(
                        onPressed: () =>
                            _downloadFile(fullUrl, attachment.fileName),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        } else {
          // Документ (PDF, Word, Excel и др.)
          final docIcon = _getDocumentIcon(attachment.fileName);
          final docColor = _getDocumentColor(attachment.fileName);
          return GestureDetector(
            onTap: isPdf
                ? () => _showPdfPreview(fullUrl, attachment.fileName)
                : () => _downloadFile(fullUrl, attachment.fileName),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.15)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.2)
                          : docColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      docIcon,
                      color: isMe ? Colors.white : docColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.fileName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isMe ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (attachment.fileSize != null)
                          Text(
                            _formatFileSize(attachment.fileSize!),
                            style: TextStyle(
                              fontSize: 12,
                              color: isMe ? Colors.white70 : Colors.black45,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.download_rounded,
                    color: isMe ? Colors.white70 : docColor,
                    size: 20,
                  ),
                ],
              ),
            ),
          );
        }
      }).toList(),
    );
  }

  Widget _buildImageDownloadButton({required VoidCallback onPressed}) {
    return Positioned(
      top: 6,
      right: 6,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tr(context, ru: 'Скачать', zh: '下载'),
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          padding: EdgeInsets.zero,
          color: Colors.white,
          onPressed: onPressed,
          icon: const Icon(Icons.download_rounded),
        ),
      ),
    );
  }

  /// Иконка документа по расширению файла
  IconData _getDocumentIcon(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
      case 'rtf':
        return Icons.description;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'txt':
        return Icons.article;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// Цвет иконки документа по расширению
  Color _getDocumentColor(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
      case 'rtf':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Colors.green;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'zip':
      case 'rar':
      case '7z':
        return Colors.amber;
      case 'txt':
        return Colors.grey;
      default:
        return context.brandPrimary;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Показать изображение на весь экран
  void _showFullImage(String url, String fileName) {
    showFullscreenImageOverlay(
      context: context,
      imageUrl: url,
      fileName: fileName,
      onDownload: () => _downloadFile(url, fileName),
    );
  }

  bool _isPdfAttachment(String fileName, String fileType) {
    return fileType.toLowerCase() == 'application/pdf' ||
        fileName.toLowerCase().endsWith('.pdf');
  }

  void _showPdfPreview(String url, String fileName) {
    showPdfPreviewOverlay(
      context: context,
      url: url,
      fileName: fileName,
      onDownload: () => _downloadFile(url, fileName),
    );
  }

  /// Скачать файл
  Future<void> _downloadFile(String url, String fileName) async {
    try {
      // Показываем индикатор загрузки
      if (mounted) {
        AppToast.showFromSnackBar(
          context,
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Text(tr(context, ru: 'Загрузка файла...', zh: '正在下载文件...')),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.fixed,
          ),
        );
      }

      final bytes = await loadMediaBytes(mediaApiClient(context), url);
      if (!mounted) return;
      final saved = await downloadFile(bytes: bytes, fileName: fileName);
      if (!saved) {
        throw Exception('Could not save file');
      }
      if (!mounted) return;
      AppToast.hide();
      AppToast.showFromSnackBar(
        context,
        SnackBar(
          content: Text(
            tr(context, ru: 'Файл сохранён: $fileName', zh: '文件已保存：$fileName'),
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.fixed,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.hide();
      AppToast.showFromSnackBar(
        context,
        SnackBar(
          content: Text(tr(context, ru: 'Ошибка загрузки: $e', zh: '下载错误：$e')),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [context.brandPrimary, context.brandSecondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            tr(context, ru: 'Чат поддержки', zh: '客服聊天'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              tr(
                context,
                ru: 'Напишите нам и мы поможем решить любой вопрос',
                zh: '给我们写信，我们会帮您解决任何问题',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField() {
    final chatState = ref.watch(chatControllerProvider);
    final pendingAttachments = chatState.pendingAttachments;
    final isUploading = chatState.isUploading;

    return Padding(
      key: _inputAreaKey,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 28,
              spreadRadius: -14,
              offset: const Offset(0, 16),
            ),
            BoxShadow(
              color: context.brandPrimary.withValues(alpha: 0.10),
              blurRadius: 22,
              spreadRadius: -16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pendingAttachments.isNotEmpty || isUploading)
                  _buildPendingAttachments(
                    context,
                    pendingAttachments,
                    isUploading,
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _SupportComposerButton(
                      icon: Icons.attach_file_rounded,
                      onTap: _showAttachmentPicker,
                      tooltip: tr(context, ru: 'Прикрепить', zh: '附加'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: AppOutlinedInputFrame(
                          radius: 20,
                          borderWidth: 1.2,
                          focusedBorderWidth: 1.6,
                          fillColor: const Color(0xFFF8FAFC),
                          borderColor: const Color(0xFFE1E5ED),
                          focusedBorderColor: context.brandPrimary,
                          builder: (context, focusNode) {
                            return TrainingTarget(
                              id: 'support.message',
                              child: TextField(
                                controller: _textController,
                                focusNode: focusNode,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.newline,
                                decoration: InputDecoration(
                                  hintText: tr(
                                    context,
                                    ru: 'Введите сообщение...',
                                    zh: '输入消息...',
                                  ),
                                  hintStyle: const TextStyle(
                                    color: Color(0xFFB0B4BE),
                                    fontFamily: 'Gilroy',
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                  isDense: true,
                                ),
                                style: const TextStyle(
                                  fontFamily: 'Gilroy',
                                  fontSize: 15,
                                  height: 1.25,
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                                textCapitalization:
                                    TextCapitalization.sentences,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final isSending = ref.watch(
                          chatControllerProvider.select((s) => s.isSending),
                        );
                        final sendDisabled =
                            isSending || isUploading || _isSendingLocally;
                        return _SupportComposerButton(
                          icon: Icons.send_rounded,
                          isLoading: sendDisabled,
                          isDisabled: sendDisabled,
                          onTap: sendDisabled
                              ? null
                              : () => _handleMessageSend(_textController.text),
                          tooltip: tr(context, ru: 'Отправить', zh: '发送'),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Виджет для отображения прикреплённых файлов перед отправкой
  Widget _buildPendingAttachments(
    BuildContext context,
    List<ChatAttachment> attachments,
    bool isUploading,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Показываем загружаемый файл
            if (isUploading)
              Container(
                width: 72,
                height: 72,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        context.brandPrimary,
                      ),
                    ),
                  ),
                ),
              ),

            // Показываем уже загруженные файлы
            ...attachments.map((attachment) {
              final fileType = attachment.fileType;
              final fileName = attachment.fileName;
              final url = attachment.url;
              final isImage = fileType.startsWith('image/');

              return Container(
                width: 72,
                height: 72,
                margin: const EdgeInsets.only(right: 8),
                child: Stack(
                  children: [
                    // Превью файла
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: isImage
                          ? AuthenticatedCachedImage(
                              imageUrl: ApiConfig.getMediaUrl(url),
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              memCacheWidth: 160,
                              memCacheHeight: 160,
                              maxWidthDiskCache: 320,
                              maxHeightDiskCache: 320,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              filterQuality: FilterQuality.low,
                              placeholder: (context, url) => Container(
                                color: const Color(0xFFF0F0F0),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: const Color(0xFFF0F0F0),
                                child: const Icon(Icons.error),
                              ),
                            )
                          : Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: _getDocumentColor(
                                  fileName,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _getDocumentIcon(fileName),
                                    color: _getDocumentColor(fileName),
                                    size: 28,
                                  ),
                                  const SizedBox(height: 4),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Text(
                                      fileName,
                                      style: const TextStyle(
                                        fontSize: 8,
                                        color: Colors.black54,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),

                    // Кнопка удаления
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          ref
                              .read(chatControllerProvider.notifier)
                              .removePendingAttachment(attachment.id);
                        },
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SupportComposerButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final bool isLoading;
  final bool isDisabled;

  const _SupportComposerButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.isLoading = false,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !isDisabled;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: enabled
                    ? [context.brandPrimary, context.brandSecondary]
                    : [const Color(0xFFB8BDC8), const Color(0xFFD5D8DF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: context.brandPrimary.withValues(alpha: 0.18),
                        blurRadius: 16,
                        spreadRadius: -10,
                        offset: const Offset(0, 9),
                      ),
                    ]
                  : null,
            ),
            child: isLoading
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(icon, color: Colors.white, size: 21),
          ),
        ),
      ),
    );
  }
}

class _SupportAttachmentPickerSheet extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onDocument;

  const _SupportAttachmentPickerSheet({
    required this.onCamera,
    required this.onGallery,
    required this.onDocument,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          AppLayout.bottomBarObstruction(context) + 16,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 30,
                spreadRadius: -16,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFD7DAE1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: context.brandGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: context.brandPrimary.withValues(alpha: 0.18),
                      blurRadius: 20,
                      spreadRadius: -12,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
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
                        Icons.attach_file_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(context, ru: 'Прикрепить файл', zh: '附加文件'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Gilroy',
                              fontSize: 20,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            tr(
                              context,
                              ru: 'Фото, скриншот или документ к обращению',
                              zh: '为请求添加照片、截图或文档',
                            ),
                            style: const TextStyle(
                              color: Color(0xE6FFFFFF),
                              fontFamily: 'Gilroy',
                              fontSize: 12.8,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SupportAttachmentOptionTile(
                icon: Icons.camera_alt_rounded,
                title: tr(context, ru: 'Камера', zh: '相机'),
                subtitle: tr(context, ru: 'Сделать фото сейчас', zh: '立即拍照'),
                color: Colors.blue,
                onTap: onCamera,
              ),
              const SizedBox(height: 8),
              _SupportAttachmentOptionTile(
                icon: Icons.photo_library_rounded,
                title: tr(context, ru: 'Галерея', zh: '相册'),
                subtitle: tr(
                  context,
                  ru: 'Выбрать готовое изображение',
                  zh: '选择现有图片',
                ),
                color: Colors.green,
                onTap: onGallery,
              ),
              const SizedBox(height: 8),
              _SupportAttachmentOptionTile(
                icon: Icons.insert_drive_file_rounded,
                title: tr(context, ru: 'Документ', zh: '文档'),
                subtitle: tr(
                  context,
                  ru: 'PDF, Word, Excel и другие файлы',
                  zh: 'PDF、Word、Excel等文件',
                ),
                color: Colors.orange,
                onTap: onDocument,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportAttachmentOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SupportAttachmentOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black.withValues(alpha: 0.035)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'Gilroy',
                        fontSize: 15,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Gilroy',
                        fontSize: 12.5,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

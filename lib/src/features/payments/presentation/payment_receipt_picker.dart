import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/ui/blurred_modal_bottom_sheet.dart';
import '../../../core/utils/locale_text.dart';

const paymentReceiptAllowedExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
  'pdf',
];

const paymentReceiptMaxBytes = 15 * 1024 * 1024;

class PaymentReceiptTooLarge implements Exception {
  const PaymentReceiptTooLarge();
}

void validatePaymentReceiptSize(int bytes) {
  if (bytes > paymentReceiptMaxBytes) throw const PaymentReceiptTooLarge();
}

enum _PaymentReceiptSource { gallery, files }

class PaymentReceiptSelection {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  const PaymentReceiptSelection({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });
}

String? paymentReceiptExtension(String fileName, {String? explicitExtension}) {
  final explicit = explicitExtension?.trim().toLowerCase();
  if (explicit != null && explicit.isNotEmpty) return explicit;

  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == fileName.length - 1) return null;
  return fileName.substring(dotIndex + 1).toLowerCase();
}

String paymentReceiptMimeType(String extension) {
  return switch (extension.toLowerCase()) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };
}

/// Показывает единый выбор источника чека и возвращает готовые данные файла.
/// Ошибки выбора отображаются здесь, чтобы оба платёжных сценария вели себя
/// одинаково.
Future<PaymentReceiptSelection?> pickPaymentReceipt(
  BuildContext context,
) async {
  final source = await showBlurredModalBottomSheet<_PaymentReceiptSource>(
    context: context,
    useRootNavigator: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 5,
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr(sheetContext, ru: 'Приложить чек', zh: '附加付款凭证'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            _ReceiptSourceTile(
              icon: Icons.photo_library_rounded,
              title: tr(sheetContext, ru: 'Галерея', zh: '相册'),
              subtitle: tr(
                sheetContext,
                ru: 'Фото или скриншот оплаты',
                zh: '付款照片或截图',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_PaymentReceiptSource.gallery),
            ),
            _ReceiptSourceTile(
              icon: Icons.folder_rounded,
              title: tr(sheetContext, ru: 'Файлы', zh: '文件'),
              subtitle: tr(
                sheetContext,
                ru: 'Изображение или PDF · до 15 МБ',
                zh: '图片或 PDF · 最大 15 MB',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_PaymentReceiptSource.files),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted || source == null) return null;

  try {
    final selection = switch (source) {
      _PaymentReceiptSource.gallery => await _pickReceiptFromGallery(),
      _PaymentReceiptSource.files => await _pickReceiptFromFiles(),
    };
    if (!context.mounted || selection == null) return null;
    validatePaymentReceiptSize(selection.bytes.length);
    if (selection.bytes.isEmpty) {
      AppToast.show(
        context,
        tr(context, ru: 'Выбранный файл пуст', zh: '所选文件为空'),
        isError: true,
      );
      return null;
    }
    return selection;
  } on PaymentReceiptTooLarge {
    if (context.mounted) {
      AppToast.show(
        context,
        tr(
          context,
          ru: 'Чек больше 15 МБ. Уменьшите изображение или размер PDF и выберите файл снова.',
          zh: '凭证超过 15 MB，请缩小图片或 PDF 后重新选择。',
        ),
        isError: true,
      );
    }
    return null;
  } on UnsupportedError {
    if (context.mounted) {
      AppToast.show(
        context,
        tr(context, ru: 'Неподдерживаемый формат файла', zh: '不支持的文件格式'),
        isError: true,
      );
    }
    return null;
  } catch (_) {
    if (context.mounted) {
      AppToast.show(
        context,
        tr(context, ru: 'Не удалось выбрать чек', zh: '无法选择付款凭证'),
        isError: true,
      );
    }
    return null;
  }
}

Future<PaymentReceiptSelection?> _pickReceiptFromGallery() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    requestFullMetadata: false,
  );
  if (picked == null) return null;
  validatePaymentReceiptSize(await picked.length());

  var fileName = picked.name.trim();
  var extension = paymentReceiptExtension(fileName);
  final pickerMime = picked.mimeType?.toLowerCase();

  extension ??= switch (pickerMime) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/heic' => 'heic',
    'image/heif' => 'heif',
    _ => 'jpg',
  };
  if (!paymentReceiptAllowedExtensions.contains(extension) ||
      extension == 'pdf') {
    throw UnsupportedError('Unsupported payment receipt image');
  }
  if (paymentReceiptExtension(fileName) == null) {
    fileName = '${fileName.isEmpty ? 'receipt' : fileName}.$extension';
  }

  return PaymentReceiptSelection(
    bytes: await picked.readAsBytes(),
    fileName: fileName,
    mimeType: pickerMime ?? paymentReceiptMimeType(extension),
  );
}

Future<PaymentReceiptSelection?> _pickReceiptFromFiles() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: paymentReceiptAllowedExtensions,
    withData: false,
  );
  if (result == null || result.files.isEmpty) return null;

  final file = result.files.first;
  validatePaymentReceiptSize(file.size);
  final extension = paymentReceiptExtension(
    file.name,
    explicitExtension: file.extension,
  );
  if (extension == null ||
      !paymentReceiptAllowedExtensions.contains(extension)) {
    throw UnsupportedError('Unsupported payment receipt file');
  }

  return PaymentReceiptSelection(
    bytes: file.bytes ?? await file.xFile.readAsBytes(),
    fileName: file.name,
    mimeType: paymentReceiptMimeType(extension),
  );
}

class _ReceiptSourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ReceiptSourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: context.brandPrimary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: context.brandPrimary),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontFamily: 'Gilroy',
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontFamily: 'Gilroy',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textSecondary,
      ),
      onTap: onTap,
    );
  }
}

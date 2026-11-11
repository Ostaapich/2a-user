import '../../training/presentation/training_target.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ui/app_colors.dart';
import '../../../core/ui/app_toast.dart';
import '../../../core/utils/locale_text.dart';
import '../../../core/ui/blurred_modal_bottom_sheet.dart';

class WarehouseAddressCheckData {
  final String clientCode;
  final String address;
  final String phone;

  const WarehouseAddressCheckData({
    required this.clientCode,
    required this.address,
    required this.phone,
  });
}

class WarehouseAddressCheckField {
  final String label;
  final String expectedValue;
  final String? recognizedValue;
  final bool matched;
  final int matchPercent;
  final String? missingFragment;

  const WarehouseAddressCheckField({
    required this.label,
    required this.expectedValue,
    required this.recognizedValue,
    required this.matched,
    required this.matchPercent,
    this.missingFragment,
  });
}

class WarehouseAddressCheckResult {
  final List<WarehouseAddressCheckField> fields;

  const WarehouseAddressCheckResult(this.fields);

  bool get isValid =>
      fields.isNotEmpty && fields.every((field) => field.matched);
}

class WarehouseAddressVerifier {
  static WarehouseAddressCheckResult verify({
    required WarehouseAddressCheckData expected,
    required String recognizedText,
  }) {
    final normalizedText = _normalize(recognizedText);
    final addressWithoutMarker = expected.address
        .replaceFirst(RegExp(r'\s*\(不要隐藏代码\s*[^)]*\)\s*$'), '')
        .trim();

    final fields = <WarehouseAddressCheckField>[
      _clientCodeField(expected.clientCode, recognizedText),
      if (expected.phone.trim().isNotEmpty)
        _phoneField(expected.phone, recognizedText),
      if (addressWithoutMarker.isNotEmpty)
        _addressField(
          addressWithoutMarker,
          expected.address,
          expected.clientCode,
          recognizedText,
          normalizedText,
        ),
    ];

    return WarehouseAddressCheckResult(fields);
  }

  static WarehouseAddressCheckField _clientCodeField(
    String clientCode,
    String recognizedText,
  ) {
    final normalizedExpected = _normalize(clientCode);
    final exactMatched =
        normalizedExpected.isNotEmpty &&
        _normalize(recognizedText).contains(normalizedExpected);
    final expectedReconstructed = _reconstructSplitValue(
      expected: normalizedExpected,
      recognizedText: recognizedText,
    );
    final recognizedValue = exactMatched || expectedReconstructed != null
        ? clientCode
        : _findAnyClientCode(recognizedText);
    final matched = exactMatched || expectedReconstructed != null;
    return WarehouseAddressCheckField(
      label: 'Код клиента',
      expectedValue: clientCode,
      recognizedValue: recognizedValue,
      matched: matched,
      matchPercent: matched ? 100 : 0,
      missingFragment: matched ? null : clientCode,
    );
  }

  static WarehouseAddressCheckField _phoneField(
    String phone,
    String recognizedText,
  ) {
    final expectedDigits = _digits(phone);
    final recognizedValue = _bestPhoneCandidate(phone, recognizedText);
    final recognizedDigits = _digits(recognizedValue ?? '');
    final localExpected = expectedDigits.length > 11
        ? expectedDigits.substring(expectedDigits.length - 11)
        : expectedDigits;
    final matched =
        expectedDigits.isNotEmpty &&
        (recognizedDigits.contains(expectedDigits) ||
            (localExpected.length == 11 &&
                recognizedDigits.contains(localExpected)));
    return WarehouseAddressCheckField(
      label: 'Телефон склада',
      expectedValue: phone,
      recognizedValue: recognizedValue,
      matched: matched,
      matchPercent: matched ? 100 : 0,
      missingFragment: matched ? null : phone,
    );
  }

  static WarehouseAddressCheckField _addressField(
    String address,
    String displayedAddress,
    String clientCode,
    String recognizedText,
    String normalizedText,
  ) {
    final normalizedAddress = _normalize(address);
    final score = _containedNgramScore(normalizedAddress, normalizedText);
    final bestRecognizedValue = _bestRecognizedFragment(
      expected: normalizedAddress,
      recognizedText: recognizedText,
      maxJoinedLines: 6,
      preferredFragment: _normalize(clientCode),
    );
    final reconstructedCode = _reconstructSplitValue(
      expected: _normalize(clientCode),
      recognizedText: recognizedText,
    );
    final splitCodeSuffix = _splitValueSuffix(
      expected: _normalize(clientCode),
      recognizedText: recognizedText,
    );
    final reconstructedRecognizedCode = _findAnyClientCode(recognizedText);
    final recognizedValue =
        bestRecognizedValue == null || reconstructedCode == null
        ? _appendDetectedCode(bestRecognizedValue, reconstructedRecognizedCode)
        : '${bestRecognizedValue.trim()} ${splitCodeSuffix ?? ''}'.trim();
    final normalizedRecognizedValue = _normalize(recognizedValue ?? '');
    final normalizedClientCode = _normalize(clientCode);
    final clientCodeInAddress =
        normalizedClientCode.isNotEmpty &&
        normalizedRecognizedValue.contains(normalizedClientCode);
    final addressMatched = normalizedAddress.isNotEmpty && score >= 0.82;
    final matched = addressMatched && clientCodeInAddress;
    return WarehouseAddressCheckField(
      label: 'Адрес склада',
      expectedValue: displayedAddress,
      recognizedValue: recognizedValue,
      matched: matched,
      matchPercent: matched
          ? 100
          : clientCodeInAddress
          ? (score * 100).round().clamp(0, 99)
          : ((score * 80).round()).clamp(0, 80),
      missingFragment: matched
          ? null
          : addressMatched && !clientCodeInAddress
          ? 'В поле адреса отсутствует код клиента: $clientCode'
          : _firstMissingFragment(normalizedAddress, normalizedText),
    );
  }

  static double _containedNgramScore(String expected, String actual) {
    if (expected.isEmpty || actual.isEmpty) return 0;
    if (actual.contains(expected)) return 1;
    if (expected.length < 3) return actual.contains(expected) ? 1 : 0;

    const size = 3;
    var matched = 0;
    final total = expected.length - size + 1;
    for (var index = 0; index <= expected.length - size; index++) {
      if (actual.contains(expected.substring(index, index + size))) {
        matched++;
      }
    }
    return matched / total;
  }

  static String? _firstMissingFragment(String expected, String actual) {
    if (expected.isEmpty) return null;
    if (actual.isEmpty) {
      return expected.substring(0, expected.length.clamp(0, 10));
    }
    final window = expected.length >= 4 ? 4 : expected.length;
    for (var index = 0; index <= expected.length - window; index++) {
      final fragment = expected.substring(index, index + window);
      if (!actual.contains(fragment)) {
        final start = (index - 2).clamp(0, expected.length);
        final end = (index + window + 4).clamp(start, expected.length);
        return expected.substring(start, end);
      }
    }
    return null;
  }

  static String? _bestRecognizedFragment({
    required String expected,
    required String recognizedText,
    int maxJoinedLines = 2,
    String? preferredFragment,
  }) {
    final lines = recognizedText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    String? best;
    var bestScore = 0.0;
    var bestContainsPreferred = false;
    for (var start = 0; start < lines.length; start++) {
      for (
        var count = 1;
        count <= maxJoinedLines && start + count <= lines.length;
        count++
      ) {
        final candidateLines = lines.sublist(start, start + count);
        final candidate = candidateLines.join(' ');
        final normalizedCandidate = _normalize(candidate);
        final score = _containedNgramScore(expected, normalizedCandidate);
        final containsPreferred = _containsPreferredInsideMatchedBlock(
          expected: expected,
          lines: candidateLines,
          preferredFragment: preferredFragment,
        );
        if (score > bestScore ||
            (score == bestScore &&
                containsPreferred &&
                !bestContainsPreferred) ||
            (score == bestScore &&
                containsPreferred == bestContainsPreferred &&
                (best == null || candidate.length < best.length))) {
          bestScore = score;
          best = candidate;
          bestContainsPreferred = containsPreferred;
        }
      }
    }
    return bestScore > 0 ? best : null;
  }

  static bool _containsPreferredInsideMatchedBlock({
    required String expected,
    required List<String> lines,
    required String? preferredFragment,
  }) {
    if (preferredFragment == null || preferredFragment.isEmpty) return false;

    int? firstAddressLine;
    for (var index = 0; index < lines.length; index++) {
      final normalizedLine = _normalize(lines[index]);
      if (firstAddressLine == null &&
          _containedNgramScore(expected, normalizedLine) >= 0.12) {
        firstAddressLine = index;
      }
    }

    if (firstAddressLine == null) return false;
    final normalizedAddressBlock = _normalize(
      lines.sublist(firstAddressLine).join(' '),
    );
    return normalizedAddressBlock.contains(preferredFragment);
  }

  static String? _reconstructSplitValue({
    required String expected,
    required String recognizedText,
  }) {
    final suffix = _splitValueSuffix(
      expected: expected,
      recognizedText: recognizedText,
    );
    return suffix == null ? null : expected;
  }

  static String? _splitValueSuffix({
    required String expected,
    required String recognizedText,
  }) {
    if (expected.length < 4) return null;
    final lines = recognizedText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    for (var split = 2; split <= expected.length - 2; split++) {
      final prefix = expected.substring(0, split);
      final suffix = expected.substring(split);
      String? prefixLine;
      String? suffixLine;
      for (final line in lines) {
        final normalizedLine = _normalize(line);
        if (prefixLine == null && normalizedLine.endsWith(prefix)) {
          prefixLine = line;
        }
        if (suffixLine == null && normalizedLine == suffix) {
          suffixLine = line;
        }
      }
      if (prefixLine != null && suffixLine != null) {
        return suffixLine;
      }
    }
    return null;
  }

  static String? _findAnyClientCode(String recognizedText) {
    final normalizedWidth = String.fromCharCodes(
      recognizedText.runes.map((rune) {
        if (rune >= 0xFF01 && rune <= 0xFF5E) return rune - 0xFEE0;
        return rune;
      }),
    );
    final lines = normalizedWidth
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    for (var index = 0; index < lines.length; index++) {
      final prefix = RegExp(
        r'\b(2A|WD|TT|BB)-\s*$',
        caseSensitive: false,
      ).firstMatch(lines[index]);
      if (prefix == null) continue;
      for (final line in lines) {
        if (RegExp(r'^\d{1,6}$').hasMatch(line)) {
          return '${prefix.group(1)!.toUpperCase()}-$line';
        }
      }
    }
    return RegExp(
      r'\b(?:2A|WD|TT|BB)-\d+(?:-[A-Z0-9]+)*\b',
      caseSensitive: false,
    ).firstMatch(normalizedWidth)?.group(0)?.toUpperCase();
  }

  static String? _appendDetectedCode(String? value, String? detectedCode) {
    if (value == null || detectedCode == null) return value;
    final normalizedValue = _normalize(value);
    final normalizedCode = _normalize(detectedCode);
    if (normalizedValue.contains(normalizedCode)) return value;

    final separatorIndex = detectedCode.indexOf('-');
    if (separatorIndex < 0) return value;
    final prefix = detectedCode.substring(0, separatorIndex + 1);
    if (!value.trimRight().toUpperCase().endsWith(prefix)) return value;
    return '${value.trimRight()}${detectedCode.substring(separatorIndex + 1)}';
  }

  static String? _bestPhoneCandidate(String expected, String recognizedText) {
    final normalizedWidth = String.fromCharCodes(
      recognizedText.runes.map((rune) {
        if (rune >= 0xFF10 && rune <= 0xFF19) return rune - 0xFEE0;
        if (rune == 0xFF0B ||
            rune == 0xFF0D ||
            rune == 0xFF08 ||
            rune == 0xFF09) {
          return rune - 0xFEE0;
        }
        return rune;
      }),
    );
    final candidates = normalizedWidth
        .split(RegExp(r'[\r\n]+'))
        .expand((line) => RegExp(r'\+?\d[\d \t()\-]{5,}\d').allMatches(line))
        .map((match) => match.group(0)?.trim())
        .whereType<String>()
        .where((value) => _digits(value).length >= 7)
        .toList();
    if (candidates.isEmpty) return null;

    final expectedDigits = _digits(expected);
    candidates.sort((left, right) {
      final leftScore = _digitSimilarity(expectedDigits, _digits(left));
      final rightScore = _digitSimilarity(expectedDigits, _digits(right));
      return rightScore.compareTo(leftScore);
    });
    return candidates.first;
  }

  static double _digitSimilarity(String expected, String actual) {
    if (expected.isEmpty || actual.isEmpty) return 0;
    if (expected.contains(actual) || actual.contains(expected)) return 1;
    final expectedLocal = expected.length > 11
        ? expected.substring(expected.length - 11)
        : expected;
    final actualLocal = actual.length > 11
        ? actual.substring(actual.length - 11)
        : actual;
    var same = 0;
    final length = expectedLocal.length < actualLocal.length
        ? expectedLocal.length
        : actualLocal.length;
    for (var index = 0; index < length; index++) {
      if (expectedLocal[index] == actualLocal[index]) same++;
    }
    return same /
        (expectedLocal.length > actualLocal.length
            ? expectedLocal.length
            : actualLocal.length);
  }

  static String _normalize(String value) {
    final normalizedWidth = String.fromCharCodes(
      value.runes.map((rune) {
        if (rune >= 0xFF10 && rune <= 0xFF19) return rune - 0xFEE0;
        if (rune >= 0xFF21 && rune <= 0xFF3A) return rune - 0xFEE0;
        if (rune >= 0xFF41 && rune <= 0xFF5A) return rune - 0xFEE0;
        return rune;
      }),
    );
    return normalizedWidth.toLowerCase().replaceAll(
      RegExp(r'[^\p{L}\p{N}]', unicode: true),
      '',
    );
  }

  static String _digits(String value) => String.fromCharCodes(
    value.runes.map((rune) {
      if (rune >= 0xFF10 && rune <= 0xFF19) return rune - 0xFEE0;
      return rune;
    }),
  ).replaceAll(RegExp(r'[^0-9]'), '');
}

abstract class WarehouseScreenshotTextRecognizer {
  Future<String> recognize(String imagePath);
}

class NativeWarehouseScreenshotTextRecognizer
    implements WarehouseScreenshotTextRecognizer {
  static const _channel = MethodChannel(
    'com.twoalogistic.user/text_recognition',
  );

  const NativeWarehouseScreenshotTextRecognizer();

  @override
  Future<String> recognize(String imagePath) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      throw PlatformException(
        code: 'UNSUPPORTED_PLATFORM',
        message:
            'Проверка скриншота доступна в приложении на iPhone и Android.',
      );
    }
    final text = await _channel.invokeMethod<String>('recognizeText', {
      'path': imagePath,
    });
    return text?.trim() ?? '';
  }
}

final _warehouseScreenshotPickers = Expando<bool>();

Future<XFile?> _pickWarehouseScreenshot() =>
    ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 100);

Future<void> showWarehouseAddressChecker(
  BuildContext context, {
  required WarehouseAddressCheckData expected,
  WarehouseScreenshotTextRecognizer recognizer =
      const NativeWarehouseScreenshotTextRecognizer(),
  Future<XFile?> Function()? screenshotPicker,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  if (_warehouseScreenshotPickers[navigator] == true) return;
  _warehouseScreenshotPickers[navigator] = true;
  try {
    final supported =
        recognizer is! NativeWarehouseScreenshotTextRecognizer ||
        (!kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android));
    XFile? image;
    if (supported) {
      try {
        image = await (screenshotPicker?.call() ?? _pickWarehouseScreenshot());
      } catch (error) {
        if (!context.mounted || !navigator.mounted) return;
        AppToast.show(
          context,
          error is PlatformException &&
                  error.code.toLowerCase().contains('denied')
              ? tr(
                  context,
                  ru: 'Нет доступа к фото. Разрешите доступ в настройках устройства и повторите.',
                  zh: '无法访问照片，请在设备设置中授权后重试。',
                )
              : tr(
                  context,
                  ru: 'Не удалось открыть выбор скриншота. Попробуйте ещё раз.',
                  zh: '无法打开截图选择器，请重试。',
                ),
          isError: true,
        );
        return;
      }
      if (!context.mounted || !navigator.mounted || image == null) return;
    }
    if (!context.mounted || !navigator.mounted) return;
    await showBlurredModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WarehouseAddressCheckerSheet(
        expected: expected,
        recognizer: recognizer,
        screenshotPicker: screenshotPicker,
        initialImage: image,
      ),
    );
  } finally {
    _warehouseScreenshotPickers[navigator] = false;
  }
}

class WarehouseAddressCheckerSheet extends StatefulWidget {
  final WarehouseAddressCheckData expected;
  final WarehouseScreenshotTextRecognizer recognizer;
  final Future<XFile?> Function()? screenshotPicker;
  final XFile? initialImage;

  const WarehouseAddressCheckerSheet({
    super.key,
    required this.expected,
    required this.recognizer,
    this.screenshotPicker,
    this.initialImage,
  });

  @override
  State<WarehouseAddressCheckerSheet> createState() =>
      _WarehouseAddressCheckerSheetState();
}

class _WarehouseAddressCheckerSheetState
    extends State<WarehouseAddressCheckerSheet> {
  bool get _recognitionAvailable =>
      widget.recognizer is! NativeWarehouseScreenshotTextRecognizer ||
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android));
  bool _checking = false;
  Uint8List? _previewBytes;
  WarehouseAddressCheckResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    final image = widget.initialImage;
    if (image != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_pickAndCheck(selectedImage: image));
      });
    }
  }

  Future<void> _pickAndCheck({XFile? selectedImage}) async {
    if (_checking || !_recognitionAvailable) return;
    setState(() => _checking = true);
    try {
      final image =
          selectedImage ??
          await (widget.screenshotPicker?.call() ?? _pickWarehouseScreenshot());
      if (!mounted || image == null) return;
      setState(() {
        _result = null;
        _error = null;
      });
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      final text = await widget.recognizer.recognize(image.path);
      if (!mounted) return;
      if (text.isEmpty) {
        setState(() {
          _previewBytes = bytes;
          _error =
              'Не удалось распознать текст. Выберите более чёткий скриншот.';
        });
        return;
      }
      setState(() {
        _previewBytes = bytes;
        _result = WarehouseAddressVerifier.verify(
          expected: widget.expected,
          recognizedText: text,
        );
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.code.toLowerCase().contains('denied')
            ? tr(
                context,
                ru: 'Нет доступа к фото. Разрешите доступ в настройках устройства и повторите.',
                zh: '无法访问照片，请在设备设置中授权后重试。',
              )
            : error.message ??
                  tr(
                    context,
                    ru: 'Не удалось проверить скриншот.',
                    zh: '无法检查截图。',
                  );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось проверить скриншот. Попробуйте ещё раз.';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8DCE3),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Проверка адреса',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'Gilroy',
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Загрузите скриншот из китайского маркетплейса. Текст распознаётся прямо на телефоне — изображение не отправляется на сервер.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontFamily: 'Gilroy',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              if (!_recognitionAvailable) ...[
                const SizedBox(height: 16),
                _MessageCard(
                  color: context.brandPrimary,
                  icon: Icons.info_outline,
                  text: tr(
                    context,
                    ru: 'Распознавание скриншота доступно в приложении на iPhone и Android. В браузере сравните адрес и код клиента вручную.',
                    zh: '截图识别可在 iPhone 和 Android 应用中使用。在浏览器中请手动核对地址和客户代码。',
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '${widget.expected.clientCode}\n${widget.expected.address}\n${widget.expected.phone}',
                ),
              ],
              if (_previewBytes != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.memory(
                    _previewBytes!,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                _MessageCard(
                  color: const Color(0xFFC43C3C),
                  icon: Icons.error_outline_rounded,
                  text: _error!,
                ),
              ],
              if (result != null) ...[
                const SizedBox(height: 16),
                _MessageCard(
                  color: result.isValid
                      ? const Color(0xFF27966A)
                      : const Color(0xFFC47A24),
                  icon: result.isValid
                      ? Icons.verified_rounded
                      : Icons.warning_amber_rounded,
                  text: result.isValid
                      ? 'Всё заполнено правильно. Адрес, телефон и код клиента совпадают.'
                      : 'Обнаружены несовпадения. Проверьте отмеченные поля перед оформлением заказа.',
                ),
                const SizedBox(height: 12),
                for (final field in result.fields) ...[
                  _CheckFieldCard(field: field),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 18),
              TrainingTarget(
                id: 'warehouse.screenshot',
                child: FilledButton.icon(
                  onPressed: _checking || !_recognitionAvailable
                      ? null
                      : _pickAndCheck,
                  icon: _checking
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    _checking
                        ? 'Проверяем…'
                        : _previewBytes == null
                        ? 'Выбрать скриншот'
                        : 'Проверить другой скриншот',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.brandPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Gilroy',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _MessageCard({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'Gilroy',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckFieldCard extends StatelessWidget {
  final WarehouseAddressCheckField field;

  const _CheckFieldCard({required this.field});

  @override
  Widget build(BuildContext context) {
    final color = field.matched
        ? const Color(0xFF27966A)
        : const Color(0xFFC43C3C);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                field.matched
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  field.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'Gilroy',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  field.matched
                      ? 'Совпадает'
                      : field.label == 'Адрес склада'
                      ? '${field.matchPercent}%'
                      : 'Есть отличие',
                  style: TextStyle(
                    color: color,
                    fontFamily: 'Gilroy',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ComparisonValue(
            label: 'Выдано системой',
            value: field.expectedValue,
            color: context.brandPrimary,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 7),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.textSecondary,
              size: 22,
            ),
          ),
          _ComparisonValue(
            label: 'Найдено на скриншоте',
            value: field.recognizedValue ?? 'Значение не найдено',
            color: color,
          ),
          if (!field.matched && field.missingFragment != null) ...[
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Проверьте фрагмент: '),
                  TextSpan(
                    text: field.missingFragment,
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'Gilroy',
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComparisonValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ComparisonValue({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontFamily: 'Gilroy',
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          SelectableText(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontFamily: 'Gilroy',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

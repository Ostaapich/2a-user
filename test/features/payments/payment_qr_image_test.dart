import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/payments/utils/payment_qr_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
          'Gilroy',
        )..addFont(rootBundle.load('assets/fonts/gilroy/Gilroy-ExtraBold.ttf')))
        .load();
  });
  test('export has red warning above QR with quiet zone', () async {
    final bytes = await createPaymentQrImage(
      payload: 'https://example.com/pay/test-only-123',
    );
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final pixels = (await image.toByteData())!;
    var red = 0, dark = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final i = (y * image.width + x) * 4;
        final r = pixels.getUint8(i),
            g = pixels.getUint8(i + 1),
            b = pixels.getUint8(i + 2);
        if (r > 100 && r > g * 1.8 && r > b * 1.8) {
          red++;
          expect(y, lessThan(image.height * .2));
        }
        if (r < 20 && g < 20 && b < 20) {
          dark++;
          expect(y, greaterThan(image.height * .1));
          expect(x, greaterThan(30));
          expect(x, lessThan(image.width - 30));
        }
      }
    }
    expect(paymentPayerWarning, 'НЕ ОПЛАЧИВАТЬ С ИП/ООО');
    expect(red, greaterThan(100));
    expect(dark, greaterThan(1000));
    final file = File(
      '../outputs/2026-11-10-payments-ux/exported-payment-qr.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    image.dispose();
    codec.dispose();
  });
  test('remote pixels preserved at original resolution below header', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 40, 40),
      Paint()..color = Colors.black,
    );
    final picture = recorder.endRecording();
    final source = await picture.toImage(80, 80);
    final png = (await source.toByteData(format: ui.ImageByteFormat.png))!;
    final bytes = await createPaymentQrImage(
      imageBytes: png.buffer.asUint8List(),
    );
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final raw = (await image.toByteData())!;
    final offsetY = image.height - 80 - 16;
    for (var y = 0; y < 80; y++) {
      for (var x = 0; x < 80; x++) {
        final index = ((offsetY + y) * image.width + 16 + x) * 4;
        expect(raw.getUint8(index), x < 40 && y < 40 ? 0 : 255);
      }
    }
    image.dispose();
    codec.dispose();
    source.dispose();
    picture.dispose();
  });
}

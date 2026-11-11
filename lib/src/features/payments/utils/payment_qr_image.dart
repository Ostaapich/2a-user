import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

const paymentPayerWarning = 'НЕ ОПЛАЧИВАТЬ С ИП/ООО';

/// Exports a payment QR with a permanent payer warning outside its quiet zone.
/// Supplied images retain their original pixels and dimensions.
Future<Uint8List> createPaymentQrImage({
  String? payload,
  Uint8List? imageBytes,
}) async {
  assert((payload == null) != (imageBytes == null));
  ui.Image? source;
  try {
    late final int width;
    late final int height;
    late final int margin;
    QrPainter? painter;
    if (imageBytes != null) {
      final codec = await ui.instantiateImageCodec(imageBytes);
      try {
        source = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      width = source.width;
      height = source.height;
      margin = (width * .2).ceil();
    } else {
      final validation = QrValidator.validate(data: payload!);
      final qr = validation.qrCode;
      if (!validation.isValid || qr == null) {
        throw StateError('Cannot encode payment QR');
      }
      // Integer module size avoids resampling QR edges.
      final moduleSize = (1024 / qr.moduleCount).ceil();
      width = height = qr.moduleCount * moduleSize;
      margin = moduleSize * 4;
      painter = QrPainter.withQr(qr: qr, gapless: true);
    }
    final outputWidth = width + margin * 2;
    final text = TextPainter(
      text: TextSpan(
        text: paymentPayerWarning,
        style: TextStyle(
          color: const Color(0xFFB91C1C),
          fontFamily: 'Gilroy',
          fontSize: outputWidth * .037,
          fontWeight: FontWeight.w800,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: outputWidth - margin.toDouble());
    final headerHeight = (text.height + outputWidth * .065).ceil();
    final outputHeight = headerHeight + height + margin * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
    text.paint(
      canvas,
      Offset((outputWidth - text.width) / 2, outputWidth * .032),
    );
    text.dispose();
    final origin = Offset(
      margin.toDouble(),
      (headerHeight + margin).toDouble(),
    );
    if (source != null) {
      canvas.drawImage(
        source,
        origin,
        Paint()..filterQuality = FilterQuality.none,
      );
    } else {
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      painter!.paint(canvas, Size(width.toDouble(), height.toDouble()));
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final ui.Image image;
    try {
      image = await picture.toImage(outputWidth, outputHeight);
    } finally {
      picture.dispose();
    }
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Cannot export payment QR');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    source?.dispose();
  }
}

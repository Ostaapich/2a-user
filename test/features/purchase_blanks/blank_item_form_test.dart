import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:twoalogisticcabineuser/src/features/purchase_blanks/presentation/widgets/blank_item_form.dart';

void main() {
  testWidgets('failed save keeps entered fields visible and permits retry', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlankItemForm(
              onSave:
                  ({
                    required productName,
                    required productUrl,
                    characteristics,
                    required quantity,
                    required unitPrice,
                    newPhotos,
                    newPhotoNames,
                  }) async {
                    if (++saves == 1) throw StateError('network');
                  },
            ),
          ),
        ),
      ),
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Sneakers');
    await tester.enterText(fields.at(1), 'https://example.com/item');
    await tester.enterText(fields.at(4), '12.5');
    final save = find.widgetWithText(FilledButton, 'Добавить товар');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Sneakers'), findsOneWidget);
    expect(find.textContaining('Введённые данные оставлены'), findsOneWidget);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saves, 2);
  });
  testWidgets('Chinese blank form translates labels and validation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: BlankItemForm(
              onSave:
                  ({
                    required productName,
                    required productUrl,
                    characteristics,
                    required quantity,
                    required unitPrice,
                    newPhotos,
                    newPhotoNames,
                  }) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('商品名称 *'), findsOneWidget);
    expect(find.text('商品链接 *'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, '添加商品');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('必填项'), findsNWidgets(2));
    expect(find.text('请输入价格'), findsOneWidget);
  });

  testWidgets('photo picker is serialized and unlocks after completion', (
    tester,
  ) async {
    final firstResult = Completer<List<XFile>>();
    var calls = 0;
    await tester.pumpWidget(
      _FormHost(
        photoPicker: () {
          calls++;
          if (calls == 1) return firstResult.future;
          return Future.value(const []);
        },
      ),
    );

    final addPhotos = find.byKey(const Key('blank_item_add_photos'));
    await tester.tap(addPhotos);
    await tester.pump();
    await tester.tap(addPhotos);
    await tester.pump();
    expect(calls, 1);

    firstResult.complete(const []);
    await tester.pump();
    await tester.tap(addPhotos);
    await tester.pump();

    expect(calls, 2);
  });

  testWidgets('photo picker unlocks after an error without hiding it', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _FormHost(
        photoPicker: () {
          calls++;
          if (calls == 1) {
            return Future<List<XFile>>.error(
              PlatformException(code: 'already_active'),
            );
          }
          return Future.value(const []);
        },
      ),
    );

    final addPhotos = find.byKey(const Key('blank_item_add_photos'));
    final dynamic callback = tester.widget<InkWell>(addPhotos).onTap;
    final Future<void> firstAttempt = callback() as Future<void>;
    await expectLater(firstAttempt, throwsA(isA<PlatformException>()));
    await tester.pump();

    await tester.tap(addPhotos);
    await tester.pump();
    expect(calls, 2);
  });
}

class _FormHost extends StatelessWidget {
  const _FormHost({required this.photoPicker});

  final BlankItemPhotoPicker photoPicker;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BlankItemForm(
            photoPicker: photoPicker,
            onSave:
                ({
                  required productName,
                  required productUrl,
                  characteristics,
                  required quantity,
                  required unitPrice,
                  newPhotos,
                  newPhotoNames,
                }) async {},
          ),
        ),
      ),
    );
  }
}

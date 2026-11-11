import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/purchase_blanks/data/blank_item_save_session.dart';

void main() {
  test('failed item save never starts photo upload', () async {
    final session = BlankItemSaveSession();
    var uploads = 0;
    await expectLater(
      session.save(
        saveItem: (_) async => null,
        photos: [
          Uint8List.fromList([1]),
        ],
        uploadPhoto: (_, _, _) async {
          uploads++;
          return 'url';
        },
      ),
      throwsA(
        isA<BlankItemSaveFailure>().having(
          (e) => e.stage,
          'stage',
          BlankItemSaveStage.item,
        ),
      ),
    );
    expect(uploads, 0);
    expect(session.savedItemId, isNull);
  });

  test(
    'retry after a partial photo failure reuses item and confirmed uploads',
    () async {
      final session = BlankItemSaveSession();
      final photos = [
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
      ];
      final savedIds = <int?>[];
      final uploaded = <int>[];
      var failSecondPhoto = true;
      Future<void> save() => session.save(
        saveItem: (id) async {
          savedIds.add(id);
          return id ?? 45;
        },
        photos: photos,
        uploadPhoto: (id, bytes, index) async {
          expect(id, 45);
          uploaded.add(index);
          return index == 1 && failSecondPhoto ? null : 'url/$index';
        },
      );
      await expectLater(
        save(),
        throwsA(
          isA<BlankItemSaveFailure>().having(
            (e) => e.stage,
            'stage',
            BlankItemSaveStage.photo,
          ),
        ),
      );
      failSecondPhoto = false;
      await save();
      expect(savedIds, [null, 45]);
      expect(uploaded, [0, 1, 1]);
    },
  );
}

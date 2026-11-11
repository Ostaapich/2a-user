import 'dart:typed_data';

enum BlankItemSaveStage { item, photo }

class BlankItemSaveFailure implements Exception {
  const BlankItemSaveFailure(this.stage);
  final BlankItemSaveStage stage;
}

/// Remembers confirmed steps while the item form remains open.
/// Retrying a failed photo must not create another item or upload earlier photos.
class BlankItemSaveSession {
  BlankItemSaveSession({this.savedItemId});

  int? savedItemId;
  final _uploadedPhotos = Set<Uint8List>.identity();

  Future<void> save({
    required Future<int?> Function(int? savedItemId) saveItem,
    required List<Uint8List> photos,
    required Future<String?> Function(int itemId, Uint8List bytes, int index)
    uploadPhoto,
  }) async {
    final itemId = await saveItem(savedItemId);
    if (itemId == null) {
      throw const BlankItemSaveFailure(BlankItemSaveStage.item);
    }
    savedItemId = itemId;
    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      if (_uploadedPhotos.contains(photo)) continue;
      if (await uploadPhoto(itemId, photo, index) == null) {
        throw const BlankItemSaveFailure(BlankItemSaveStage.photo);
      }
      _uploadedPhotos.add(photo);
    }
  }
}

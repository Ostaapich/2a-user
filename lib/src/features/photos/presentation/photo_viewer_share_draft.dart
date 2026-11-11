/// Owns the prepared browser file for one viewer selection.
/// A late result from a previous selection is revoked rather than displayed.
class PhotoViewerShareDraft {
  PhotoViewerShareDraft(this._clearPrepared);

  final void Function(String) _clearPrepared;
  int _revision = 0;
  String? _preparedId;

  int get revision => _revision;
  String? get preparedId => _preparedId;

  void reset() {
    _revision++;
    final previous = _preparedId;
    _preparedId = null;
    if (previous != null) _clearPrepared(previous);
  }

  bool accept(int revision, String? preparedId) {
    if (revision != _revision) {
      if (preparedId != null) _clearPrepared(preparedId);
      return false;
    }
    final previous = _preparedId;
    _preparedId = preparedId;
    if (previous != null && previous != preparedId) _clearPrepared(previous);
    return true;
  }
}

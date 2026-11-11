import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/photos/presentation/photo_viewer_share_draft.dart';

void main() {
  test(
    'swiping from prepared A to B revokes A and requires a new preparation',
    () {
      final cleared = <String>[];
      final draft = PhotoViewerShareDraft(cleared.add);
      expect(draft.accept(draft.revision, 'photo-A'), isTrue);
      draft.reset();
      expect(draft.preparedId, isNull);
      expect(cleared, ['photo-A']);
      expect(draft.accept(draft.revision, 'photo-B'), isTrue);
      expect(draft.preparedId, 'photo-B');
    },
  );
  test('late preparation for A after swiping cannot replace B', () {
    final cleared = <String>[];
    final draft = PhotoViewerShareDraft(cleared.add);
    final revisionA = draft.revision;
    draft.reset();
    expect(draft.accept(draft.revision, 'photo-B'), isTrue);
    expect(draft.accept(revisionA, 'photo-A'), isFalse);
    expect(draft.preparedId, 'photo-B');
    expect(cleared, ['photo-A']);
  });
  test(
    'dispose/reset invalidates an in-flight result and clears at most once',
    () {
      final cleared = <String>[];
      final draft = PhotoViewerShareDraft(cleared.add);
      final revision = draft.revision;
      draft.reset();
      draft.reset();
      expect(draft.accept(revision, 'closed-viewer'), isFalse);
      expect(draft.preparedId, isNull);
      expect(cleared, ['closed-viewer']);
    },
  );
}

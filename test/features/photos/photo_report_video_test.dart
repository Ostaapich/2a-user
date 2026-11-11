import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/photos/domain/photo_item.dart';
import 'package:twoalogisticcabineuser/src/features/photos/presentation/photo_report_video_badge.dart';
import 'package:twoalogisticcabineuser/src/features/tracks/domain/track_item.dart';

Map<String, dynamic> video(String id) => {
  'id': id,
  'url': '/uploads/photodesk-videos/$id.mp4',
  'fileName': '$id.mp4',
  'mimeType': 'video/mp4',
  'sizeBytes': 100,
  'durationSeconds': null,
  'createdAt': '2026-10-22T01:00:00Z',
  'trackId': 12,
  'photoRequestId': 34,
};

Map<String, dynamic> photo(int id, {List<Map<String, dynamic>>? videos}) => {
  'id': id,
  'url': '/uploads/photo-$id.jpg',
  'track': {'trackNumber': 'TRACK-12'},
  'createdAt': '2026-10-22T01:00:00Z',
  if (videos != null) 'photoRequest': {'videos': videos},
};

void main() {
  test('old photo-only API and empty videos preserve gallery contents', () {
    final items = [
      PhotoItem.fromJson(photo(1)),
      PhotoItem.fromJson(photo(2, videos: [])),
    ];
    expect(
      items.every((item) => item.reportVideos.isEmpty && !item.isVideo),
      isTrue,
    );
    expect(photoReportGallery(items), items);
  });

  test('report attachments keep identity, track and optional duration', () {
    final item = PhotoItem.fromJson(photo(1, videos: [video('video-1')]));
    final attachment = item.reportVideos.single;
    expect(attachment.videoId, 'video-1');
    expect(attachment.isVideo, isTrue);
    expect(attachment.trackingNumber, 'TRACK-12');
    expect(attachment.url, endsWith('/video-1.mp4'));
    expect(attachment.date, DateTime.utc(2026, 10, 22, 1));
  });

  test('several photos of a report do not duplicate videos in viewer', () {
    final first = PhotoItem.fromJson(photo(1, videos: [video('shared')]));
    final second = PhotoItem.fromJson(
      photo(2, videos: [video('shared'), video('other')]),
    );
    final gallery = photoReportGallery([first, second]);
    expect(gallery.where((item) => item.isVideo).map((item) => item.videoId), [
      'shared',
      'other',
    ]);
    expect(gallery.where((item) => !item.isVideo), [first, second]);
    expect(gallery.indexOf(second), 2);
  });

  test(
    'mixed gallery lists top-level and attached video once in either order',
    () {
      final image = PhotoItem.fromJson(photo(1, videos: [video('shared')]));
      final standalone = PhotoItem.fromJson({
        ...video('shared'),
        'id': 'video:shared',
        'trackNumber': 'TRACK-12',
      });
      for (final items in [
        [image, standalone],
        [standalone, image],
      ]) {
        final gallery = photoReportGallery(items);
        expect(gallery.where((item) => item.isVideo), hasLength(1));
        expect(gallery.where((item) => !item.isVideo), [image]);
      }
    },
  );

  test('viewer selects retained same-id video when its signed URL changed', () {
    final first = PhotoItem(
      url: '/video.mp4?session=old',
      videoId: '42',
      date: DateTime(2026),
    );
    final requested = PhotoItem(
      url: '/video.mp4?session=new',
      videoId: '42',
      date: DateTime(2026),
    );
    final image = PhotoItem(
      url: '/image.jpg',
      date: DateTime(2026),
      reportVideos: [first],
    );
    final gallery = photoReportGallery([image, requested]);
    expect(gallery, [image, first]);
    expect(photoReportGalleryIndex(gallery, requested), 1);
    expect(photoReportGalleryIndex(gallery, image), 0);
    expect(photoReportGalleryIndex([], requested), 0);
  });

  test('legacy video detection ignores query and handles uppercase paths', () {
    expect(
      PhotoItem(
        url: '/uploads/VIDEO.MP4?download=1',
        date: DateTime(2026),
      ).isVideo,
      isTrue,
    );
    expect(
      PhotoItem(
        url: '/uploads/image.jpg?name=video.mp4',
        date: DateTime(2026),
      ).isVideo,
      isFalse,
    );
  });

  test('track and nested request add videos without requiring any photos', () {
    final value = TrackItem.fromJson({
      'id': 12,
      'trackNumber': 'TRACK-12',
      'videos': [video('track')],
      'photoRequests': [
        {
          'id': 34,
          'videos': [video('request')],
        },
      ],
    });
    expect(value.photoReportUrls, ['/uploads/photodesk-videos/track.mp4']);
    expect(value.photoRequests.single.mediaUrls, [
      '/uploads/photodesk-videos/request.mp4',
    ]);
  });

  test('track legacy photos and request preserve old optional contract', () {
    final value = TrackItem.fromJson({
      'id': 12,
      'photos': [
        {'url': '/uploads/photo.jpg'},
      ],
      'photoRequests': [
        {
          'id': 34,
          'photos': [
            {'url': '/uploads/request.jpg'},
          ],
        },
      ],
    });
    expect(value.photoReportUrls, ['/uploads/photo.jpg']);
    expect(value.photoRequests.single.mediaUrls, ['/uploads/request.jpg']);
    expect(TrackItem.fromJson({'id': 13}).photoReportUrls, isEmpty);
  });

  testWidgets('optional badge opens videos and disappears without videos', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoReportVideoBadge(count: 2, onPressed: () => opened++),
        ),
      ),
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.tap(find.byType(InkWell));
    expect(opened, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoReportVideoBadge(count: 0, onPressed: () => opened++),
        ),
      ),
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });
}

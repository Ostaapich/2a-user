import '../../../core/network/api_config.dart';

class PhotoItem {
  final int? id;
  final String url;
  final DateTime date;
  final String? trackingNumber;
  final String? assemblyNumber;
  final List<PhotoItem> reportVideos;
  final String? videoId;

  const PhotoItem({
    this.id,
    required this.url,
    required this.date,
    this.trackingNumber,
    this.assemblyNumber,
    this.reportVideos = const [],
    this.videoId,
  });

  factory PhotoItem.fromJson(Map<String, dynamic> json) {
    // Получаем URL и формируем полный путь если относительный
    final rawUrl =
        json['url'] as String? ?? json['thumbnailUrl'] as String? ?? '';
    final fullUrl = ApiConfig.getMediaUrl(rawUrl);

    return PhotoItem(
      id: json['id'] is int ? json['id'] as int : null,
      videoId: json['mimeType']?.toString().startsWith('video/') == true
          ? json['id']?.toString()
          : null,
      reportVideos:
          ((json['photoRequest'] as Map<String, dynamic>?)?['videos']
                      as List<dynamic>? ??
                  const [])
              .whereType<Map<String, dynamic>>()
              .where((video) => (video['url'] as String?)?.isNotEmpty == true)
              .map(
                (video) => PhotoItem.fromJson({
                  ...video,
                  'trackNumber':
                      json['trackNumber'] ?? json['track']?['trackNumber'],
                }),
              )
              .toList(),
      url: fullUrl,
      date: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      trackingNumber:
          json['trackNumber'] as String? ??
          json['track']?['trackNumber'] as String?,
      assemblyNumber: json['assembly']?['number'] as String?,
    );
  }

  bool get isVideo {
    final lower = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    return videoId != null ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mov');
  }
}

/// Attach report videos once even when several photos belong to that report.
List<PhotoItem> photoReportGallery(List<PhotoItem> photos) {
  final result = <PhotoItem>[];
  final seenIds = <String>{};
  final seenUrls = <String>{};
  void append(PhotoItem item) {
    if (item.isVideo) {
      if (seenUrls.contains(item.url) ||
          (item.videoId != null && seenIds.contains(item.videoId))) {
        return;
      }
      seenUrls.add(item.url);
      if (item.videoId != null) seenIds.add(item.videoId!);
    }
    result.add(item);
  }

  for (final photo in photos) {
    append(photo);
    for (final video in photo.reportVideos) {
      append(video);
    }
  }
  return result;
}

/// Locate the retained item after merging top-level and attached videos.
int photoReportGalleryIndex(List<PhotoItem> gallery, PhotoItem requested) {
  final index = gallery.indexWhere(
    (item) =>
        identical(item, requested) ||
        (item.isVideo &&
            requested.isVideo &&
            (item.url == requested.url ||
                (item.videoId != null && item.videoId == requested.videoId))),
  );
  return index < 0 ? 0 : index;
}

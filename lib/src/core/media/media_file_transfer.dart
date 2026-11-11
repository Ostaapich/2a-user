import 'dart:io';

import 'package:dio/dio.dart';

import '../network/api_client.dart';
import 'authenticated_media.dart';

/// Writes the original incrementally; never materializes the whole video in RAM.
/// Partial files and files from a changed account are removed before returning.
Future<void> transferMediaToFile(
  ApiClient api,
  String url,
  File file, {
  required CancelToken cancelToken,
  ProgressCallback? onProgress,
}) async {
  final path = authenticatedMediaPath(url);
  final identity = await api.getMediaCacheIdentity();
  Dio? external;
  IOSink? sink;
  var complete = false;
  try {
    if (cancelToken.isCancelled) {
      throw cancelToken.cancelError!;
    }
    final options = Options(
      responseType: ResponseType.stream,
      followRedirects: false,
      maxRedirects: 0,
      headers: {'Accept-Encoding': 'identity'},
      receiveTimeout: const Duration(minutes: 5),
      extra: {if (path != null) 'private_media_no_redirect': true},
    );
    final Response<ResponseBody> response;
    if (path != null) {
      response = await api.getMediaTransfer<ResponseBody>(
        path,
        options: options,
        cancelToken: cancelToken,
      );
    } else {
      final uri = Uri.tryParse(url);
      if (uri == null || !{'https', 'http'}.contains(uri.scheme)) {
        throw StateError('Invalid media URL');
      }
      external = Dio();
      response = await external.get<ResponseBody>(
        url,
        options: options,
        cancelToken: cancelToken,
      );
    }
    if (response.statusCode != 200 || response.data == null) {
      throw StateError('Incomplete media response');
    }
    final total =
        int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
    var received = 0;
    sink = file.openWrite();
    await for (final chunk in response.data!.stream.timeout(
      const Duration(seconds: 45),
    )) {
      if (cancelToken.isCancelled) {
        throw cancelToken.cancelError!;
      }
      sink.add(chunk);
      // Flush each bounded chunk to apply back pressure to the network stream.
      await sink.flush();
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.close();
    sink = null;
    if (cancelToken.isCancelled) {
      throw cancelToken.cancelError!;
    }
    if (received == 0 || (total >= 0 && received != total)) {
      throw StateError('Incomplete media response');
    }
    if (await api.getMediaCacheIdentity() != identity) {
      throw StateError('Media session changed');
    }
    complete = true;
  } finally {
    await sink?.close();
    external?.close(force: true);
    if (!complete && await file.exists()) await file.delete();
  }
}

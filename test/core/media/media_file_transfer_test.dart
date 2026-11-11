import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/media/media_file_transfer.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';

class _StreamApi extends ApiClient {
  _StreamApi(this.chunks, {this.total = 6, this.status = 200});
  final Stream<Uint8List> chunks;
  final int total, status;
  String identity = 'account-A';
  Options? usedOptions;
  @override
  Future<String> getMediaCacheIdentity() async => identity;
  @override
  Future<Response<T>> getMediaTransfer<T>(
    String path, {
    Options? options,
    required CancelToken cancelToken,
  }) async {
    expect(path, '/uploads/video.mp4');
    usedOptions = options;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      headers: Headers.fromMap({
        'content-length': ['$total'],
      }),
      data: ResponseBody(chunks, status) as T,
    );
  }
}

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('2a-media-test-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Stream<Uint8List> chunks() => Stream.fromIterable([
    Uint8List.fromList([1, 2, 3]),
    Uint8List.fromList([4, 5, 6]),
  ]);
  test(
    'streams original with progress and authenticated no-redirect guard',
    () async {
      final api = _StreamApi(chunks());
      final file = File('${temp.path}/video.mp4');
      final progress = <int>[];
      await transferMediaToFile(
        api,
        '/uploads/video.mp4',
        file,
        cancelToken: CancelToken(),
        onProgress: (received, _) => progress.add(received),
      );
      expect(await file.readAsBytes(), [1, 2, 3, 4, 5, 6]);
      expect(progress, [3, 6]);
      expect(api.usedOptions?.responseType, ResponseType.stream);
      expect(api.usedOptions?.followRedirects, false);
      expect(api.usedOptions?.extra?['private_media_no_redirect'], true);
    },
  );
  test('cancellation deletes partially written original', () async {
    final api = _StreamApi(chunks());
    final file = File('${temp.path}/cancelled.mp4');
    final cancel = CancelToken();
    await expectLater(
      transferMediaToFile(
        api,
        '/uploads/video.mp4',
        file,
        cancelToken: cancel,
        onProgress: (_, _) => cancel.cancel(),
      ),
      throwsA(isA<DioException>()),
    );
    expect(await file.exists(), false);
  });
  test('changed account deletes exported original', () async {
    final api = _StreamApi(chunks());
    final file = File('${temp.path}/private.mp4');
    await expectLater(
      transferMediaToFile(
        api,
        '/uploads/video.mp4',
        file,
        cancelToken: CancelToken(),
        onProgress: (_, _) => api.identity = 'account-B',
      ),
      throwsStateError,
    );
    expect(await file.exists(), false);
  });
  test('truncated response cannot be exported as success', () async {
    final api = _StreamApi(chunks(), total: 12);
    final file = File('${temp.path}/truncated.mp4');
    await expectLater(
      transferMediaToFile(
        api,
        '/uploads/video.mp4',
        file,
        cancelToken: CancelToken(),
      ),
      throwsStateError,
    );
    expect(await file.exists(), false);
  });
  test('redirect response cannot be exported', () async {
    final api = _StreamApi(chunks(), status: 302);
    final file = File('${temp.path}/redirect.mp4');
    await expectLater(
      transferMediaToFile(
        api,
        '/uploads/video.mp4',
        file,
        cancelToken: CancelToken(),
      ),
      throwsStateError,
    );
    expect(await file.exists(), false);
  });
}

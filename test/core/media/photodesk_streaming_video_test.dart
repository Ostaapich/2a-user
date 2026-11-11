import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/media/authenticated_video.dart';
import 'package:twoalogisticcabineuser/src/core/network/api_client.dart';
import 'package:video_player/video_player.dart';

class _Api extends Fake implements ApiClient {
  var downloads = 0;
  @override
  Future<String?> getToken() async => 'private-account-token';
  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    downloads++;
    throw StateError('A native streaming video must not be downloaded');
  }
}

void main() {
  testWidgets(
    'native PhotoDesk MP4 uses authenticated network Range instead of full bytes or tempfile',
    (tester) async {
      final api = _Api();
      late BuildContext context;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final controller = await createAuthenticatedVideoController(
        context,
        '/uploads/photodesk-videos/PHOTODESK1/report-1/video-sha.mp4',
      );
      expect(controller.dataSourceType, DataSourceType.network);
      expect(
        controller.httpHeaders['Authorization'],
        'Bearer private-account-token',
      );
      expect(controller.httpHeaders['X-Warehouse-Protocol'], isNull);
      expect(controller.dataSource, contains('/api/uploads/photodesk-videos/'));
      expect(controller.dataSource, isNot(contains('private-account-token')));
      expect(api.downloads, 0);
      await controller.dispose();
    },
  );
}

@TestOn('browser')
library;

import 'package:dio/dio.dart';
import 'package:dio/browser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/core/network/media_http_adapter_web.dart';

const origin = String.fromEnvironment('MEDIA_REDIRECT_TEST_ORIGIN');
void main() {
  test(
    'browser rejects both redirects and sends credentials only to the initial origin',
    () async {
      if (origin.isEmpty) {
        fail('Run with test/fixtures/media_redirect_server.py');
      }
      final dio = Dio(
        BaseOptions(
          baseUrl: '$origin/api',
          headers: {'Authorization': 'Bearer fixture-test-only'},
        ),
      );
      dio.httpClientAdapter = StrictMediaBrowserAdapter(
        BrowserHttpClientAdapter(),
      );
      addTearDown(dio.close);
      final options = Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        maxRedirects: 0,
        extra: {'private_media_no_redirect': true},
      );
      final good = await dio.get<List<int>>('/good', options: options);
      expect(good.data, [1, 2, 3]);
      await expectLater(
        dio.get<List<int>>('/redirect-same', options: options),
        throwsA(isA<DioException>()),
      );
      await expectLater(
        dio.get<List<int>>('/redirect-cross', options: options),
        throwsA(isA<DioException>()),
      );
      final stats = await Dio().get<Map<String, dynamic>>('$origin/stats');
      expect(stats.data!['goodAuthorized'], true);
      expect(stats.data!['sameOriginSinkHits'], 0);
      expect(stats.data!['thirdPartyHits'], 0);
      expect(stats.data!['thirdPartyAuthorized'], false);
    },
  );
}

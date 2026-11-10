import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/custom_interceptor.dart';
import 'package:simple_live_core/src/common/http_client.dart';

class _PlaybackAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Map<String, dynamic> response = {
    'error': 0,
    'data': {
      'rtmp_url': 'https://cdn.example.test/live',
      'rtmp_live': 'stream.flv?expire=300&amp;token=private-stream-token',
      'rate': 0,
      'cdnsWithName': [
        {'cdn': 'test'}
      ],
      'multirates': [
        {'name': '原画', 'rate': 0}
      ],
    },
  };

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(response), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const cookie = 'dy_auth=private-session==; dy_did=paired-device; '
      'LTP0=private-passport-token; analytics=tracking';

  test('requires session plus device from the same imported cookie', () {
    expect(
        DouyuAccountCookies.parse('dy_auth=session').canUseForPlayback, false);
    expect(DouyuAccountCookies.parse('dy_did=device').canUseForPlayback, false);
    expect(
        DouyuAccountCookies.parse('LTP0=refresh; dy_did=device')
            .canUseForPlayback,
        false);
    final account = DouyuAccountCookies.parse(cookie);
    expect(account.canUseForPlayback, true);
    expect(account.deviceId, 'paired-device');
    expect(account.playbackCookie,
        'dy_auth=private-session==; dy_did=paired-device');
    expect(
        DouyuAccountCookies.parse('acf_jwt_token=jwt; acf_did=device')
            .canUseForPlayback,
        true);
  });

  test('rejects header injection without echoing the cookie', () {
    expect(() => DouyuAccountCookies.parse('$cookie\r\nInjected: yes'),
        throwsFormatException);
  });

  group('playback API identity', () {
    late Dio previous;
    late _PlaybackAdapter adapter;
    final logs = <String>[];
    final detail = LiveRoomDetail(
      roomId: '123',
      title: '',
      cover: '',
      userName: '',
      userAvatar: '',
      online: 0,
      status: true,
      url: 'https://www.douyu.com/123',
      data: 'sign=test',
    );

    setUp(() {
      previous = HttpClient.instance.dio;
      adapter = _PlaybackAdapter();
      HttpClient.instance.dio = Dio()..httpClientAdapter = adapter;
      HttpClient.instance.dio.interceptors.add(CustomInterceptor());
      logs.clear();
      CoreLog.enableLog = true;
      CoreLog.requestLogType = RequestLogType.all;
      CoreLog.onPrintLog = (_, message) => logs.add(message);
    });

    tearDown(() {
      HttpClient.instance.dio.close();
      HttpClient.instance.dio = previous;
      CoreLog.onPrintLog = null;
      CoreLog.requestLogType = RequestLogType.short;
    });

    test('uses login cookies for qualities and each CDN, keeps secrets private',
        () async {
      final site = DouyuSite()..cookie = cookie;
      final qualities = await site.getPlayQualites(detail: detail);
      final result =
          await site.getPlayUrls(detail: detail, quality: qualities.first);
      expect(adapter.requests, hasLength(2));
      for (final request in adapter.requests) {
        expect(request.uri.host, 'www.douyu.com');
        expect(request.headers['Cookie'],
            'dy_auth=private-session==; dy_did=paired-device');
      }
      // CDN playback does not need the user's login secrets.
      expect(result.headers, isNull);
      expect(result.urls.single,
          'https://cdn.example.test/live/stream.flv?expire=300&token=private-stream-token');
      final output = logs.join('\n');
      expect(output, contains('sessionSupplied=true'));
      expect(output, contains('expire=300'));
      expect(output, isNot(contains('private-session')));
      expect(output, isNot(contains('private-passport-token')));
      expect(output, isNot(contains('private-stream-token')));
    });

    test('clearing identity restores guest requests', () async {
      final site = DouyuSite()..cookie = cookie;
      site.cookie = '';
      await site.getPlayUrl('123', 'sign=test', 0, 'test');
      expect(adapter.requests.single.headers.containsKey('Cookie'), false);
      expect(logs.join('\n'), contains('sessionSupplied=false'));
    });

    test('accepts absolute stream URLs without adding a duplicate host',
        () async {
      adapter.response['data']['rtmp_live'] =
          'https://cdn.example.test/live.flv';
      final url = await DouyuSite().getPlayUrl('123', 'sign=test', 0, 'test');
      expect(url, 'https://cdn.example.test/live.flv');
    });

    test('rejects expired/rejected sessions without exposing private response',
        () async {
      adapter.response = {'error': -1, 'msg': 'private-response'};
      final site = DouyuSite()..cookie = cookie;
      await expectLater(
          site.getPlayUrl('123', 'sign=test', 0, 'test'),
          throwsA(predicate(
              (error) => !error.toString().contains('private-response'))));
      expect(logs.join('\n'), isNot(contains('private-response')));
    });
  });
}

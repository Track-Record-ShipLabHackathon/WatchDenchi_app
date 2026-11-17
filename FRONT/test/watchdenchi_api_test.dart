import 'dart:convert';

import 'package:battery_app/services/watchdenchi_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('anonymous client creation retains token for next requests', () async {
    final api = WatchDenchiApi(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/client');
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response('{"access_token":"test-token"}', 201);
      }),
    );
    expect(await api.createAnonymousClient(), 'test-token');
    expect(api.accessToken, 'test-token');
  });

  test('battery registration sends expected JSON and bearer token', () async {
    final api = WatchDenchiApi(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/battery');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(jsonDecode(request.body), {
          'type': '単3形',
          'manufacturer': 'Panasonic',
          'quantity': 3,
          'storage_location': 'リビング',
        });
        return http.Response('', 201);
      }),
    )..setAccessToken('test-token');

    await api.registerBattery(const BatteryCreateRequest(
      type: '単3形',
      manufacturer: 'Panasonic',
      quantity: 3,
      storageLocation: 'リビング',
    ));
  });

  test('battery list decodes Go array response', () async {
    final api = WatchDenchiApi(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/battery');
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode([
            {
              'id': 7,
              'type': '単4形',
              'manufacturer': 'maxell',
              'quantity': 2,
              'storage_location': '引き出し',
            }
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..setAccessToken('test-token');

    final batteries = await api.getBatteries();
    expect(batteries, hasLength(1));
    expect(batteries.single.id, 7);
    expect(batteries.single.type, '単4形');
    expect(batteries.single.quantity, 2);
    expect(batteries.single.storageLocation, '引き出し');
  });

  test('expired or invalid authorization is not silently accepted', () async {
    final api = WatchDenchiApi(
      baseUrl: 'https://example.test',
      client: MockClient((_) async => http.Response('unauthorized', 401)),
    )..setAccessToken('wrong-token');

    await expectLater(
      api.getBatteries(),
      throwsA(isA<WatchDenchiApiException>().having(
        (e) => e.statusCode,
        'statusCode',
        401,
      )),
    );
  });
}

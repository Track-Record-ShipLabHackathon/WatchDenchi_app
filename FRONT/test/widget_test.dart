import 'dart:convert';

import 'package:battery_app/services/watchdenchi_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('anonymous auth token is returned', () async {
    final api = WatchDenchiApi(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/client');
        expect(request.headers.containsKey('Authorization'), false);
        return http.Response('{"access_token":"mock-token"}', 201);
      }),
    );
    expect(await api.createAnonymousClient(), 'mock-token');
    expect(api.accessToken, 'mock-token');
  });

  test('register battery sends token and chemical as agreed', () async {
    final api = WatchDenchiApi(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/battery');
        expect(request.headers['Authorization'], 'Bearer mock-token');
        expect(jsonDecode(request.body), {
          'type': '単3形',
          'manufacturer': 'Panasonic',
          'quantity': 3,
          'storage_location': '引き出し',
          'chemical': 'アルカリ',
        });
        return http.Response('', 201);
      }),
    )..setAccessToken('mock-token');
    await api.registerBattery(const BatteryCreateRequest(
      type: '単3形',
      manufacturer: 'Panasonic',
      quantity: 3,
      storageLocation: '引き出し',
      chemical: 'アルカリ',
    ));
  });

  test('list batteries preserves DB id and chemical', () async {
    final api = WatchDenchiApi(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/battery');
        expect(request.headers['Authorization'], 'Bearer mock-token');
        return http.Response(jsonEncode([{
          'id': 17,
          'type': '単4形',
          'manufacturer': 'maxell',
          'quantity': 2,
          'storage_location': '机',
          'chemical': 'アルカリ',
          'registered_at': '2026-11-19T08:00:00Z',
        }]), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    )..setAccessToken('mock-token');
    final battery = (await api.getBatteries()).single;
    expect(battery.id, 17);
    expect(battery.chemical, 'アルカリ');
  });

  test('401 must not be silently handled as success', () async {
    final api = WatchDenchiApi(
      baseUrl: 'https://example.test',
      client: MockClient((_) async => http.Response('unauthorized', 401)),
    )..setAccessToken('invalid');
    await expectLater(api.getBatteries(), throwsA(
      isA<WatchDenchiApiException>().having(
        (e) => e.statusCode, 'statusCode', 401)));
  });
}

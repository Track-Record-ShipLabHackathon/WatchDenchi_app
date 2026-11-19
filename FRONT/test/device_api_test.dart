import 'dart:convert';
import 'package:battery_app/main.dart';
import 'package:battery_app/services/watchdenchi_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('device creation, install and replacement keep the agreed IDs and empty responses', () async {
    final seen = <String>[];
    final api = WatchDenchiApi(
      baseUrl: 'https://example.test',
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer mock-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('client_id'), false);
        seen.add(request.method + ' ' + request.url.path);
        if (request.url.path == '/api/device') {
          expect(body, {'type': 'マウス', 'name': '作業用マウス'});
          return http.Response('{"id":10}', 201);
        }
        if (request.method == 'POST') {
          expect(body, {'device_id':10, 'battery_id':20, 'battery_quantity':1});
          return http.Response('', 201);
        }
        expect(request.method, 'PATCH');
        expect(body, {'id':30, 'battery_id':21});
        return http.Response('', 204);
      }),
    )..setAccessToken('mock-token');
    final device = await api.createDevice(type:'マウス', name:'作業用マウス');
    await api.installDeviceBattery(deviceId:device['id'] as int,
      batteryId:20, batteryQuantity:1);
    await api.replaceDeviceBattery(id:30, batteryId:21);
    expect(seen, ['POST /api/device', 'POST /api/device-battery', 'PATCH /api/device-battery']);
  });

  test('server usage maps DB identifiers and prediction to the screen model', () {
    final usage = DeviceUsage.fromServer({
      'id':30, 'device_id':10, 'device_name':'作業用マウス',
      'device_type':'マウス', 'battery_id':20, 'battery_type':'単3形',
      'manufacturer':'テスト', 'battery_quantity':1,
      'started_at':'2026-11-19T09:00:00Z',
      'recommended_replacement_date':'2028-07-23',
    });
    expect(usage.id,30);
    expect(usage.deviceId,10);
    expect(usage.batteryId,20);
    expect(usage.type,'単3形');
    expect(usage.iconKey,'mouse');
    expect(usage.recommendedReplacementDate,'2028-07-23');
  });

  test('prediction lookup uses device_battery_id and returns the saved date', () async {
    final api = WatchDenchiApi(baseUrl:'https://example.test',
      client:MockClient((request) async {
        expect(request.url.queryParameters, {'device_battery_id':'30'});
        return http.Response('{"device_battery_id":30,"recommended_replacement_date":"2028-07-23"}',200);
      }))..setAccessToken('mock-token');
    expect(await api.getPrediction(30),'2028-07-23');
  });

  test('failed mutation reports the backend message and is never retried', () async {
    var attempts = 0;
    final api = WatchDenchiApi(baseUrl:'https://example.test',
      client:MockClient((request) async {
        attempts++;
        return http.Response('{"error":{"code":"insufficient_stock","message":"stock unavailable"}}',409);
      }))..setAccessToken('mock-token');
    await expectLater(api.replaceDeviceBattery(id:30,batteryId:21),
      throwsA(isA<WatchDenchiApiException>()
        .having((e)=>e.statusCode,'status',409)
        .having((e)=>e.message,'message','stock unavailable')));
    expect(attempts,1);
  });

  test('battery registration accepts an unspecified storage location', () async {
    final api = WatchDenchiApi(baseUrl:'https://example.test',
      client:MockClient((request) async {
        expect(jsonDecode(request.body)['storage_location'],'');
        return http.Response('',201);
      }))..setAccessToken('mock-token');
    await api.registerBattery(const BatteryCreateRequest(type:'単3形',
      manufacturer:'テスト',quantity:3,storageLocation:'',chemical:'アルカリ'));
  });
}

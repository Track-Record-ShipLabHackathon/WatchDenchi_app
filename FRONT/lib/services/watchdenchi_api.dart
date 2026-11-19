import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// テスト時のGo API。URLはflutter build/runの--dart-defineで指定。
const watchDenchiApiBaseUrl = String.fromEnvironment(
  'WATCHDENCHI_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8080',
);

/// 現在のGo POST /api/batteryに合わせた項目＋新設予定のchemical。
/// 現行GoはchemicalをまだDBに保存しない。UI側で警告して試験する。
class BatteryCreateRequest {
  const BatteryCreateRequest({
    required this.type,
    required this.manufacturer,
    required this.quantity,
    required this.storageLocation,
    required this.chemical,
  });

  final String type;
  final String manufacturer;
  final int quantity;
  final String storageLocation;
  final String chemical;

  Map<String, dynamic> toJson() => {
        'type': type,
        'manufacturer': manufacturer,
        'quantity': quantity,
        'storage_location': storageLocation,
        'chemical': chemical,
      };
}

class BatteryApiItem {
  const BatteryApiItem({
    required this.id,
    required this.type,
    required this.manufacturer,
    required this.quantity,
    required this.storageLocation,
    this.chemical,
  });

  final int id; // BATTERYのPK。後の使用・交換フローで必要。
  final String type;
  final String manufacturer;
  final int quantity;
  final String storageLocation;
  final String? chemical;

  factory BatteryApiItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final quantity = json['quantity'];
    final type = json['type'];
    final manufacturer = json['manufacturer'];
    final storageLocation = json['storage_location'];
    if (id is! int ||
        quantity is! int ||
        type is! String ||
        manufacturer is! String ||
        storageLocation is! String) {
      throw const FormatException('Goの電池一覧のレスポンス形式が一致しません');
    }
    // Go側は新仕様でchemicalを返す予定。旧仕様のchemistryとも互換。
    final chemical = json['chemical'] ?? json['chemistry'];
    return BatteryApiItem(
      id: id,
      type: type,
      manufacturer: manufacturer,
      quantity: quantity,
      storageLocation: storageLocation,
      chemical: chemical is String ? chemical : null,
    );
  }
}

class WatchDenchiApiException implements Exception {
  const WatchDenchiApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => statusCode == null
      ? 'WatchDenchiApiException: $message'
      : 'WatchDenchiApiException($statusCode): $message';
}

/// 匿名トークンを各認証APIのAuthorizationに付与する通信クラス。
/// Flutterからclient_idを渡さず、Goでトークンからclient_idを特定する。
class WatchDenchiApi {
  WatchDenchiApi({
    http.Client? client,
    String baseUrl = watchDenchiApiBaseUrl,
    Duration timeout = const Duration(seconds: 8),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _timeout = timeout;

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final Duration _timeout;
  String? _accessToken;

  void setAccessToken(String? token) => _accessToken = token;
  String? get accessToken => _accessToken;
  void close() { if (_ownsClient) _client.close(); }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> _headers({bool authenticated = true}) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        if (authenticated && _accessToken != null)
          'Authorization': 'Bearer $_accessToken',
      };

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    if (authenticated && _accessToken == null) {
      throw const WatchDenchiApiException(
        'サーバー認証が完了していません。匿名認証を先に実行してください',
      );
    }
    try {
      final http.Response response;
      if (method == 'GET') {
        response = await _client.get(_uri(path),
          headers: _headers(authenticated: authenticated)).timeout(_timeout);
      } else if (method == 'POST') {
        response = await _client.post(_uri(path),
          headers: _headers(authenticated: authenticated),
          body: body == null ? null : jsonEncode(body)).timeout(_timeout);
      } else {
        throw ArgumentError.value(method, 'method', 'GET/POSTのみ対応');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw WatchDenchiApiException('Go APIからエラーが返りました',
          statusCode: response.statusCode);
      }
      return response;
    } on TimeoutException {
      throw const WatchDenchiApiException('Go APIへの接続がタイムアウトしました');
    } on http.ClientException {
      throw const WatchDenchiApiException('Go APIに接続できませんでした');
    }
  }

  Future<void> checkHealth() async {
    await _send('GET', '/healthz', authenticated: false);
  }

  /// 初回のみ作成。以後はanonymous_session.dartに保存されたトークンを使う。
  Future<String> createAnonymousClient() async {
    final response = await _send('POST', '/api/client', authenticated: false);
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map || data['access_token'] is! String) {
        throw const FormatException('access_tokenがありません');
      }
      final token = data['access_token'] as String;
      if (token.isEmpty) throw const FormatException('access_tokenが空です');
      setAccessToken(token);
      return token;
    } on FormatException {
      throw const WatchDenchiApiException('Goの匿名認証レスポンスが不正です');
    }
  }

  Future<List<BatteryApiItem>> getBatteries() async {
    final response = await _send('GET', '/api/battery');
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final dynamic items = decoded is List ? decoded :
        decoded is Map<String,dynamic> ? decoded['batteries'] : null;
      if (items is! List) throw const FormatException('電池一覧が配列ではありません');
      return items.map((item) {
        if (item is! Map) throw const FormatException('電池のレコード形式が不正です');
        return BatteryApiItem.fromJson(Map<String, dynamic>.from(item));
      }).toList(growable: false);
    } on FormatException {
      throw const WatchDenchiApiException('Goの電池一覧の形式が不正です');
    } on TypeError {
      throw const WatchDenchiApiException('Goの電池一覧に型の不一致があります');
    }
  }

  /// 二重登録防止のため、失敗しても自動リトライしない。
  Future<void> registerBattery(BatteryCreateRequest request) async {
    if (request.type.trim().isEmpty ||
        request.manufacturer.trim().isEmpty ||
        request.quantity < 1 ||
        request.storageLocation.trim().isEmpty ||
        request.chemical.trim().isEmpty) {
      throw const FormatException('登録する電池情報が不正です');
    }
    await _send('POST', '/api/battery', body: request.toJson());
  }
}

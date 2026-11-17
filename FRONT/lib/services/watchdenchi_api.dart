import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

// Go側のAPI契約が確定したら、まずこのファイルだけ変更します。
// 今は現行の画面から呼び出していないので、端末内保存の動作は変わりません。
const watchDenchiApiBaseUrl = String.fromEnvironment(
  'WATCHDENCHI_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8080',
);

/// サーバーに登録する電池情報。JSONキーはエレナと合意前の「仮仕様」です。
class BatteryCreateRequest {
  const BatteryCreateRequest({
    required this.type,
    required this.manufacturer,
    required this.quantity,
    required this.storageLocation,
  });

  final String type;
  final String manufacturer;
  final int quantity;
  final String storageLocation;

  Map<String, dynamic> toJson() => {
        'type': type,
        'manufacturer': manufacturer,
        'quantity': quantity,
        'storage_location': storageLocation,
      };
}

/// バッテリーのAPI返却データ。使用/移動を行うにはDB上のIDが必要です。
class BatteryApiItem {
  const BatteryApiItem({
    required this.id,
    required this.type,
    required this.manufacturer,
    required this.quantity,
    required this.storageLocation,
    this.chemistry,
  });

  final int id;
  final String type;
  final String manufacturer;
  final int quantity;
  final String storageLocation;
  final String? chemistry;

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
      throw const FormatException('電池一覧のJSON形式が仮仕様と一致しません');
    }
    return BatteryApiItem(
      id: id,
      type: type,
      manufacturer: manufacturer,
      quantity: quantity,
      storageLocation: storageLocation,
      chemistry: json['chemistry'] is String
          ? json['chemistry'] as String
          : null,
    );
  }
}

/// ネットワーク失敗やHTTPエラーをUI側で区別して扱うための例外。
class WatchDenchiApiException implements Exception {
  const WatchDenchiApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'WatchDenchiApiException: $message'
      : 'WatchDenchiApiException($statusCode): $message';
}

/// 画面から独立したGo APIの通信担当。実際のサーバーはまだ不要です。
///
/// - http.Clientを注入でき、MockClientで通信テストできます。
/// - POSTは自動再送しません（電池が二重登録されるのを防ぐため）。
/// - 認証トークンはメモリ上だけ。永続化方法はエレナと決定後に実装。
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

  void setAccessToken(String? token) {
    _accessToken = token;
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  String? get accessToken => _accessToken;

  Map<String, String> _headers({bool authenticated = true}) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        // Bearerヘッダー方式も仮仕様（要合意）。
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
    late http.Response response;
    try {
      if (method == 'GET') {
        response = await _client
            .get(_uri(path), headers: _headers(authenticated: authenticated))
            .timeout(_timeout);
      } else if (method == 'POST') {
        response = await _client
            .post(
              _uri(path),
              headers: _headers(authenticated: authenticated),
              // bodyがnullならHTTPの空ボディ。null JSONではありません。
              body: body == null ? null : jsonEncode(body),
            )
            .timeout(_timeout);
      } else {
        throw ArgumentError.value(method, 'method', 'GET/POSTのみ対応');
      }
    } on TimeoutException {
      throw const WatchDenchiApiException('サーバーへの接続がタイムアウトしました');
    } on http.ClientException {
      throw const WatchDenchiApiException('サーバーへ接続できませんでした');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // 401/403/409/500等を成功として処理しない。詳細文は合意後に追加。
      throw WatchDenchiApiException(
        'サーバーからエラーが返りました',
        statusCode: response.statusCode,
      );
    }
    return response;
  }

  /// Goの稼働確認。GET /healthz は既にGitHubにコードがあります。
  Future<void> checkHealth() async {
    await _send('GET', '/healthz', authenticated: false);
  }

  /// POST /api/client: {"access_token": "..."} はレスポンスの仮仕様。
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
      throw const WatchDenchiApiException('認証レスポンスの形式が仮仕様と一致しません');
    }
  }

  /// GET /api/battery。仮仕様としてJSON配列または {"batteries": [...]} を受け付ける。
  Future<List<BatteryApiItem>> getBatteries() async {
    final response = await _send('GET', '/api/battery');
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final dynamic items = decoded is List
          ? decoded
          : decoded is Map<String, dynamic>
              ? decoded['batteries']
              : null;
      if (items is! List) throw const FormatException('一覧が配列ではありません');
      return items.map((item) {
        if (item is! Map) throw const FormatException('不正な電池データです');
        return BatteryApiItem.fromJson(Map<String, dynamic>.from(item));
      }).toList(growable: false);
    } on FormatException {
      throw const WatchDenchiApiException('電池一覧のJSON形式が仮仕様と一致しません');
    } on TypeError {
      throw const WatchDenchiApiException('電池一覧のデータ型が正しくありません');
    }
  }

  /// POST /api/battery。設計書の応答はNULLなので、2xxなら成功とする。
  Future<void> registerBattery(BatteryCreateRequest draft) async {
    if (draft.type.trim().isEmpty ||
        draft.manufacturer.trim().isEmpty ||
        draft.quantity <= 0 ||
        draft.storageLocation.trim().isEmpty) {
      throw const FormatException('登録する電池情報が不正です');
    }
    await _send('POST', '/api/battery', body: draft.toJson());
  }
}

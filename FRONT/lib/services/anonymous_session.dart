import 'package:shared_preferences/shared_preferences.dart';

import 'watchdenchi_api.dart';

/// 匿名認証はGoサーバーが発行するトークンを利用する。
/// 端末で生成した乱数を「本人確認済みのID」として扱わない。
///
/// 本番公開前に、SharedPreferencesから安全なトークン保存方法へ変更する。
/// SharedPreferencesはWebでの秘密情報の保護を保証しない。
class AnonymousSession {
  AnonymousSession({
    required this.api,
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const String tokenKey = 'watchdenchi_server_access_token_v1';

  final WatchDenchiApi api;
  final SharedPreferencesAsync _preferences;
  Future<String>? _ongoing;

  /// 保存済みトークンを再利用。なければPOST /api/clientを一度呼ぶ。
  /// 通信エラーは呼び出し側に返し、偽のトークンは発行しない。
  Future<String> restoreOrCreate() {
    final active = _ongoing;
    if (active != null) return active;
    final result = _restoreOrCreate();
    _ongoing = result;
    result.then<void>((_) => _ongoing = null,
        onError: (Object _, StackTrace __) => _ongoing = null);
    return result;
  }

  Future<String> _restoreOrCreate() async {
    final stored = await _preferences.getString(tokenKey);
    if (stored != null && stored.trim().isNotEmpty) {
      api.setAccessToken(stored);
      return stored;
    }

    final token = await api.createAnonymousClient();
    if (token.trim().isEmpty) {
      throw const WatchDenchiApiException('匿名認証トークンが空です');
    }
    try {
      await _preferences.setString(tokenKey, token);
    } catch (_) {
      api.setAccessToken(null);
      rethrow;
    }
    return token;
  }

  /// トークン無効(401など)を正式に確認した場合に限り呼び出す。
  Future<void> clearSavedToken() async {
    await _preferences.remove(tokenKey);
    api.setAccessToken(null);
  }
}

/// Go側のAPIが公開されるまでfalseで、ローカル保存のアプリは従来通り動く。
/// trueにする場合はWATCHDENCHI_API_BASE_URLも合わせて設定する。
const bool enableServerAnonymousAuth = bool.fromEnvironment(
  'WATCHDENCHI_ENABLE_SERVER_AUTH',
  defaultValue: false,
);

/// 画面間でAPIを再利用。将来の在庫同期でも同じトークンを使う。
class WatchDenchiServerServices {
  WatchDenchiServerServices._();
  static final WatchDenchiApi api = WatchDenchiApi();
  static final AnonymousSession auth = AnonymousSession(api: api);
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TraktException implements Exception {
  TraktException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TraktDeviceCode {
  TraktDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.interval,
  });
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int expiresIn;
  final int interval;
}

class TraktResponse {
  TraktResponse(this.status, {this.retryAfter});
  final int status;
  final int? retryAfter;
}

/// 播放目标(电影 / 剧集)在 Trakt 上的身份。
class ScrobbleTarget {
  ScrobbleTarget._({
    required this.kind,
    this.ids = const {},
    this.showIds,
    this.season,
    this.number,
  });

  /// 'movie' | 'episode'
  final String kind;

  /// 电影 ID,或单集自身的 ID
  final Map<String, dynamic> ids;

  /// 剧集用「剧 ID + 季 + 集」定位时的剧 ID
  final Map<String, dynamic>? showIds;
  final int? season;
  final int? number;

  static Map<String, dynamic> _ids(Map<String, String> p, {bool tvdb = false}) {
    final out = <String, dynamic>{};
    final imdb = p['imdb'];
    if (imdb != null && imdb.startsWith('tt')) out['imdb'] = imdb;
    final tmdb = int.tryParse(p['tmdb'] ?? '');
    if (tmdb != null) out['tmdb'] = tmdb;
    if (tvdb) {
      final t = int.tryParse(p['tvdb'] ?? '');
      if (t != null) out['tvdb'] = t;
    }
    return out;
  }

  static ScrobbleTarget? forMovie(Map<String, String> providerIds) {
    final ids = _ids(providerIds);
    if (ids.isEmpty) return null;
    return ScrobbleTarget._(kind: 'movie', ids: ids);
  }

  /// 优先用「剧 ID + 季集号」(与 Emby 官方 Trakt 插件一致),缺失时退回单集自身 ID。
  static ScrobbleTarget? forEpisode({
    required Map<String, String> episodeIds,
    Map<String, String>? showProviderIds,
    int? season,
    int? number,
  }) {
    final showIds = showProviderIds == null ? <String, dynamic>{} : _ids(showProviderIds, tvdb: true);
    if (showIds.isNotEmpty && season != null && number != null) {
      return ScrobbleTarget._(kind: 'episode', showIds: showIds, season: season, number: number);
    }
    final ids = _ids(episodeIds, tvdb: true);
    if (ids.isEmpty) return null;
    return ScrobbleTarget._(kind: 'episode', ids: ids);
  }

  Map<String, dynamic> toBody(double progress) {
    final p = double.parse(progress.clamp(0.0, 100.0).toStringAsFixed(2));
    if (kind == 'movie') {
      return {
        'movie': {'ids': ids},
        'progress': p,
      };
    }
    if (showIds != null) {
      return {
        'show': {'ids': showIds},
        'episode': {'season': season, 'number': number},
        'progress': p,
      };
    }
    return {
      'episode': {'ids': ids},
      'progress': p,
    };
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'ids': ids,
        'showIds': showIds,
        'season': season,
        'number': number,
      };

  factory ScrobbleTarget.fromJson(Map<String, dynamic> j) => ScrobbleTarget._(
        kind: j['kind'] as String,
        ids: Map<String, dynamic>.from((j['ids'] as Map?) ?? const {}),
        showIds: j['showIds'] == null ? null : Map<String, dynamic>.from(j['showIds'] as Map),
        season: (j['season'] as num?)?.toInt(),
        number: (j['number'] as num?)?.toInt(),
      );
}

class TraktService extends ChangeNotifier {
  TraktService(this.prefs) {
    clientId = prefs.getString('trakt.clientId') ?? '';
    clientSecret = prefs.getString('trakt.clientSecret') ?? '';
    username = prefs.getString('trakt.username');
    final raw = prefs.getString('trakt.tokens');
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _access = j['access'] as String?;
        _refresh = j['refresh'] as String?;
        _expiresAt = DateTime.fromMillisecondsSinceEpoch(j['expiresAt'] as int);
      } catch (_) {}
    }
  }

  final SharedPreferences prefs;
  static const _api = 'https://api.trakt.tv';
  static const _redirect = 'urn:ietf:wg:oauth:2.0:oob';
  final http.Client _http = http.Client();

  String clientId = '';
  String clientSecret = '';
  String? username;
  String? _access;
  String? _refresh;
  DateTime? _expiresAt;

  /// 最近的请求记录,设置页可查看,用来确认「没有多发请求」
  final ValueNotifier<List<String>> log = ValueNotifier<List<String>>(const <String>[]);

  bool get configured => clientId.isNotEmpty && clientSecret.isNotEmpty;
  bool get connected => _access != null;

  void _log(String line) {
    final t = DateTime.now();
    final ts = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
    final next = ['$ts  $line', ...log.value];
    log.value = next.length > 60 ? next.sublist(0, 60) : next;
  }

  Future<void> saveCredentials(String id, String secret) async {
    clientId = id.trim();
    clientSecret = secret.trim();
    await prefs.setString('trakt.clientId', clientId);
    await prefs.setString('trakt.clientSecret', clientSecret);
    notifyListeners();
  }

  Map<String, String> _headers({bool auth = true}) => {
        'Content-Type': 'application/json',
        'trakt-api-version': '2',
        'trakt-api-key': clientId,
        'User-Agent': 'EmbyPlayer/0.1.0',
        if (auth && _access != null) 'Authorization': 'Bearer $_access',
      };

  // ───────────────────────── 授权(Device Code)─────────────────────────

  Future<TraktDeviceCode> requestDeviceCode() async {
    if (!configured) throw TraktException('请先填写 Trakt Client ID 和 Client Secret');
    final res = await _http
        .post(Uri.parse('$_api/oauth/device/code'),
            headers: _headers(auth: false), body: jsonEncode({'client_id': clientId}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw TraktException('获取授权码失败(HTTP ${res.statusCode}),请检查 Client ID');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return TraktDeviceCode(
      deviceCode: j['device_code'] as String,
      userCode: j['user_code'] as String,
      verificationUrl: j['verification_url'] as String,
      expiresIn: (j['expires_in'] as num).toInt(),
      interval: (j['interval'] as num).toInt(),
    );
  }

  /// 轮询授权结果。用户完成授权返回 true;被取消返回 false;失败抛出 [TraktException]。
  Future<bool> pollForToken(TraktDeviceCode c, bool Function() cancelled) async {
    var interval = c.interval;
    final deadline = DateTime.now().add(Duration(seconds: c.expiresIn));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(Duration(seconds: interval));
      if (cancelled()) return false;
      try {
        final res = await _http
            .post(Uri.parse('$_api/oauth/device/token'),
                headers: _headers(auth: false),
                body: jsonEncode({
                  'code': c.deviceCode,
                  'client_id': clientId,
                  'client_secret': clientSecret,
                }))
            .timeout(const Duration(seconds: 15));
        switch (res.statusCode) {
          case 200:
            await _storeTokens(jsonDecode(res.body) as Map<String, dynamic>);
            await _loadProfile();
            _log('已连接 Trakt 账号 ${username ?? ''}');
            notifyListeners();
            return true;
          case 400: // 用户还没授权,继续等
            break;
          case 429: // 轮询过快
            interval += 1;
            break;
          case 404:
            throw TraktException('授权码无效');
          case 409:
            throw TraktException('该授权码已被使用');
          case 410:
            throw TraktException('授权码已过期,请重新连接');
          case 418:
            throw TraktException('你拒绝了授权');
          default:
            break;
        }
      } on TraktException {
        rethrow;
      } catch (_) {
        // 网络抖动,下一轮继续
      }
    }
    throw TraktException('授权超时,请重新连接');
  }

  Future<void> _storeTokens(Map<String, dynamic> j) async {
    _access = j['access_token'] as String;
    _refresh = j['refresh_token'] as String;
    final created = (j['created_at'] as num?)?.toInt() ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final expiresIn = (j['expires_in'] as num?)?.toInt() ?? 7776000;
    _expiresAt = DateTime.fromMillisecondsSinceEpoch((created + expiresIn) * 1000);
    await prefs.setString(
      'trakt.tokens',
      jsonEncode({
        'access': _access,
        'refresh': _refresh,
        'expiresAt': _expiresAt!.millisecondsSinceEpoch,
      }),
    );
  }

  Future<void> _loadProfile() async {
    try {
      final res = await _http
          .get(Uri.parse('$_api/users/settings'), headers: _headers())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        username = (j['user'] as Map?)?['username'] as String?;
        if (username != null) await prefs.setString('trakt.username', username!);
      }
    } catch (_) {}
  }

  /// 令牌剩余不足一天时刷新(Trakt 令牌有效期 3 个月)。
  Future<void> ensureFreshToken() async {
    final exp = _expiresAt;
    if (_access == null || exp == null) return;
    if (exp.difference(DateTime.now()) < const Duration(days: 1)) {
      await refresh();
    }
  }

  Future<bool> refresh() async {
    if (_refresh == null || !configured) return false;
    try {
      final res = await _http
          .post(Uri.parse('$_api/oauth/token'),
              headers: _headers(auth: false),
              body: jsonEncode({
                'refresh_token': _refresh,
                'client_id': clientId,
                'client_secret': clientSecret,
                'redirect_uri': _redirect,
                'grant_type': 'refresh_token',
              }))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        await _storeTokens(jsonDecode(res.body) as Map<String, dynamic>);
        _log('令牌已刷新');
        return true;
      }
      _log('令牌刷新失败 HTTP ${res.statusCode}');
    } catch (e) {
      _log('令牌刷新出错:$e');
    }
    return false;
  }

  Future<void> disconnect() async {
    if (_access != null) {
      try {
        await _http
            .post(Uri.parse('$_api/oauth/revoke'),
                headers: _headers(auth: false),
                body: jsonEncode({'token': _access, 'client_id': clientId, 'client_secret': clientSecret}))
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
    }
    _access = null;
    _refresh = null;
    _expiresAt = null;
    username = null;
    await prefs.remove('trakt.tokens');
    await prefs.remove('trakt.username');
    _log('已断开 Trakt');
    notifyListeners();
  }

  // ───────────────────────── Scrobble ─────────────────────────

  /// 发送一次 scrobble。网络异常会向上抛出,由调用方决定是否落入离线队列。
  Future<TraktResponse> scrobble(String action, Map<String, dynamic> body) async {
    final res = await _http
        .post(Uri.parse('$_api/scrobble/$action'), headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    final progress = body['progress'];
    _log('POST /scrobble/$action  ${res.statusCode}  ($progress%)');
    final ra = int.tryParse(res.headers['retry-after'] ?? '');
    return TraktResponse(res.statusCode, retryAfter: ra);
  }

  // ───────────────────────── 离线补录 ─────────────────────────

  static const _pendingKey = 'trakt.pendingHistory';

  List<Map<String, dynamic>> _readPending() {
    final raw = prefs.getStringList(_pendingKey) ?? const [];
    final out = <Map<String, dynamic>>[];
    for (final s in raw) {
      try {
        out.add(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {}
    }
    return out;
  }

  /// 网络失败且已看完(≥80%)的条目,存下来之后用 /sync/history 补录。
  Future<void> addPendingHistory(ScrobbleTarget target, DateTime watchedAt) async {
    final list = prefs.getStringList(_pendingKey) ?? <String>[];
    list.add(jsonEncode({'t': target.toJson(), 'at': watchedAt.toUtc().toIso8601String()}));
    await prefs.setStringList(_pendingKey, list.length > 200 ? list.sublist(list.length - 200) : list);
    _log('网络不可用,已暂存一条观看记录,稍后补录');
  }

  int get pendingCount => (prefs.getStringList(_pendingKey) ?? const []).length;

  Future<void> flushPending() async {
    if (!connected) return;
    final pending = _readPending();
    if (pending.isEmpty) return;

    final movies = <Map<String, dynamic>>[];
    final episodes = <Map<String, dynamic>>[];
    final shows = <Map<String, dynamic>>[];
    for (final p in pending) {
      final t = ScrobbleTarget.fromJson(Map<String, dynamic>.from(p['t'] as Map));
      final at = p['at'] as String;
      if (t.kind == 'movie') {
        movies.add({'watched_at': at, 'ids': t.ids});
      } else if (t.showIds != null) {
        shows.add({
          'ids': t.showIds,
          'seasons': [
            {
              'number': t.season,
              'episodes': [
                {'number': t.number, 'watched_at': at},
              ],
            },
          ],
        });
      } else {
        episodes.add({'watched_at': at, 'ids': t.ids});
      }
    }

    try {
      await ensureFreshToken();
      final res = await _http
          .post(Uri.parse('$_api/sync/history'),
              headers: _headers(),
              body: jsonEncode({
                if (movies.isNotEmpty) 'movies': movies,
                if (episodes.isNotEmpty) 'episodes': episodes,
                if (shows.isNotEmpty) 'shows': shows,
              }))
          .timeout(const Duration(seconds: 20));
      _log('POST /sync/history  ${res.statusCode}  (补录 ${pending.length} 条)');
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await prefs.remove(_pendingKey);
      }
    } catch (_) {
      // 保留在本地,下次启动再试
    }
  }
}

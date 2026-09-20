import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/emby_client.dart';
import '../services/ratings_service.dart';
import '../services/trakt_scrobbler.dart';
import '../services/trakt_service.dart';

class AppState extends ChangeNotifier {
  AppState._(this.prefs);

  final SharedPreferences prefs;
  late final String deviceId;
  late final TraktService trakt;
  late final TraktScrobbler scrobbler;
  late final RatingsService ratings;

  EmbyClient? emby;

  /// 每次播放结束 +1,首页据此刷新「继续观看」。
  final ValueNotifier<int> playbackRevision = ValueNotifier(0);

  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = AppState._(prefs);
    await s._init();
    return s;
  }

  Future<void> _init() async {
    var id = prefs.getString('deviceId');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('deviceId', id);
    }
    deviceId = id;

    trakt = TraktService(prefs);
    scrobbler = TraktScrobbler(trakt);
    ratings = RatingsService(prefs)..apiKey = prefs.getString('mdblist.key');

    final server = prefs.getString('emby.server');
    final token = prefs.getString('emby.token');
    final userId = prefs.getString('emby.userId');
    if (server != null && token != null && userId != null) {
      emby = EmbyClient(
        baseUrl: server,
        deviceId: deviceId,
        token: token,
        userId: userId,
        userName: prefs.getString('emby.userName'),
      );
    }

    if (trakt.connected) unawaited(trakt.flushPending());
  }

  String get lastServer => prefs.getString('emby.server') ?? '';
  String get lastUser => prefs.getString('emby.userName') ?? '';
  String get mdblistKey => prefs.getString('mdblist.key') ?? '';

  Future<void> login(String server, String username, String password) async {
    final c = await EmbyClient.login(
      baseUrl: server,
      username: username,
      password: password,
      deviceId: deviceId,
    );
    await prefs.setString('emby.server', c.baseUrl);
    await prefs.setString('emby.token', c.token!);
    await prefs.setString('emby.userId', c.userId!);
    await prefs.setString('emby.userName', c.userName ?? username);
    emby = c;
    notifyListeners();
  }

  Future<void> logout() async {
    await prefs.remove('emby.token');
    await prefs.remove('emby.userId');
    emby = null;
    notifyListeners();
  }

  Future<void> setMdblistKey(String key) async {
    final k = key.trim();
    await prefs.setString('mdblist.key', k);
    ratings.apiKey = k;
    await ratings.clearCache();
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  /// 会随状态变化重建
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// 只读取,不订阅(可用在 initState 里)
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

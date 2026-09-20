import 'dart:async';

import 'trakt_service.dart';

enum ScrobbleAction { start, pause, stop }

class _Event {
  _Event(this.action, this.target, this.progress);
  final ScrobbleAction action;
  final ScrobbleTarget target;
  final double progress; // 0~100
  int attempts = 0;
}

/// Trakt Scrobble 状态机。
///
/// 严格按官方建议,**只在这四种时机发请求,没有任何定时心跳**:
///   1. 开始播放 / 暂停后恢复  → /scrobble/start
///   2. 暂停                    → /scrobble/pause
///   3. 拖动进度                → 停止拖动 1.5 秒后发一次(播放中发 start,暂停中发 pause)
///   4. 播放结束 / 退出         → /scrobble/stop
///
/// 保护措施:
///   - 单一串行队列,两次请求之间至少间隔 1.2 秒(Trakt 写操作约 1 次/秒)
///   - 队列里连续两个相同动作只保留最新的(合并)
///   - stop 到来时,丢弃同一影片还没发出去的 start / pause
///   - 409(重复上报)视为成功,不重试
///   - 429 按 Retry-After 等待后最多再试一次
///   - 网络失败不循环重试;已看完(≥80%)的 stop 会存入本地,之后用 /sync/history 补录
class TraktScrobbler {
  TraktScrobbler(this.trakt);

  final TraktService trakt;

  static const minGap = Duration(milliseconds: 1200);
  static const seekDebounce = Duration(milliseconds: 1500);
  static const watchedThreshold = 80.0;

  final List<_Event> _queue = [];
  bool _pumping = false;
  Timer? _seekTimer;
  ScrobbleTarget? _target;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _active => _target != null && trakt.connected;

  /// 开始追踪一部影片;传 null 表示这部片子没法匹配 Trakt(缺少 IMDb/TMDb ID)。
  void begin(ScrobbleTarget? target) {
    _seekTimer?.cancel();
    _target = target;
  }

  /// 开始播放,或从暂停恢复。
  void onPlay(double progress) {
    _seekTimer?.cancel();
    _enqueue(ScrobbleAction.start, progress);
  }

  void onPause(double progress) {
    _seekTimer?.cancel(); // 暂停时的进度比还没发出的拖动进度更新
    _enqueue(ScrobbleAction.pause, progress);
  }

  /// 用户拖动 / 跳转进度。连续多次只会在最后一次之后 1.5 秒发送一次。
  void onSeek(double progress, {required bool playing}) {
    if (!_active) return;
    _seekTimer?.cancel();
    _seekTimer = Timer(seekDebounce, () {
      _enqueue(playing ? ScrobbleAction.start : ScrobbleAction.pause, progress);
    });
  }

  /// 播放结束或退出播放器。
  void onStop(double progress) {
    _seekTimer?.cancel();
    final t = _target;
    _target = null;
    if (t == null || !trakt.connected) return;
    _queue.removeWhere((e) => identical(e.target, t));
    _queue.add(_Event(ScrobbleAction.stop, t, progress));
    _pump();
  }

  void _enqueue(ScrobbleAction action, double progress) {
    final t = _target;
    if (t == null || !trakt.connected) return;
    if (_queue.isNotEmpty &&
        identical(_queue.last.target, t) &&
        _queue.last.action == action) {
      _queue.removeLast(); // 合并:只保留最新进度
    }
    _queue.add(_Event(action, t, progress));
    _pump();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        final wait = _lastSent.add(minGap).difference(DateTime.now());
        if (!wait.isNegative) await Future.delayed(wait);
        if (_queue.isEmpty) break;
        final e = _queue.removeAt(0);
        await _deliver(e);
        _lastSent = DateTime.now();
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _deliver(_Event e) async {
    e.attempts++;
    try {
      await trakt.ensureFreshToken();
      var res = await trakt.scrobble(e.action.name, e.target.toBody(e.progress));
      if (res.status == 401 && await trakt.refresh()) {
        res = await trakt.scrobble(e.action.name, e.target.toBody(e.progress));
      }
      final s = res.status;
      if (s == 200 || s == 201 || s == 409) {
        if (e.action == ScrobbleAction.stop) unawaited(trakt.flushPending());
        return;
      }
      if (s == 429) {
        if (e.attempts < 2) {
          await Future.delayed(Duration(seconds: res.retryAfter ?? 5));
          _queue.insert(0, e);
        }
        return;
      }
      if (s >= 500) {
        await _saveOffline(e);
      }
      // 401(刷新也失败)/ 404(匹配不到影片)/ 422 等:不重试,直接丢弃
    } catch (_) {
      await _saveOffline(e);
    }
  }

  Future<void> _saveOffline(_Event e) async {
    if (e.action == ScrobbleAction.stop && e.progress >= watchedThreshold) {
      await trakt.addPendingHistory(e.target, DateTime.now().toUtc());
    }
  }
}

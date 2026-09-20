import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show AppExitResponse, FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/media.dart';
import '../services/emby_client.dart';
import '../services/trakt_service.dart';

/// 播放页。
///
/// 两条完全独立的上报链路:
///  - Emby:  开始 / 每 10 秒 / 暂停 / 恢复 / 结束(Emby 服务端本来就要求定时进度)
///  - Trakt: 仅在 开始 / 暂停·恢复 / 拖动进度 / 结束 时发送(见 TraktScrobbler,没有定时心跳)
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.item,
    required this.queue,
    this.startPosition = Duration.zero,
  });

  final MediaItem item;
  final List<MediaItem> queue;
  final Duration startPosition;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final AppState _app;
  late final Player _player;
  late final VideoController _video;
  late final AppLifecycleListener _lifecycle;
  final List<StreamSubscription<dynamic>> _subs = [];
  final FocusNode _focus = FocusNode();

  late MediaItem _item;
  late int _queueIndex;

  MediaSource? _source;
  String _playSessionId = '';
  Duration _durHint = Duration.zero;
  bool _transcoding = false;
  bool _triedTranscode = false;

  final ValueNotifier<Duration> _posN = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durN = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _bufN = ValueNotifier(Duration.zero);

  bool _loading = true;
  bool _buffering = false;
  bool _awaitingStart = false; // 等待文件真正打开(收到时长)后再算「开始播放」
  bool _opened = false; // 当前影片已开始,后续的暂停/恢复才需要上报
  bool _finished = true; // 当前影片的「停止」是否已上报(true = 没有待收尾的影片)
  bool _completedHandled = false;
  bool? _reportedPlaying;
  String? _error;

  bool _showControls = true;
  bool _menuOpen = false;
  Timer? _hideTimer;
  Timer? _embyTimer;
  bool _fullscreen = false;
  double _volume = 100;
  double _volumeBeforeMute = 100;
  double _rate = 1.0;
  BoxFit _fit = BoxFit.contain;
  bool _dragging = false;
  double _dragMs = 0;

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    _item = widget.item;
    final idx = widget.queue.indexWhere((e) => e.id == widget.item.id);
    _queueIndex = idx < 0 ? 0 : idx;

    _player = Player(
      configuration: PlayerConfiguration(
        title: 'Emby Player',
        bufferSize: 128 * 1024 * 1024,
        libass: true, // 用 libass 渲染 ASS/SSA 特效字幕(样式、卡拉OK、定位都保留)
      ),
    );
    _video = VideoController(_player);
    _bindStreams();
    _configureMpv();

    // 点窗口关闭按钮时,也要把「停止」事件发出去
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      await _finishCurrent();
      return AppExitResponse.exit;
    });

    _load(_item, start: widget.startPosition);
    _pokeControls();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _embyTimer?.cancel();
    _finishCurrent(); // 同步读取位置后再释放播放器
    for (final s in _subs) {
      s.cancel();
    }
    _lifecycle.dispose();
    if (_fullscreen && Platform.isWindows) windowManager.setFullScreen(false);
    _player.dispose();
    _focus.dispose();
    _posN.dispose();
    _durN.dispose();
    _bufN.dispose();
    super.dispose();
  }

  // ───────────────────────── 初始化 ─────────────────────────

  void _listen<T>(Stream<T> s, void Function(T) f) => _subs.add(s.listen(f));

  void _bindStreams() {
    _listen<bool>(_player.stream.playing, _onPlaying);
    _listen<Duration>(_player.stream.position, (p) {
      if (_opened) _posN.value = p;
    });
    _listen<Duration>(_player.stream.duration, (d) {
      _durN.value = d > Duration.zero ? d : _durHint;
      if (d > Duration.zero && _awaitingStart) {
        _awaitingStart = false;
        _onStarted();
      }
    });
    _listen<Duration>(_player.stream.buffer, (b) => _bufN.value = b);
    _listen<bool>(_player.stream.buffering, (b) {
      if (mounted) setState(() => _buffering = b);
    });
    _listen<bool>(_player.stream.completed, _onCompleted);
    _listen<Tracks>(_player.stream.tracks, (_) {
      if (mounted) setState(() {});
    });
    _listen<Track>(_player.stream.track, (_) {
      if (mounted) setState(() {});
    });
    _listen<String>(_player.stream.error, _onError);
  }

  Future<void> _configureMpv() async {
    try {
      if (_player.platform is NativePlayer) {
        final native = _player.platform as dynamic;
        // 默认字幕语言优先级:中文 > 英文
        await native.setProperty('slang', 'chi,zho,zh,chs,cht,eng');
        // 非 ASS 字幕(SRT 等)以及 ASS 缺字时的兜底字体
        await native.setProperty('sub-font', 'Microsoft YaHei');
      }
    } catch (_) {}
  }

  // ───────────────────────── 载入影片 ─────────────────────────

  Future<void> _load(MediaItem item, {Duration start = Duration.zero}) async {
    setState(() {
      _item = item;
      _loading = true;
      _error = null;
      _opened = false;
      _awaitingStart = false;
      _completedHandled = false;
      _triedTranscode = false;
      _transcoding = false;
      _reportedPlaying = null;
      _posN.value = start;
      _bufN.value = Duration.zero;
    });
    final emby = _app.emby!;
    try {
      final info = await emby.playbackInfo(item.id, startTicks: durationToTicks(start));
      if (!mounted) return;
      if (info.mediaSources.isEmpty) throw EmbyException('服务器没有返回可播放的媒体源');
      final source = info.mediaSources.first;
      _source = source;
      _playSessionId = info.playSessionId;
      final hint = source.runTimeTicks ?? item.runtimeTicks;
      _durHint = hint == null ? Duration.zero : ticksToDuration(hint);
      _durN.value = _durHint;

      await _prepareTrakt(item);
      if (!mounted) return;

      final url = emby.directStreamUrl(item.id, source, _playSessionId);
      _awaitingStart = true;
      await _player.open(
        Media(url, start: start > Duration.zero ? start : null),
        play: true,
      );
      if (!mounted) return;
      setState(() => _loading = false);
      await _addExternalSubs();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _prepareTrakt(MediaItem item) async {
    ScrobbleTarget? target;
    if (_app.trakt.connected) {
      if (item.isMovie) {
        target = ScrobbleTarget.forMovie(item.providerIds);
      } else if (item.isEpisode) {
        Map<String, String>? showIds;
        if (item.seriesId != null) {
          try {
            showIds = (await _app.emby!.item(item.seriesId!)).providerIds;
          } catch (_) {}
        }
        target = ScrobbleTarget.forEpisode(
          episodeIds: item.providerIds,
          showProviderIds: showIds,
          season: item.parentIndexNumber,
          number: item.indexNumber,
        );
      }
      if (target == null && mounted) {
        _toast('这部影片缺少 IMDb / TMDb ID,不会同步到 Trakt');
      }
    }
    _app.scrobbler.begin(target);
  }

  /// 外挂字幕由 Emby 提供地址;内封字幕(含 PGS)mpv 直接从文件里读。
  Future<void> _addExternalSubs() async {
    final s = _source;
    if (s == null) return;
    final emby = _app.emby!;
    var added = false;
    for (final sub in s.subtitles) {
      final url = emby.externalSubtitleUrl(_item.id, s, sub);
      if (url == null) continue;
      try {
        await _player.setSubtitleTrack(SubtitleTrack.uri(
          url,
          title: sub.displayTitle ?? sub.title ?? '外挂字幕',
          language: sub.language,
        ));
        added = true;
      } catch (_) {}
    }
    // 添加外挂字幕会自动选中最后一条,这里交还给 mpv 按语言偏好重新选择
    if (added) await _player.setSubtitleTrack(SubtitleTrack.auto());
  }

  // ───────────────────────── 事件 → 上报 ─────────────────────────

  Duration get _dur => _durN.value;

  double _progressOf(Duration p) {
    final d = _dur;
    if (d.inMilliseconds <= 0) return 0;
    return (p.inMilliseconds * 100 / d.inMilliseconds).clamp(0.0, 100.0).toDouble();
  }

  bool _nearEnd() {
    final d = _dur;
    return d > Duration.zero && (d - _posN.value) < const Duration(milliseconds: 1500);
  }

  /// 文件真正打开、开始播放。
  void _onStarted() {
    _opened = true;
    _finished = false;
    _completedHandled = false;
    _reportedPlaying = true;
    _app.scrobbler.onPlay(_progressOf(_posN.value)); // Trakt: start
    final src = _source;
    if (src != null) unawaited(_app.emby!.reportStart(_playBody()));
    _embyTimer?.cancel();
    _embyTimer = Timer.periodic(const Duration(seconds: 10), (_) => _reportEmby('TimeUpdate'));
  }

  void _onPlaying(bool playing) {
    if (mounted) setState(() {});
    if (!_opened || _finished || _completedHandled) return;
    if (_reportedPlaying == playing) return;
    if (playing) {
      _reportedPlaying = true;
      _app.scrobbler.onPlay(_progressOf(_posN.value)); // 暂停后恢复 → start
      _reportEmby('Unpause');
    } else {
      if (_nearEnd()) return; // 片尾自然停止,交给 completed 事件处理
      _reportedPlaying = false;
      _app.scrobbler.onPause(_progressOf(_posN.value)); // Trakt: pause
      _reportEmby('Pause');
    }
  }

  Future<void> _onCompleted(bool completed) async {
    if (!completed || !_opened || _completedHandled) return;
    _completedHandled = true;
    await _finishCurrent(completed: true);
    if (!mounted) return;
    if (_queueIndex + 1 < widget.queue.length) {
      _queueIndex++;
      await _load(widget.queue[_queueIndex]);
    } else {
      await _exit();
    }
  }

  /// 结束当前影片:Trakt stop + Emby stopped,只会执行一次。
  Future<void> _finishCurrent({bool completed = false}) async {
    if (_finished) return;
    _finished = true;
    _embyTimer?.cancel();
    final pos = completed ? _dur : _posN.value;
    _app.scrobbler.onStop(completed ? 100.0 : _progressOf(pos)); // Trakt: stop
    if (_source != null) {
      unawaited(_app.emby!.reportStopped({
        ..._playBody(position: pos),
        'IsPaused': true,
      }));
    }
  }

  Map<String, dynamic> _playBody({String? event, Duration? position}) => {
        'ItemId': _item.id,
        'MediaSourceId': _source!.id,
        'PlaySessionId': _playSessionId,
        'PositionTicks': durationToTicks(position ?? _posN.value),
        'IsPaused': !_player.state.playing,
        'CanSeek': true,
        'PlayMethod': _transcoding ? 'Transcode' : 'DirectStream',
        if (event != null) 'EventName': event,
      };

  void _reportEmby(String event) {
    if (_source == null || _finished) return;
    unawaited(_app.emby!.reportProgress(_playBody(event: event)));
  }

  // ───────────────────────── 错误 / 转码兜底 ─────────────────────────

  void _onError(String message) {
    if (!mounted) return;
    if (!_opened && !_transcoding && !_triedTranscode && _source != null) {
      _fallbackTranscode();
      return;
    }
    if (!_opened) {
      setState(() {
        _loading = false;
        _error = '无法播放:$message';
      });
    } else {
      _toast('播放器提示:$message');
    }
  }

  Future<void> _fallbackTranscode() async {
    final s = _source;
    if (s == null) return;
    _triedTranscode = true;
    _transcoding = true;
    _toast('直连播放失败,已切换为服务器转码');
    try {
      final url = _app.emby!.transcodeUrl(_item.id, s, _playSessionId);
      final start = _posN.value;
      _awaitingStart = true;
      await _player.open(
        Media(url, start: start > const Duration(seconds: 2) ? start : null),
        play: true,
      );
      await _addExternalSubs();
    } catch (e) {
      if (mounted) setState(() => _error = '转码播放也失败了:$e');
    }
  }

  // ───────────────────────── 用户操作 ─────────────────────────

  void _togglePlay() => _player.playOrPause();

  Future<void> _seekTo(Duration target) async {
    var t = target;
    if (t < Duration.zero) t = Duration.zero;
    final d = _dur;
    if (d > Duration.zero && t > d) t = d;
    await _player.seek(t);
    _posN.value = t;
    // Trakt: 拖动进度(内部防抖 1.5 秒,连续操作只发一次)
    if (_opened && !_finished) {
      _app.scrobbler.onSeek(_progressOf(t), playing: _player.state.playing);
    }
  }

  void _seekBy(int seconds) => _seekTo(_posN.value + Duration(seconds: seconds));

  Future<void> _changeItem(int delta) async {
    final next = _queueIndex + delta;
    if (next < 0 || next >= widget.queue.length) return;
    await _finishCurrent();
    _queueIndex = next;
    await _load(widget.queue[next]);
  }

  void _setVolume(double v) {
    setState(() => _volume = v);
    _player.setVolume(v);
  }

  void _toggleMute() {
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      _setVolume(0);
    } else {
      _setVolume(_volumeBeforeMute <= 0 ? 100 : _volumeBeforeMute);
    }
  }

  Future<void> _setFullscreen(bool v) async {
    if (!Platform.isWindows) return;
    _fullscreen = v;
    await windowManager.setFullScreen(v);
    if (mounted) setState(() {});
  }

  Future<void> _toggleFullscreen() => _setFullscreen(!_fullscreen);

  Future<void> _exit() async {
    await _finishCurrent();
    if (_fullscreen) await _setFullscreen(false);
    if (mounted) Navigator.of(context).pop();
  }

  void _pokeControls() {
    if (!_showControls && mounted) setState(() => _showControls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _player.state.playing && !_menuOpen && !_dragging) {
        setState(() => _showControls = false);
      }
    });
  }

  void _menuOpened(bool open) {
    _menuOpen = open;
    if (open) {
      _hideTimer?.cancel();
    } else {
      _pokeControls();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final down = e is KeyDownEvent;
    if (k == LogicalKeyboardKey.space && down) {
      _togglePlay();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _seekBy(10);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _setVolume(math.min(100.0, _volume + 5));
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _setVolume(math.max(0.0, _volume - 5));
    } else if ((k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) && down) {
      _toggleFullscreen();
    } else if (k == LogicalKeyboardKey.keyM && down) {
      _toggleMute();
    } else if (k == LogicalKeyboardKey.keyN && down) {
      _changeItem(1);
    } else if (k == LogicalKeyboardKey.keyP && down) {
      _changeItem(-1);
    } else if (k == LogicalKeyboardKey.escape && down) {
      _fullscreen ? _setFullscreen(false) : _exit();
    } else {
      return KeyEventResult.ignored;
    }
    _pokeControls();
    return KeyEventResult.handled;
  }

  // ───────────────────────── UI ─────────────────────────

  String get _title {
    final i = _item;
    if (i.isEpisode) return '${i.seriesName ?? ''}   ${i.episodeCode}   ${i.name}'.trim();
    return i.name;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: _showControls ? SystemMouseCursors.basic : SystemMouseCursors.none,
          onHover: (_) => _pokeControls(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(
                controller: _video,
                fit: _fit,
                controls: NoVideoControls,
                // 字幕由 libass 画进视频里,这里关掉 Flutter 端的纯文字字幕层
                subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePlay,
                  onDoubleTap: _toggleFullscreen,
                ),
              ),
              if (_loading || _buffering)
                const IgnorePointer(child: Center(child: CircularProgressIndicator(color: Colors.white70))),
              if (_error != null) _errorView(),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: ExcludeFocus(child: _controls()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface.withAlpha(235),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 36, color: Color(0xFFFF7B72)),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () => _load(_item, start: _posN.value),
                  child: const Text('重试'),
                ),
                const SizedBox(width: 10),
                TextButton(onPressed: _exit, child: const Text('返回')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    final hasQueue = widget.queue.length > 1;
    final playing = _player.state.playing;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 24, 44),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withAlpha(200), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: '返回 (Esc)',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _exit,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              if (_transcoding)
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Text('服务器转码', style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                ),
            ],
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.fromLTRB(28, 48, 28, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withAlpha(215)],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _seekBar(),
              Row(
                children: [
                  if (hasQueue)
                    IconButton(
                      tooltip: '上一集 (P)',
                      icon: const Icon(Icons.skip_previous_rounded),
                      onPressed: _queueIndex > 0 ? () => _changeItem(-1) : null,
                    ),
                  IconButton(
                    tooltip: '后退 10 秒 (←)',
                    icon: const Icon(Icons.replay_10_rounded),
                    onPressed: () => _seekBy(-10),
                  ),
                  IconButton(
                    iconSize: 38,
                    tooltip: playing ? '暂停 (空格)' : '播放 (空格)',
                    icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    onPressed: _togglePlay,
                  ),
                  IconButton(
                    tooltip: '前进 10 秒 (→)',
                    icon: const Icon(Icons.forward_10_rounded),
                    onPressed: () => _seekBy(10),
                  ),
                  if (hasQueue)
                    IconButton(
                      tooltip: '下一集 (N)',
                      icon: const Icon(Icons.skip_next_rounded),
                      onPressed: _queueIndex < widget.queue.length - 1 ? () => _changeItem(1) : null,
                    ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '静音 (M)',
                    icon: Icon(_volume <= 0
                        ? Icons.volume_off_rounded
                        : (_volume < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded)),
                    onPressed: _toggleMute,
                  ),
                  SizedBox(
                    width: 110,
                    child: SliderTheme(
                      data: _sliderTheme(),
                      child: Slider(value: _volume, min: 0, max: 100, onChanged: _setVolume),
                    ),
                  ),
                  const Spacer(),
                  _speedMenu(),
                  _audioMenu(),
                  _subtitleMenu(),
                  IconButton(
                    tooltip: _fit == BoxFit.contain
                        ? '画面:适应窗口'
                        : (_fit == BoxFit.cover ? '画面:裁切填满' : '画面:拉伸填满'),
                    icon: const Icon(Icons.aspect_ratio_rounded),
                    onPressed: () => setState(() {
                      _fit = _fit == BoxFit.contain
                          ? BoxFit.cover
                          : (_fit == BoxFit.cover ? BoxFit.fill : BoxFit.contain);
                    }),
                  ),
                  IconButton(
                    tooltip: _fullscreen ? '退出全屏 (F)' : '全屏 (F)',
                    icon: Icon(_fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                    onPressed: _toggleFullscreen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  SliderThemeData _sliderTheme() => SliderTheme.of(context).copyWith(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: SliderComponentShape.noOverlay,
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: Colors.white24,
        secondaryActiveTrackColor: Colors.white38,
        thumbColor: Colors.white,
      );

  Widget _seekBar() {
    const timeStyle = TextStyle(fontSize: 12.5, color: Colors.white70, fontFeatures: [FontFeature.tabularFigures()]);
    return AnimatedBuilder(
      animation: Listenable.merge([_posN, _durN, _bufN]),
      builder: (_, __) {
        final maxMs = math.max(_dur.inMilliseconds.toDouble(), 1.0);
        final cur = (_dragging ? _dragMs : _posN.value.inMilliseconds.toDouble())
            .clamp(0.0, maxMs)
            .toDouble();
        final buf = _bufN.value.inMilliseconds.toDouble().clamp(0.0, maxMs).toDouble();
        return Row(
          children: [
            SizedBox(
              width: 58,
              child: Text(formatDuration(Duration(milliseconds: cur.round())), style: timeStyle),
            ),
            Expanded(
              child: SliderTheme(
                data: _sliderTheme(),
                child: Slider(
                  value: cur,
                  min: 0,
                  max: maxMs,
                  secondaryTrackValue: buf,
                  onChangeStart: (v) {
                    _dragging = true;
                    _dragMs = v;
                    _hideTimer?.cancel();
                  },
                  onChanged: (v) => setState(() => _dragMs = v),
                  onChangeEnd: (v) {
                    _dragging = false;
                    _seekTo(Duration(milliseconds: v.round()));
                    _pokeControls();
                  },
                ),
              ),
            ),
            SizedBox(
              width: 58,
              child: Text(formatDuration(_dur), textAlign: TextAlign.right, style: timeStyle),
            ),
          ],
        );
      },
    );
  }

  Widget _speedMenu() {
    const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    return PopupMenuButton<double>(
      tooltip: '倍速',
      color: AppColors.surfaceHi,
      onOpened: () => _menuOpened(true),
      onCanceled: () => _menuOpened(false),
      onSelected: (r) {
        _menuOpened(false);
        setState(() => _rate = r);
        _player.setRate(r);
      },
      itemBuilder: (_) => [
        for (final r in rates)
          CheckedPopupMenuItem<double>(value: r, checked: r == _rate, child: Text('${r}x')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Text('${_rate}x', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      ),
    );
  }

  String _trackLabel(String id, String? title, String? language) {
    final parts = <String>[];
    if (title != null && title.trim().isNotEmpty) parts.add(title.trim());
    final lang = langName(language);
    if (lang.isNotEmpty && !parts.any((p) => p.contains(lang))) parts.add(lang);
    return parts.isEmpty ? '轨道 $id' : parts.join('  ');
  }

  Widget _audioMenu() {
    final tracks =
        _player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final current = _player.state.track.audio;
    return PopupMenuButton<AudioTrack>(
      tooltip: '音轨',
      color: AppColors.surfaceHi,
      enabled: tracks.isNotEmpty,
      icon: const Icon(Icons.graphic_eq_rounded),
      onOpened: () => _menuOpened(true),
      onCanceled: () => _menuOpened(false),
      onSelected: (t) {
        _menuOpened(false);
        _player.setAudioTrack(t);
      },
      itemBuilder: (_) => [
        for (final t in tracks)
          CheckedPopupMenuItem<AudioTrack>(
            value: t,
            checked: t.id == current.id,
            child: Text(_trackLabel(t.id, t.title, t.language)),
          ),
      ],
    );
  }

  Widget _subtitleMenu() {
    final tracks =
        _player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final current = _player.state.track.subtitle;
    return PopupMenuButton<SubtitleTrack>(
      tooltip: '字幕',
      color: AppColors.surfaceHi,
      icon: const Icon(Icons.subtitles_rounded),
      onOpened: () => _menuOpened(true),
      onCanceled: () => _menuOpened(false),
      onSelected: (t) {
        _menuOpened(false);
        _player.setSubtitleTrack(t);
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem<SubtitleTrack>(
          value: SubtitleTrack.no(),
          checked: current.id == 'no',
          child: const Text('关闭字幕'),
        ),
        for (final t in tracks)
          CheckedPopupMenuItem<SubtitleTrack>(
            value: t,
            checked: t.id == current.id,
            child: Text(_trackLabel(t.id, t.title, t.language)),
          ),
      ],
    );
  }
}

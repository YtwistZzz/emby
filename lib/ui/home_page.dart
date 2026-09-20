import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/media.dart';
import '../widgets/emby_image.dart';
import '../widgets/poster_card.dart';
import '../widgets/shelf.dart';
import 'nav.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.views});
  final List<MediaItem> views;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppState _app;
  List<MediaItem> _resume = [];
  List<MediaItem> _nextUp = [];
  final Map<String, List<MediaItem>> _latest = {};
  List<MediaItem> _hero = [];
  bool _loading = true;
  String? _error;
  int _heroIndex = 0;
  Timer? _heroTimer;

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    _app.playbackRevision.addListener(_reloadProgress);
    _load();
  }

  @override
  void dispose() {
    _app.playbackRevision.removeListener(_reloadProgress);
    _heroTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final emby = _app.emby!;
    try {
      final base = await Future.wait([emby.resume(), emby.nextUp()]);
      final latest = await Future.wait(widget.views.map((v) => emby.latest(v.id)));
      if (!mounted) return;
      final hero = latest
          .expand((l) => l)
          .where((i) => (i.isMovie || i.isSeries) && emby.backdropUrl(i) != null)
          .take(6)
          .toList();
      setState(() {
        _resume = base[0];
        _nextUp = base[1];
        for (var i = 0; i < widget.views.length; i++) {
          _latest[widget.views[i].id] = latest[i];
        }
        _hero = hero;
        _loading = false;
        _error = null;
      });
      _startHeroTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  /// 播放结束后只刷新「继续观看 / 接下来」,不重新加载整页。
  Future<void> _reloadProgress() async {
    final emby = _app.emby;
    if (emby == null) return;
    try {
      final base = await Future.wait([emby.resume(), emby.nextUp()]);
      if (!mounted) return;
      setState(() {
        _resume = base[0];
        _nextUp = base[1];
      });
    } catch (_) {}
  }

  void _startHeroTimer() {
    _heroTimer?.cancel();
    if (_hero.length < 2) return;
    _heroTimer = Timer.periodic(const Duration(seconds: 9), (_) {
      if (!mounted) return;
      setState(() => _heroIndex = (_heroIndex + 1) % _hero.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    const posterW = 150.0;
    const thumbW = 260.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (_hero.isNotEmpty)
            _Hero(
              item: _hero[_heroIndex % _hero.length],
              count: _hero.length,
              index: _heroIndex % _hero.length,
              onDot: (i) {
                setState(() => _heroIndex = i);
                _startHeroTimer();
              },
            )
          else
            const SizedBox(height: 40),
          Shelf(
            title: '继续观看',
            height: PosterCard.heightFor(thumbW, landscape: true),
            itemCount: _resume.length,
            itemBuilder: (_, i) => PosterCard(
              item: _resume[i],
              width: thumbW,
              landscape: true,
              onTap: () => openDetail(context, _resume[i]),
              onPlay: () => playItem(context, _resume[i]),
            ),
          ),
          Shelf(
            title: '接下来观看',
            height: PosterCard.heightFor(thumbW, landscape: true),
            itemCount: _nextUp.length,
            itemBuilder: (_, i) => PosterCard(
              item: _nextUp[i],
              width: thumbW,
              landscape: true,
              onTap: () => openDetail(context, _nextUp[i]),
              onPlay: () => playItem(context, _nextUp[i]),
            ),
          ),
          for (final v in widget.views)
            Shelf(
              title: '最近添加 · ${v.name}',
              height: PosterCard.heightFor(posterW),
              itemCount: (_latest[v.id] ?? const []).length,
              itemBuilder: (_, i) {
                final item = _latest[v.id]![i];
                return PosterCard(
                  item: item,
                  width: posterW,
                  onTap: () => openDetail(context, item),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.item,
    required this.count,
    required this.index,
    required this.onDot,
  });

  final MediaItem item;
  final int count;
  final int index;
  final ValueChanged<int> onDot;

  @override
  Widget build(BuildContext context) {
    final emby = AppScope.read(context).emby!;
    final meta = <String>[
      if (item.year != null) '${item.year}',
      if (item.officialRating != null) item.officialRating!,
      if (item.runtimeTicks != null) formatRuntime(item.runtimeTicks),
      if (item.isSeries) '剧集',
    ];
    return SizedBox(
      height: 440,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            switchInCurve: Curves.easeOut,
            child: SizedBox.expand(
              key: ValueKey(item.id),
              child: EmbyImage(
                url: emby.backdropUrl(item, maxWidth: 1600),
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xE60B0C10), Color(0x660B0C10), Color(0x000B0C10)],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x000B0C10), AppColors.bg],
                stops: [0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 40,
            bottom: 52,
            width: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, height: 1.08),
                ),
                const SizedBox(height: 12),
                Text(meta.join('   '),
                    style: const TextStyle(fontSize: 14, color: AppColors.textDim, fontWeight: FontWeight.w500)),
                if ((item.overview ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    item.overview!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.text.withAlpha(215)),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => openDetail(context, item),
                  icon: const Icon(Icons.info_outline_rounded, size: 20),
                  label: const Text('查看详情'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          if (count > 1)
            Positioned(
              right: 40,
              bottom: 56,
              child: Row(
                children: [
                  for (var i = 0; i < count; i++)
                    GestureDetector(
                      onTap: () => onDot(i),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: i == index ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == index ? AppColors.text : Colors.white.withAlpha(70),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

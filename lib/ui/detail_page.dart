import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/media.dart';
import '../services/ratings_service.dart';
import '../widgets/emby_image.dart';
import '../widgets/poster_card.dart';
import '../widgets/rating_badges.dart';
import '../widgets/shelf.dart';
import 'nav.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.item});
  final MediaItem item;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late final AppState _app;
  late final String _rootId;
  String? _highlightEpisodeId;

  MediaItem? _full;
  Ratings? _ratings;
  List<MediaItem> _seasons = [];
  List<MediaItem> _episodes = [];
  MediaItem? _season;
  MediaItem? _nextUp;
  List<MediaItem> _similar = [];
  bool _loadingEpisodes = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    final it = widget.item;
    _rootId = (it.isEpisode && it.seriesId != null) ? it.seriesId! : it.id;
    _highlightEpisodeId = it.isEpisode ? it.id : null;
    _load();
  }

  Future<void> _load() async {
    final emby = _app.emby!;
    try {
      final full = await emby.item(_rootId);
      if (!mounted) return;
      setState(() => _full = full);
      unawaited(_loadRatings(full));
      unawaited(_loadSimilar());
      if (full.isSeries) await _loadSeries(full);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadRatings(MediaItem full) async {
    final r = await _app.ratings.forItem(full);
    if (mounted) setState(() => _ratings = r);
  }

  Future<void> _loadSimilar() async {
    try {
      final s = await _app.emby!.similar(_rootId);
      if (mounted) setState(() => _similar = s);
    } catch (_) {}
  }

  Future<void> _loadSeries(MediaItem series) async {
    final emby = _app.emby!;
    final seasons = await emby.seasons(series.id);
    MediaItem? next;
    try {
      final n = await emby.nextUp(seriesId: series.id, limit: 1);
      if (n.isNotEmpty) next = n.first;
    } catch (_) {}

    final wantSeasonId = widget.item.isEpisode ? widget.item.seasonId : next?.seasonId;
    MediaItem? pick;
    if (wantSeasonId != null) {
      pick = seasons.where((s) => s.id == wantSeasonId).firstOrNull;
    }
    pick ??= seasons.firstOrNull;
    if (!mounted) return;
    setState(() {
      _seasons = seasons;
      _season = pick;
      _nextUp = next;
    });
    if (pick != null) await _loadEpisodes(pick);
  }

  Future<void> _loadEpisodes(MediaItem season) async {
    setState(() {
      _season = season;
      _loadingEpisodes = true;
    });
    try {
      final eps = await _app.emby!.episodes(_rootId, seasonId: season.id);
      if (!mounted || _season?.id != season.id) return;
      setState(() {
        _episodes = eps;
        _loadingEpisodes = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingEpisodes = false);
    }
  }

  /// 播放结束回来后,刷新观看进度。
  Future<void> _refresh() async {
    try {
      final emby = _app.emby!;
      final full = await emby.item(_rootId);
      MediaItem? next;
      List<MediaItem>? eps;
      if (full.isSeries) {
        final n = await emby.nextUp(seriesId: full.id, limit: 1);
        next = n.firstOrNull;
        if (_season != null) eps = await emby.episodes(_rootId, seasonId: _season!.id);
      }
      if (!mounted) return;
      setState(() {
        _full = full;
        if (full.isSeries) {
          _nextUp = next;
          if (eps != null) _episodes = eps;
          _highlightEpisodeId = null;
        }
      });
    } catch (_) {}
  }

  MediaItem? get _playTarget {
    final f = _full;
    if (f == null) return null;
    if (!f.isSeries) return f;
    if (_highlightEpisodeId != null) {
      final e = _episodes.where((x) => x.id == _highlightEpisodeId).firstOrNull;
      if (e != null) return e;
    }
    return _nextUp ?? _episodes.firstOrNull;
  }

  Future<void> _play(MediaItem target, {bool resume = true, List<MediaItem>? queue}) async {
    await playItem(context, target, resume: resume, queue: queue);
    if (mounted) _refresh();
  }

  Future<void> _togglePlayed() async {
    final f = _full;
    if (f == null) return;
    try {
      await _app.emby!.setPlayed(f.id, !f.userData.played);
      await _refresh();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final emby = _app.emby!;
    final f = _full;
    return Scaffold(
      body: Stack(
        children: [
          // 背景剧照
          if (f != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 620,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EmbyImage(url: emby.backdropUrl(f, maxWidth: 1920), alignment: Alignment.topCenter),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x800B0C10), Color(0xCC0B0C10), AppColors.bg],
                        stops: [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (f == null && _error == null) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(child: Text(_error!, style: const TextStyle(color: AppColors.textDim))),
          if (f != null) _content(f),
          Positioned(
            top: 16,
            left: 20,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Material(
                  color: Colors.black.withAlpha(100),
                  child: IconButton(
                    tooltip: '返回',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(MediaItem f) {
    final emby = _app.emby!;
    final target = _playTarget;
    final ratings = _ratings ?? Ratings.fromEmby(f);
    final meta = <String>[
      if (f.year != null) '${f.year}',
      if (f.isMovie && f.runtimeTicks != null) formatRuntime(f.runtimeTicks),
      if (f.isSeries && _seasons.isNotEmpty) '${_seasons.length} 季',
    ];
    final tags = f.mediaSources.isNotEmpty ? f.mediaSources.first.qualityTags() : const <String>[];
    final people = f.people.where((p) => p.type == 'Actor' || p.type == 'Director').take(20).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 96, bottom: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 236,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(160), blurRadius: 30, offset: const Offset(0, 14))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: EmbyImage(url: emby.posterUrl(f, maxWidth: 520), cacheWidth: 520),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 38),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.name,
                            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, height: 1.1)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final m in meta)
                              Text(m, style: const TextStyle(fontSize: 14.5, color: AppColors.textDim)),
                            if (f.officialRating != null) _OutlineTag(f.officialRating!),
                          ],
                        ),
                        const SizedBox(height: 18),
                        RatingsRow(ratings: ratings, loading: _ratings == null && _app.ratings.hasKey),
                        if (!_app.ratings.hasKey && ratings.isEmpty == false)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text('在「设置」里填入 MDBList API Key,可显示 IMDb / 烂番茄 / Metacritic 等评分',
                                style: TextStyle(fontSize: 11.5, color: AppColors.textDim)),
                          ),
                        if (f.taglines.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(f.taglines.first,
                              style: const TextStyle(
                                  fontSize: 15, fontStyle: FontStyle.italic, color: AppColors.textDim)),
                        ],
                        if ((f.overview ?? '').isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(f.overview!,
                              style: TextStyle(fontSize: 15, height: 1.6, color: AppColors.text.withAlpha(225))),
                        ],
                        if (f.genres.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Wrap(spacing: 8, runSpacing: 8, children: [for (final g in f.genres) _OutlineTag(g, dim: true)]),
                        ],
                        const SizedBox(height: 24),
                        _actions(f, target),
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tags) _QualityChip(t)]),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (f.isSeries) ...[
            const SizedBox(height: 40),
            _seasonsSection(),
          ],
          if (people.isNotEmpty) ...[
            const SizedBox(height: 36),
            Shelf(
              title: '演职员',
              height: 176,
              itemCount: people.length,
              itemBuilder: (_, i) => _PersonCard(person: people[i]),
            ),
          ],
          if (_similar.isNotEmpty)
            Shelf(
              title: '更多类似',
              height: PosterCard.heightFor(140),
              itemCount: _similar.length,
              itemBuilder: (_, i) => PosterCard(
                item: _similar[i],
                width: 140,
                onTap: () => Navigator.of(context).pushReplacement(
                  fadeRoute(DetailPage(item: _similar[i])),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actions(MediaItem f, MediaItem? target) {
    if (target == null) {
      return const SizedBox(height: 48);
    }
    final resume = target.canResume;
    final label = resume
        ? '继续播放 ${formatDuration(ticksToDuration(target.userData.positionTicks))}'
        : (f.isSeries ? '播放 ${target.episodeCode}' : '播放');
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: () => _play(target, queue: f.isSeries ? _episodes : null),
          icon: const Icon(Icons.play_arrow_rounded, size: 26),
          label: Text(label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (resume)
          OutlinedButton(
            onPressed: () => _play(target, resume: false, queue: f.isSeries ? _episodes : null),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text,
              side: const BorderSide(color: AppColors.line),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('从头播放'),
          ),
        if (!f.isSeries)
          IconButton.outlined(
            tooltip: f.userData.played ? '标记为未看' : '标记为已看',
            onPressed: _togglePlayed,
            icon: Icon(
              f.userData.played ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
              color: f.userData.played ? AppColors.accent : null,
            ),
            style: IconButton.styleFrom(
              side: const BorderSide(color: AppColors.line),
              padding: const EdgeInsets.all(14),
            ),
          ),
      ],
    );
  }

  Widget _seasonsSection() {
    if (_seasons.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 44),
            itemCount: _seasons.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final s = _seasons[i];
              final sel = s.id == _season?.id;
              return ChoiceChip(
                label: Text(s.name),
                selected: sel,
                showCheckmark: false,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: sel ? const Color(0xFF0B0C10) : AppColors.text,
                ),
                selectedColor: AppColors.accent,
                backgroundColor: AppColors.surfaceHi,
                side: BorderSide.none,
                onSelected: (_) => _loadEpisodes(s),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        if (_loadingEpisodes && _episodes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: Column(
              children: [
                for (final e in _episodes)
                  _EpisodeTile(
                    episode: e,
                    highlighted: e.id == _highlightEpisodeId,
                    onTap: () => _play(e, queue: _episodes),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _OutlineTag extends StatelessWidget {
  const _OutlineTag(this.text, {this.dim = false});
  final String text;
  final bool dim;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: dim ? 12 : 7, vertical: dim ? 5 : 1),
        decoration: BoxDecoration(
          border: Border.all(color: dim ? AppColors.line : AppColors.textDim.withAlpha(140)),
          borderRadius: BorderRadius.circular(dim ? 14 : 4),
        ),
        child: Text(text,
            style: TextStyle(fontSize: dim ? 12.5 : 12, color: dim ? AppColors.text.withAlpha(200) : AppColors.textDim)),
      );
}

class _QualityChip extends StatelessWidget {
  const _QualityChip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceHi,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDim)),
      );
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person});
  final Person person;

  @override
  Widget build(BuildContext context) {
    final emby = AppScope.read(context).emby!;
    return SizedBox(
      width: 104,
      child: Column(
        children: [
          ClipOval(
            child: SizedBox(
              width: 88,
              height: 88,
              child: EmbyImage(
                url: person.primaryTag != null ? emby.personImageUrl(person) : null,
                icon: Icons.person_outline_rounded,
                cacheWidth: 200,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          if ((person.role ?? '').isNotEmpty)
            Text(person.role!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: AppColors.textDim)),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatefulWidget {
  const _EpisodeTile({required this.episode, required this.onTap, this.highlighted = false});
  final MediaItem episode;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final emby = AppScope.read(context).emby!;
    final e = widget.episode;
    final progress = e.progress;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hover
                ? AppColors.surfaceHi
                : (widget.highlighted ? AppColors.surface : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: widget.highlighted ? Border.all(color: AppColors.accent.withAlpha(120)) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 224,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        EmbyImage(url: emby.thumbUrl(e, maxWidth: 480), cacheWidth: 480),
                        if (_hover)
                          Container(
                            color: Colors.black.withAlpha(90),
                            child: const Icon(Icons.play_arrow_rounded, size: 40),
                          ),
                        if (progress != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor: Colors.black.withAlpha(140),
                              color: AppColors.accent,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${e.indexNumber ?? ''}  ${e.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (e.userData.played)
                          const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.accent),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(formatRuntime(e.runtimeTicks),
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textDim)),
                    if ((e.overview ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        e.overview!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.text.withAlpha(190)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

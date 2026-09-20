import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../models/media.dart';
import 'emby_image.dart';

class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.item,
    this.width = 160,
    this.landscape = false,
    this.onTap,
    this.onPlay,
  });

  final MediaItem item;
  final double width;
  final bool landscape;
  final VoidCallback? onTap;

  /// 横版卡片悬停时显示播放按钮(继续观看直接开播)
  final VoidCallback? onPlay;

  /// 卡片总高度(供横向列表设置高度用)
  static double heightFor(double width, {bool landscape = false}) =>
      (landscape ? width * 9 / 16 : width * 1.5) + 58;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hover = false;

  String get _title {
    final i = widget.item;
    if (widget.landscape && i.isEpisode) return i.seriesName ?? i.name;
    return i.name;
  }

  String get _subtitle {
    final i = widget.item;
    if (i.isEpisode) {
      final code = i.episodeCode;
      return widget.landscape ? '$code  ${i.name}'.trim() : (i.seriesName ?? code);
    }
    if (i.year != null) return '${i.year}';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final emby = app.emby!;
    final i = widget.item;
    final w = widget.width;
    final url = widget.landscape
        ? emby.thumbUrl(i, maxWidth: (w * 2).round())
        : emby.posterUrl(i, maxWidth: (w * 2).round());
    final aspect = widget.landscape ? 16 / 9 : 2 / 3;
    final progress = i.progress;
    final unplayed = i.userData.unplayedItemCount;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                scale: _hover ? 1.03 : 1.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: _hover
                        ? [BoxShadow(color: Colors.black.withAlpha(140), blurRadius: 18, offset: const Offset(0, 8))]
                        : const [],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: aspect,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          EmbyImage(url: url, cacheWidth: (w * 2).round()),
                          if (i.userData.played && !i.isSeries)
                            const Positioned(
                              top: 6,
                              right: 6,
                              child: _Badge(child: Icon(Icons.check_rounded, size: 14, color: Colors.white)),
                            )
                          else if (i.isSeries && unplayed != null && unplayed > 0)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: _Badge(
                                color: AppColors.accent,
                                child: Text('$unplayed',
                                    style: const TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0B0C10))),
                              ),
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
                          if (widget.onPlay != null)
                            Positioned.fill(
                              child: AnimatedOpacity(
                                opacity: _hover ? 1 : 0,
                                duration: const Duration(milliseconds: 140),
                                child: Center(
                                  child: GestureDetector(
                                    onTap: widget.onPlay,
                                    child: Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withAlpha(150),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white.withAlpha(200), width: 1.5),
                                      ),
                                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                _title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              if (_subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textDim),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color ?? Colors.black.withAlpha(160),
          borderRadius: BorderRadius.circular(11),
        ),
        child: child,
      );
}

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/media.dart';
import 'detail_page.dart';
import 'player_page.dart';

void openDetail(BuildContext context, MediaItem item) {
  Navigator.of(context).push(fadeRoute(DetailPage(item: item)));
}

/// 开始播放。剧集会自动带上同一季的后续集数,播完自动连播下一集。
Future<void> playItem(
  BuildContext context,
  MediaItem item, {
  bool resume = true,
  List<MediaItem>? queue,
}) async {
  final app = AppScope.read(context);
  var q = queue;
  if (q == null && item.isEpisode && item.seriesId != null) {
    try {
      q = await app.emby!.episodes(item.seriesId!, seasonId: item.seasonId);
    } catch (_) {}
  }
  if (q == null || !q.any((e) => e.id == item.id)) q = [item];

  final start = (resume && item.canResume)
      ? ticksToDuration(item.userData.positionTicks)
      : Duration.zero;

  if (!context.mounted) return;
  await Navigator.of(context).push(
    fadeRoute(PlayerPage(item: item, queue: q, startPosition: start)),
  );
  app.playbackRevision.value++;
}

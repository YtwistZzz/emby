import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/ratings_service.dart';

class RatingsRow extends StatelessWidget {
  const RatingsRow({super.key, required this.ratings, this.loading = false});

  final Ratings? ratings;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final list = ratings?.ordered ?? const <RatingEntry>[];
    if (list.isEmpty) {
      if (!loading) return const SizedBox.shrink();
      return const SizedBox(
        height: 26,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textDim),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 18,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [for (final e in list) RatingBadge(entry: e)],
    );
  }
}

class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, required this.entry});
  final RatingEntry entry;

  ({String label, Color bg, Color fg}) get _brand {
    final s = entry.score ?? entry.value ?? 0;
    switch (entry.source) {
      case 'imdb':
        return (label: 'IMDb', bg: const Color(0xFFF5C518), fg: Colors.black);
      case 'tomatoes':
        return (
          label: '烂番茄',
          bg: s >= 60 ? const Color(0xFFFA320A) : const Color(0xFF6AC238),
          fg: Colors.white,
        );
      case 'tomatoesaudience':
        return (
          label: '观众',
          bg: s >= 60 ? const Color(0xFFFA8A0A) : const Color(0xFF8A8F98),
          fg: Colors.white,
        );
      case 'metacritic':
        return (
          label: 'Metacritic',
          bg: s >= 61
              ? const Color(0xFF66CC33)
              : (s >= 40 ? const Color(0xFFFFCC33) : const Color(0xFFFF0000)),
          fg: s >= 40 && s < 61 ? Colors.black : Colors.white,
        );
      case 'tmdb':
        return (label: 'TMDb', bg: const Color(0xFF01B4E4), fg: Colors.white);
      case 'trakt':
        return (label: 'Trakt', bg: const Color(0xFFED1C24), fg: Colors.white);
      case 'letterboxd':
        return (label: 'Letterboxd', bg: const Color(0xFF00E054), fg: Colors.black);
      default:
        return (label: '评分', bg: const Color(0xFF3A3F4B), fg: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _brand;
    final tooltip = entry.votes != null ? '${entry.votes} 人评分' : b.label;
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: b.bg, borderRadius: BorderRadius.circular(4)),
            child: Text(
              b.label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: b.fg, height: 1.2),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            entry.display,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

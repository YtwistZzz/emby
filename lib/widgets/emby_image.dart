import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';

class EmbyImage extends StatelessWidget {
  const EmbyImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.alignment = Alignment.center,
    this.icon = Icons.movie_outlined,
  });

  final String? url;
  final BoxFit fit;
  final int? cacheWidth;
  final Alignment alignment;
  final IconData icon;

  Widget _placeholder() => ColoredBox(
        color: AppColors.surfaceHi,
        child: Center(child: Icon(icon, color: AppColors.textDim.withAlpha(90), size: 28)),
      );

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null) return _placeholder();
    return CachedNetworkImage(
      imageUrl: u,
      fit: fit,
      alignment: alignment,
      memCacheWidth: cacheWidth,
      fadeInDuration: const Duration(milliseconds: 220),
      fadeOutDuration: const Duration(milliseconds: 100),
      placeholder: (_, __) => const ColoredBox(color: AppColors.surfaceHi),
      errorWidget: (_, __, ___) => _placeholder(),
    );
  }
}

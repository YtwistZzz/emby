import 'package:flutter/material.dart';

import '../core/theme.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(32, 0, 32, 14)});
  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
      );
}

/// 横向滚动的一排卡片。鼠标悬停时显示左右翻页按钮(Windows 上没有触摸滑动)。
class Shelf extends StatefulWidget {
  const Shelf({
    super.key,
    required this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = 16,
  });

  final String title;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double gap;

  @override
  State<Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<Shelf> {
  final _controller = ScrollController();
  bool _hover = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scroll(int dir) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final target = (_controller.offset + dir * pos.viewportDimension * 0.85)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent)
        .toDouble();
    _controller.animateTo(target, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(widget.title),
            SizedBox(
              height: widget.height,
              child: Stack(
                children: [
                  ListView.separated(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    itemCount: widget.itemCount,
                    separatorBuilder: (_, __) => SizedBox(width: widget.gap),
                    itemBuilder: widget.itemBuilder,
                  ),
                  _Arrow(visible: _hover, left: true, onTap: () => _scroll(-1)),
                  _Arrow(visible: _hover, left: false, onTap: () => _scroll(1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.visible, required this.left, required this.onTap});
  final bool visible;
  final bool left;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      bottom: 58,
      left: left ? 6 : null,
      right: left ? null : 6,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Center(
            child: Material(
              color: Colors.black.withAlpha(170),
              shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 26),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

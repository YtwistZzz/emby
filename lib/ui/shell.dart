import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../models/media.dart';
import 'home_page.dart';
import 'library_page.dart';
import 'search_page.dart';
import 'settings_page.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  List<MediaItem>? _views;
  String? _error;
  final Map<int, Widget> _pages = {};

  @override
  void initState() {
    super.initState();
    _loadViews();
  }

  Future<void> _loadViews() async {
    setState(() => _error = null);
    try {
      final v = await AppScope.read(context).emby!.views();
      if (mounted) setState(() => _views = v);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  IconData _iconFor(MediaItem v) {
    switch (v.collectionType) {
      case 'movies':
        return Icons.movie_outlined;
      case 'tvshows':
        return Icons.live_tv_outlined;
      default:
        return Icons.video_library_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final views = _views;
    if (views == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: const TextStyle(color: AppColors.textDim)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _loadViews, child: const Text('重试')),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => AppScope.read(context).logout(),
                      child: const Text('重新登录'),
                    ),
                  ],
                ),
        ),
      );
    }

    // 0 首页, 1 搜索, 2..n+1 各媒体库, n+2 设置
    final settingsIndex = views.length + 2;
    final count = views.length + 3;

    Widget pageFor(int i) {
      if (i != _index && !_pages.containsKey(i)) return const SizedBox.shrink();
      return _pages.putIfAbsent(i, () {
        if (i == 0) return HomePage(views: views);
        if (i == 1) return const SearchPage();
        if (i == settingsIndex) return const SettingsPage();
        final v = views[i - 2];
        return LibraryPage(key: ValueKey(v.id), view: v);
      });
    }

    return Scaffold(
      body: Row(
        children: [
          _SideBar(
            index: _index,
            onSelect: (i) => setState(() => _index = i),
            items: [
              const _NavEntry(Icons.home_outlined, '首页'),
              const _NavEntry(Icons.search_rounded, '搜索'),
              for (final v in views) _NavEntry(_iconFor(v), v.name),
            ],
            settingsIndex: settingsIndex,
          ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: List.generate(count, pageFor),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavEntry {
  const _NavEntry(this.icon, this.label);
  final IconData icon;
  final String label;
}

class _SideBar extends StatelessWidget {
  const _SideBar({
    required this.index,
    required this.onSelect,
    required this.items,
    required this.settingsIndex,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final List<_NavEntry> items;
  final int settingsIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      decoration: const BoxDecoration(
        color: Color(0xFF0E1014),
        border: Border(right: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 22),
          for (var i = 0; i < items.length; i++)
            _NavButton(
              icon: items[i].icon,
              label: items[i].label,
              selected: index == i,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          _NavButton(
            icon: Icons.tune_rounded,
            label: '设置',
            selected: index == settingsIndex,
            onTap: () => onSelect(settingsIndex),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final color = sel ? AppColors.text : (_hover ? AppColors.text : AppColors.textDim);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? AppColors.surfaceHi : (_hover ? const Color(0x0DFFFFFF) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(widget.icon, size: 24, color: sel ? AppColors.accent : color),
              const SizedBox(height: 4),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: color, fontWeight: sel ? FontWeight.w700 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

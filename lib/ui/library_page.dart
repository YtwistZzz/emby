import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../models/media.dart';
import '../widgets/poster_card.dart';
import 'nav.dart';

const kPosterGrid = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 176,
  mainAxisSpacing: 22,
  crossAxisSpacing: 18,
  childAspectRatio: 0.54,
);

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.view});
  final MediaItem view;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const _sorts = <(String, String, String)>[
    // (显示名, SortBy, 默认顺序)
    ('名称', 'SortName', 'Ascending'),
    ('添加日期', 'DateCreated', 'Descending'),
    ('上映日期', 'PremiereDate', 'Descending'),
    ('评分', 'CommunityRating', 'Descending'),
    ('年份', 'ProductionYear', 'Descending'),
  ];

  late final AppState _app;
  final _scroll = ScrollController();
  final List<MediaItem> _items = [];
  int _total = 0;
  bool _loading = false;
  int _gen = 0; // 切换排序后,丢弃旧请求的结果
  String? _error;
  int _sortIndex = 1;
  bool _desc = true;

  String get _types {
    switch (widget.view.collectionType) {
      case 'movies':
        return 'Movie';
      case 'tvshows':
        return 'Series';
      default:
        return 'Movie,Series,Video';
    }
  }

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
    _desc = _sorts[_sortIndex].$3 == 'Descending';
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    _reset();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    setState(() {
      _gen++;
      _loading = false;
      _items.clear();
      _total = 0;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    if (_items.isNotEmpty && _items.length >= _total) return;
    final gen = _gen;
    setState(() => _loading = true);
    try {
      final page = await _app.emby!.items(
        parentId: widget.view.id,
        includeTypes: _types,
        sortBy: '${_sorts[_sortIndex].$2},SortName',
        sortOrder: _desc ? 'Descending' : 'Ascending',
        start: _items.length,
        limit: 72,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
        _loading = false;
      });
    } catch (e) {
      if (mounted && gen == _gen) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 18),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.view.name,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              ),
              if (_total > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Text('$_total 项', style: const TextStyle(color: AppColors.textDim)),
                ),
              PopupMenuButton<int>(
                tooltip: '排序方式',
                color: AppColors.surfaceHi,
                onSelected: (i) {
                  setState(() {
                    _sortIndex = i;
                    _desc = _sorts[i].$3 == 'Descending';
                  });
                  _reset();
                },
                itemBuilder: (_) => [
                  for (var i = 0; i < _sorts.length; i++)
                    CheckedPopupMenuItem<int>(
                      value: i,
                      checked: i == _sortIndex,
                      child: Text(_sorts[i].$1),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.sort_rounded, size: 20),
                      const SizedBox(width: 6),
                      Text(_sorts[_sortIndex].$1),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: _desc ? '降序' : '升序',
                icon: Icon(_desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 20),
                onPressed: () {
                  setState(() => _desc = !_desc);
                  _reset();
                },
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 14),
            FilledButton(onPressed: _reset, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator()
            : const Text('这个媒体库里还没有内容', style: TextStyle(color: AppColors.textDim)),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 40),
      gridDelegate: kPosterGrid,
      itemCount: _items.length,
      itemBuilder: (_, i) => PosterCard(
        item: _items[i],
        width: 176,
        onTap: () => openDetail(context, _items[i]),
      ),
    );
  }
}

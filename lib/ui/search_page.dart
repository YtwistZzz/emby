import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../models/media.dart';
import '../widgets/poster_card.dart';
import 'library_page.dart' show kPosterGrid;
import 'nav.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final AppState _app;
  final _controller = TextEditingController();
  Timer? _debounce;
  List<MediaItem> _results = [];
  bool _loading = false;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _app = AppScope.read(context);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _results = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _query = q;
      _error = null;
    });
    try {
      final page = await _app.emby!.items(
        includeTypes: 'Movie,Series',
        search: q,
        limit: 60,
      );
      if (!mounted || q != _query) return;
      setState(() {
        _results = page.items;
        _loading = false;
      });
    } catch (e) {
      if (mounted && q == _query) {
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
          child: TextField(
            controller: _controller,
            onChanged: _onChanged,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: '搜索电影和剧集',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
              filled: true,
              fillColor: AppColors.surfaceHi,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: AppColors.textDim)));
    }
    if (_query.isEmpty) {
      return const Center(child: Text('输入片名开始搜索', style: TextStyle(color: AppColors.textDim)));
    }
    if (_loading && _results.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_results.isEmpty) {
      return Center(child: Text('没有找到「$_query」', style: const TextStyle(color: AppColors.textDim)));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 40),
      gridDelegate: kPosterGrid,
      itemCount: _results.length,
      itemBuilder: (_, i) => PosterCard(
        item: _results[i],
        width: 176,
        onTap: () => openDetail(context, _results[i]),
      ),
    );
  }
}

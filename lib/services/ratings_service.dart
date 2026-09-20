import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media.dart';

class RatingEntry {
  const RatingEntry(this.source, {this.score, this.value, this.votes});

  /// 统一后的来源名:imdb / tomatoes / tomatoesaudience / metacritic / tmdb / trakt / letterboxd / emby
  final String source;

  /// 0~100 的归一化分数(MDBList 的 score)
  final double? score;

  /// 来源原始分值
  final double? value;
  final int? votes;

  static String normalize(String s) {
    switch (s.toLowerCase()) {
      case 'popcorn':
      case 'audience':
        return 'tomatoesaudience';
      case 'rottentomatoes':
      case 'tomatometer':
        return 'tomatoes';
      default:
        return s.toLowerCase();
    }
  }

  Map<String, dynamic> toJson() => {'s': source, 'sc': score, 'v': value, 'n': votes};

  factory RatingEntry.fromJson(Map<String, dynamic> j) => RatingEntry(
        j['s'] as String,
        score: (j['sc'] as num?)?.toDouble(),
        value: (j['v'] as num?)?.toDouble(),
        votes: (j['n'] as num?)?.toInt(),
      );

  /// 展示文字
  String get display {
    final sc = score;
    switch (source) {
      case 'imdb':
        final v = sc != null ? sc / 10 : value;
        return v == null ? '' : v.toStringAsFixed(1);
      case 'tmdb':
        final v = sc != null ? sc / 10 : value;
        return v == null ? '' : v.toStringAsFixed(1);
      case 'letterboxd':
        final v = sc != null ? sc / 20 : value; // 5 分制
        return v == null ? '' : v.toStringAsFixed(1);
      case 'emby':
        return value == null ? '' : value!.toStringAsFixed(1);
      case 'tomatoes':
      case 'tomatoesaudience':
      case 'trakt':
        final v = sc ?? value;
        return v == null ? '' : '${v.round()}%';
      default: // metacritic 等
        final v = sc ?? value;
        return v == null ? '' : '${v.round()}';
    }
  }
}

class Ratings {
  Ratings(this.entries);
  final Map<String, RatingEntry> entries;

  static const order = [
    'imdb',
    'tomatoes',
    'tomatoesaudience',
    'metacritic',
    'tmdb',
    'trakt',
    'letterboxd',
    'emby',
  ];

  bool get isEmpty => entries.isEmpty;

  List<RatingEntry> get ordered {
    final out = <RatingEntry>[];
    for (final k in order) {
      final e = entries[k];
      if (e != null && e.display.isNotEmpty) out.add(e);
    }
    return out;
  }

  /// 没有 MDBList key 时的兜底:Emby 自带的社区分和评论家分(通常是 TMDb / 烂番茄)
  factory Ratings.fromEmby(MediaItem i) {
    final m = <String, RatingEntry>{};
    final c = i.communityRating;
    if (c != null && c > 0) m['emby'] = RatingEntry('emby', value: c);
    final k = i.criticRating;
    if (k != null && k > 0) m['tomatoes'] = RatingEntry('tomatoes', score: k, value: k);
    return Ratings(m);
  }

  Ratings mergedWith(Ratings fallback) {
    final m = {...fallback.entries, ...entries};
    // 已有 TMDb 分时,不再重复展示 Emby 社区分
    if (m.containsKey('tmdb') || m.containsKey('imdb')) m.remove('emby');
    return Ratings(m);
  }
}

class RatingsService {
  RatingsService(this.prefs);

  final SharedPreferences prefs;
  String? apiKey;

  static const _ttl = Duration(days: 7);
  static const _emptyTtl = Duration(days: 1);
  static const _prefix = 'ratings.v1.';

  final Map<String, Ratings> _memory = {};
  final Map<String, Future<Ratings?>> _inflight = {};

  bool get hasKey => apiKey != null && apiKey!.trim().isNotEmpty;

  Future<Ratings> forItem(MediaItem item) async {
    final fallback = Ratings.fromEmby(item);
    if (!hasKey) return fallback;
    if (!item.isMovie && !item.isSeries) return fallback;

    final imdb = item.imdbId;
    final tmdb = item.tmdbId;
    final type = item.isSeries ? 'show' : 'movie';
    final key = imdb != null && imdb.startsWith('tt')
        ? 'imdb.$imdb'
        : (tmdb != null ? 'tmdb.$type.$tmdb' : null);
    if (key == null) return fallback;

    final cached = _memory[key] ?? _readCache(key);
    if (cached != null) {
      _memory[key] = cached;
      return cached.mergedWith(fallback);
    }

    final pending = _inflight[key] ??= _fetch(imdb, tmdb, type, key).whenComplete(() {
      _inflight.remove(key);
    });
    final r = await pending;
    return r == null ? fallback : r.mergedWith(fallback);
  }

  Ratings? _readCache(String key) {
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final t = DateTime.fromMillisecondsSinceEpoch(j['t'] as int);
      final list = (j['r'] as List)
          .map((e) => RatingEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final age = DateTime.now().difference(t);
      if (age > (list.isEmpty ? _emptyTtl : _ttl)) return null;
      return Ratings({for (final e in list) e.source: e});
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, List<RatingEntry> list) async {
    await prefs.setString(
      '$_prefix$key',
      jsonEncode({
        't': DateTime.now().millisecondsSinceEpoch,
        'r': list.map((e) => e.toJson()).toList(),
      }),
    );
  }

  Future<void> clearCache() async {
    _memory.clear();
    for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await prefs.remove(k);
    }
  }

  Future<Ratings?> _fetch(String? imdb, String? tmdb, String type, String key) async {
    final k = apiKey!.trim();
    final uris = <Uri>[
      if (imdb != null && imdb.startsWith('tt'))
        Uri.https('mdblist.com', '/api/', {'apikey': k, 'i': imdb}),
      if (tmdb != null) Uri.https('mdblist.com', '/api/', {'apikey': k, 'tm': tmdb, 'm': type}),
      // 新版接口作为备用
      if (tmdb != null) Uri.https('api.mdblist.com', '/tmdb/$type/$tmdb', {'apikey': k}),
    ];
    for (final u in uris) {
      try {
        final res = await http.get(u).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) continue;
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        if (j is! Map || j['error'] != null) continue;
        final list = _parse(j['ratings']);
        await _writeCache(key, list);
        final r = Ratings({for (final e in list) e.source: e});
        _memory[key] = r;
        return r;
      } catch (_) {
        // 换下一个地址试
      }
    }
    return null;
  }

  List<RatingEntry> _parse(dynamic raw) {
    final out = <RatingEntry>[];
    if (raw is! List) return out;
    for (final e in raw) {
      if (e is! Map) continue;
      final source = e['source'];
      if (source is! String) continue;
      final score = (e['score'] as num?)?.toDouble();
      final value = (e['value'] as num?)?.toDouble();
      if ((score == null || score <= 0) && (value == null || value <= 0)) continue;
      out.add(RatingEntry(
        RatingEntry.normalize(source),
        score: (score != null && score > 0) ? score : null,
        value: value,
        votes: (e['votes'] as num?)?.toInt(),
      ));
    }
    return out;
  }
}

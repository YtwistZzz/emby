import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/media.dart';

class EmbyException implements Exception {
  EmbyException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class ItemsPage {
  ItemsPage(this.items, this.total);
  final List<MediaItem> items;
  final int total;
}

class EmbyClient {
  EmbyClient({
    required String baseUrl,
    required this.deviceId,
    this.token,
    this.userId,
    this.userName,
    http.Client? httpClient,
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final String deviceId;
  final String? token;
  final String? userId;
  final String? userName;
  final http.Client _http;

  static const clientName = 'EmbyPlayer';
  static const clientVersion = '0.1.0';

  // 列表页只取必要字段,减少流量和解析开销
  static const _listFields =
      'ProviderIds,CommunityRating,CriticRating,OfficialRating,ProductionYear,RunTimeTicks,'
      'Overview,PrimaryImageAspectRatio,ParentBackdropItemId,ParentBackdropImageTags,'
      'SeriesPrimaryImageTag,DateCreated,ChildCount,SeasonId';
  static const _detailFields =
      '$_listFields,Genres,Studios,People,Taglines,PremiereDate,MediaSources';

  static String normalizeBaseUrl(String input) {
    var s = input.trim();
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.toLowerCase().endsWith('/emby')) s = s.substring(0, s.length - 5);
    return s;
  }

  String get apiRoot => '$baseUrl/emby';

  Map<String, String> get _headers {
    final auth = StringBuffer('MediaBrowser Client="$clientName", Device="Windows PC", '
        'DeviceId="$deviceId", Version="$clientVersion"');
    if (token != null) auth.write(', Token="$token"');
    return {
      'X-Emby-Authorization': auth.toString(),
      if (token != null) 'X-Emby-Token': token!,
      'Accept': 'application/json',
    };
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null) q[k] = v.toString();
    });
    return Uri.parse('$apiRoot$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<http.Response> _send(Future<http.Response> Function() fn) async {
    try {
      return await fn().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw EmbyException('连接超时,请检查服务器地址和网络');
    } on SocketException catch (e) {
      throw EmbyException('无法连接服务器:${e.message}');
    } on http.ClientException catch (e) {
      throw EmbyException('网络错误:${e.message}');
    }
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode == 401) {
      throw EmbyException('登录已失效,请重新登录', status: 401);
    }
    if (res.statusCode >= 400) {
      throw EmbyException('服务器返回错误 ${res.statusCode}', status: res.statusCode);
    }
    if (res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<dynamic> _get(String path, [Map<String, dynamic>? query]) async {
    final res = await _send(() => _http.get(_uri(path, query), headers: _headers));
    return _decode(res);
  }

  Future<dynamic> _post(String path, {Map<String, dynamic>? query, Object? body}) async {
    final res = await _send(() => _http.post(
          _uri(path, query),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body ?? {}),
        ));
    return _decode(res);
  }

  // ───────────────────────── 登录 ─────────────────────────

  static Future<EmbyClient> login({
    required String baseUrl,
    required String username,
    required String password,
    required String deviceId,
  }) async {
    final anon = EmbyClient(baseUrl: baseUrl, deviceId: deviceId);
    final res = await anon._send(() => anon._http.post(
          anon._uri('/Users/AuthenticateByName'),
          headers: {...anon._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'Username': username, 'Pw': password, 'Password': password}),
        ));
   if (res.statusCode == 401) {
     throw EmbyException('用户名或密码错误', status: res.statusCode);
   }
   if (res.statusCode == 400 || res.statusCode == 403 || res.statusCode == 404) {
     throw EmbyException(
       '服务器拒绝了登录请求(HTTP ${res.statusCode})。请检查地址、端口和 HTTP/HTTPS 是否正确,'
       '以及这个地址确实是 Emby 服务器。',
       status: res.statusCode,
     );
   }
    final j = anon._decode(res) as Map<String, dynamic>;
    final user = j['User'] as Map<String, dynamic>;
    return EmbyClient(
      baseUrl: baseUrl,
      deviceId: deviceId,
      token: j['AccessToken'] as String,
      userId: user['Id'] as String,
      userName: user['Name'] as String?,
    );
  }

  // ───────────────────────── 浏览 ─────────────────────────

  List<MediaItem> _items(dynamic j) => ((j['Items'] as List?) ?? const [])
      .map((e) => MediaItem(Map<String, dynamic>.from(e as Map)))
      .toList();

  Future<List<MediaItem>> views() async {
    final j = await _get('/Users/$userId/Views');
    const keep = {'movies', 'tvshows', 'homevideos', 'musicvideos', 'boxsets', 'mixed'};
    return _items(j).where((v) {
      final t = v.collectionType;
      return t == null || keep.contains(t);
    }).toList();
  }

  Future<List<MediaItem>> resume({int limit = 12}) async {
    final j = await _get('/Users/$userId/Items/Resume', {
      'Limit': limit,
      'Recursive': true,
      'MediaTypes': 'Video',
      'Fields': _listFields,
      'ImageTypeLimit': 1,
      'EnableImageTypes': 'Primary,Backdrop,Thumb',
    });
    return _items(j);
  }

  Future<List<MediaItem>> nextUp({String? seriesId, int limit = 12}) async {
    final j = await _get('/Shows/NextUp', {
      'UserId': userId,
      'Limit': limit,
      'SeriesId': seriesId,
      'Fields': _listFields,
    });
    return _items(j);
  }

  Future<List<MediaItem>> latest(String parentId, {int limit = 16}) async {
    final j = await _get('/Users/$userId/Items/Latest', {
      'ParentId': parentId,
      'Limit': limit,
      'GroupItems': true,
      'Fields': _listFields,
    });
    return ((j as List?) ?? const [])
        .map((e) => MediaItem(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<ItemsPage> items({
    String? parentId,
    String? includeTypes,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    int start = 0,
    int limit = 60,
    String? search,
  }) async {
    final j = await _get('/Users/$userId/Items', {
      'ParentId': parentId,
      'IncludeItemTypes': includeTypes,
      'Recursive': true,
      'SortBy': sortBy,
      'SortOrder': sortOrder,
      'StartIndex': start,
      'Limit': limit,
      'SearchTerm': search,
      'Fields': _listFields,
      'ImageTypeLimit': 1,
      'EnableImageTypes': 'Primary,Backdrop',
    });
    return ItemsPage(_items(j), (j['TotalRecordCount'] as num?)?.toInt() ?? 0);
  }

  Future<MediaItem> item(String id) async {
    final j = await _get('/Users/$userId/Items/$id', {'Fields': _detailFields});
    return MediaItem(Map<String, dynamic>.from(j as Map));
  }

  Future<List<MediaItem>> seasons(String seriesId) async {
    final j = await _get('/Shows/$seriesId/Seasons', {'UserId': userId, 'Fields': _listFields});
    return _items(j);
  }

  Future<List<MediaItem>> episodes(String seriesId, {String? seasonId}) async {
    final j = await _get('/Shows/$seriesId/Episodes', {
      'UserId': userId,
      'SeasonId': seasonId,
      'Fields': _listFields,
    });
    return _items(j);
  }

  Future<List<MediaItem>> similar(String id, {int limit = 14}) async {
    final j = await _get('/Items/$id/Similar', {
      'UserId': userId,
      'Limit': limit,
      'Fields': _listFields,
    });
    return _items(j);
  }

  Future<void> setPlayed(String id, bool played) async {
    final uri = _uri('/Users/$userId/PlayedItems/$id');
    final res = await _send(() => played
        ? _http.post(uri, headers: _headers)
        : _http.delete(uri, headers: _headers));
    _decode(res);
  }

  // ───────────────────────── 图片 ─────────────────────────

  String imageUrl(String itemId, String type,
      {String? tag, int? maxWidth, int quality = 88, int? index}) {
    final path = '/Items/$itemId/Images/$type${index != null ? '/$index' : ''}';
    return _uri(path, {
      'maxWidth': maxWidth,
      'quality': quality,
      'tag': tag,
      'api_key': token,
    }).toString();
  }

  /// 竖版海报
  String? posterUrl(MediaItem i, {int maxWidth = 400}) {
    if (i.primaryTag != null) {
      return imageUrl(i.id, 'Primary', tag: i.primaryTag, maxWidth: maxWidth);
    }
    if (i.isEpisode && i.seriesId != null && i.seriesPrimaryTag != null) {
      return imageUrl(i.seriesId!, 'Primary', tag: i.seriesPrimaryTag, maxWidth: maxWidth);
    }
    return null;
  }

  /// 剧照 / 背景
  String? backdropUrl(MediaItem i, {int maxWidth = 1920}) {
    if (i.backdropTags.isNotEmpty) {
      return imageUrl(i.id, 'Backdrop', tag: i.backdropTags.first, maxWidth: maxWidth, index: 0);
    }
    if (i.parentBackdropItemId != null && i.parentBackdropTags.isNotEmpty) {
      return imageUrl(i.parentBackdropItemId!, 'Backdrop',
          tag: i.parentBackdropTags.first, maxWidth: maxWidth, index: 0);
    }
    return null;
  }

  /// 横版缩略图:剧集用自己的截图,电影用剧照,都没有再退回海报
  String? thumbUrl(MediaItem i, {int maxWidth = 640}) {
    if (i.isEpisode && i.primaryTag != null) {
      return imageUrl(i.id, 'Primary', tag: i.primaryTag, maxWidth: maxWidth);
    }
    return backdropUrl(i, maxWidth: maxWidth) ?? posterUrl(i, maxWidth: maxWidth);
  }

  String personImageUrl(Person p, {int maxWidth = 200}) =>
      imageUrl(p.id, 'Primary', tag: p.primaryTag, maxWidth: maxWidth);

  // ───────────────────────── 播放 ─────────────────────────

  Future<PlaybackInfo> playbackInfo(String itemId, {int startTicks = 0}) async {
    final j = await _post(
      '/Items/$itemId/PlaybackInfo',
      query: {
        'UserId': userId,
        'StartTimeTicks': startTicks,
        'IsPlayback': true,
        'AutoOpenLiveStream': true,
        'MaxStreamingBitrate': 200000000,
      },
    ) as Map<String, dynamic>;
    final sources = ((j['MediaSources'] as List?) ?? const [])
        .map((e) => MediaSource(Map<String, dynamic>.from(e as Map)))
        .toList();
    return PlaybackInfo((j['PlaySessionId'] ?? '').toString(), sources);
  }

  /// 直连播放:原文件直出,mpv 自己解码(HEVC / AV1 / DTS / PGS / ASS 都不需要服务器转码)
  String directStreamUrl(String itemId, MediaSource s, String playSessionId) {
    return _uri('/Videos/$itemId/stream', {
      'Static': true,
      'MediaSourceId': s.id,
      'PlaySessionId': playSessionId,
      'DeviceId': deviceId,
      'api_key': token,
    }).toString();
  }

  /// 直连失败时的兜底:让服务器转成 HLS
  String transcodeUrl(String itemId, MediaSource s, String playSessionId) {
    return _uri('/Videos/$itemId/master.m3u8', {
      'MediaSourceId': s.id,
      'PlaySessionId': playSessionId,
      'DeviceId': deviceId,
      'api_key': token,
      'VideoCodec': 'h264',
      'AudioCodec': 'aac',
      'VideoBitrate': 20000000,
      'AudioBitrate': 256000,
      'MaxAudioChannels': 6,
      'SegmentContainer': 'ts',
      'BreakOnNonKeyFrames': true,
    }).toString();
  }

  /// 外挂字幕(文本类)。内封字幕不用管,mpv 会直接从容器里读。
  String? externalSubtitleUrl(String itemId, MediaSource s, MediaStream sub) {
    if (!sub.isExternal) return null;
    final format = switch (sub.codec) {
      'ass' || 'ssa' => 'ass',
      'srt' || 'subrip' => 'srt',
      'vtt' || 'webvtt' => 'vtt',
      _ => '',
    };
    if (format.isEmpty) return null;
    return _uri('/Videos/$itemId/${s.id}/Subtitles/${sub.index}/Stream.$format', {
      'api_key': token,
    }).toString();
  }

  // ── Emby 自己的播放进度上报(与 Trakt 是两条独立链路)──

  Future<void> reportStart(Map<String, dynamic> body) => _quiet('/Sessions/Playing', body);
  Future<void> reportProgress(Map<String, dynamic> body) =>
      _quiet('/Sessions/Playing/Progress', body);
  Future<void> reportStopped(Map<String, dynamic> body) =>
      _quiet('/Sessions/Playing/Stopped', body);

  Future<void> _quiet(String path, Map<String, dynamic> body) async {
    try {
      await _post(path, body: body);
    } catch (_) {
      // 进度上报失败不应该打断播放
    }
  }
}

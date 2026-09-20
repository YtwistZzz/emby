import '../core/utils.dart';

class UserData {
  const UserData({
    this.positionTicks = 0,
    this.played = false,
    this.playedPercentage,
    this.unplayedItemCount,
    this.isFavorite = false,
  });

  final int positionTicks;
  final bool played;
  final double? playedPercentage;
  final int? unplayedItemCount;
  final bool isFavorite;

  factory UserData.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const UserData();
    return UserData(
      positionTicks: (j['PlaybackPositionTicks'] as num?)?.toInt() ?? 0,
      played: j['Played'] == true,
      playedPercentage: (j['PlayedPercentage'] as num?)?.toDouble(),
      unplayedItemCount: (j['UnplayedItemCount'] as num?)?.toInt(),
      isFavorite: j['IsFavorite'] == true,
    );
  }
}

class MediaStream {
  MediaStream(this.raw);
  final Map<String, dynamic> raw;

  int get index => (raw['Index'] as num?)?.toInt() ?? 0;
  String get type => (raw['Type'] as String?) ?? '';
  String get codec => ((raw['Codec'] as String?) ?? '').toLowerCase();
  String? get language => raw['Language'] as String?;
  String? get title => raw['Title'] as String?;
  String? get displayTitle => raw['DisplayTitle'] as String?;
  bool get isExternal => raw['IsExternal'] == true;
  bool get isDefault => raw['IsDefault'] == true;
  int? get width => (raw['Width'] as num?)?.toInt();
  int? get height => (raw['Height'] as num?)?.toInt();
  int? get channels => (raw['Channels'] as num?)?.toInt();
  String? get videoRange => raw['VideoRange'] as String?;

  bool get isVideo => type == 'Video';
  bool get isAudio => type == 'Audio';
  bool get isSubtitle => type == 'Subtitle';

  bool get isHdr {
    final s = '${videoRange ?? ''} ${displayTitle ?? ''} ${raw['ExtendedVideoType'] ?? ''}'
        .toLowerCase();
    return s.contains('hdr') || s.contains('dolby') || s.contains('dovi');
  }

  bool get isDolbyVision {
    final s = '${displayTitle ?? ''} ${raw['ExtendedVideoType'] ?? ''}'.toLowerCase();
    return s.contains('dolby') || s.contains('dovi');
  }
}

class MediaSource {
  MediaSource(this.raw);
  final Map<String, dynamic> raw;

  late final List<MediaStream> streams = ((raw['MediaStreams'] as List?) ?? const [])
      .map((e) => MediaStream(Map<String, dynamic>.from(e as Map)))
      .toList();

  String get id => raw['Id'] as String;
  String? get name => raw['Name'] as String?;
  String? get container => raw['Container'] as String?;
  int? get size => (raw['Size'] as num?)?.toInt();
  int? get runTimeTicks => (raw['RunTimeTicks'] as num?)?.toInt();

  MediaStream? get video => streams.where((s) => s.isVideo).firstOrNull;
  List<MediaStream> get audios => streams.where((s) => s.isAudio).toList();
  List<MediaStream> get subtitles => streams.where((s) => s.isSubtitle).toList();

  /// 画质标签:4K / HEVC / HDR / DTS 5.1 ...
  List<String> qualityTags() {
    final tags = <String>[];
    final v = video;
    if (v != null) {
      final w = v.width ?? 0;
      final h = v.height ?? 0;
      if (w >= 3600 || h >= 2000) {
        tags.add('4K');
      } else if (w >= 1800 || h >= 1000) {
        tags.add('1080p');
      } else if (w >= 1200 || h >= 700) {
        tags.add('720p');
      } else if (h > 0) {
        tags.add('${h}p');
      }
      final codecLabel = switch (v.codec) {
        'hevc' || 'h265' => 'HEVC',
        'h264' || 'avc' => 'H.264',
        'av1' => 'AV1',
        'vp9' => 'VP9',
        '' => '',
        final c => c.toUpperCase(),
      };
      if (codecLabel.isNotEmpty) tags.add(codecLabel);
      if (v.isDolbyVision) {
        tags.add('Dolby Vision');
      } else if (v.isHdr) {
        tags.add('HDR');
      }
    }
    final a = audios.where((s) => s.isDefault).firstOrNull ?? audios.firstOrNull;
    if (a != null) {
      final ch = switch (a.channels) {
        8 => ' 7.1',
        6 => ' 5.1',
        2 => ' 2.0',
        _ => '',
      };
      final codec = switch (a.codec) {
        'truehd' => 'TrueHD',
        'eac3' => 'DD+',
        'ac3' => 'DD',
        'dts' => 'DTS',
        '' => '',
        final c => c.toUpperCase(),
      };
      if (codec.isNotEmpty) tags.add('$codec$ch');
    }
    final c = container?.split(',').first;
    if (c != null && c.isNotEmpty) tags.add(c.toUpperCase());
    final sz = formatBytes(size);
    if (sz.isNotEmpty) tags.add(sz);
    return tags;
  }
}

class PlaybackInfo {
  PlaybackInfo(this.playSessionId, this.mediaSources);
  final String playSessionId;
  final List<MediaSource> mediaSources;
}

class Person {
  Person(this.raw);
  final Map<String, dynamic> raw;
  String get id => (raw['Id'] ?? '').toString();
  String get name => (raw['Name'] as String?) ?? '';
  String? get role => raw['Role'] as String?;
  String get type => (raw['Type'] as String?) ?? '';
  String? get primaryTag => raw['PrimaryImageTag'] as String?;
}

class MediaItem {
  MediaItem(this.raw);
  final Map<String, dynamic> raw;

  String get id => raw['Id'].toString();
  String get name => (raw['Name'] as String?) ?? '';
  String get type => (raw['Type'] as String?) ?? '';
  String? get overview => raw['Overview'] as String?;
  int? get year => (raw['ProductionYear'] as num?)?.toInt();
  int? get runtimeTicks => (raw['RunTimeTicks'] as num?)?.toInt();
  double? get communityRating => (raw['CommunityRating'] as num?)?.toDouble();
  double? get criticRating => (raw['CriticRating'] as num?)?.toDouble();
  String? get officialRating => raw['OfficialRating'] as String?;
  String? get seriesId => raw['SeriesId']?.toString();
  String? get seriesName => raw['SeriesName'] as String?;
  String? get seasonId => raw['SeasonId']?.toString();
  String? get collectionType => raw['CollectionType'] as String?;
  int? get childCount => (raw['ChildCount'] as num?)?.toInt();
  int? get indexNumber => (raw['IndexNumber'] as num?)?.toInt();
  int? get parentIndexNumber => (raw['ParentIndexNumber'] as num?)?.toInt();

  /// 剧集:季号 / 集号
  int? get seasonNumber => isEpisode ? parentIndexNumber : indexNumber;
  int? get episodeNumber => isEpisode ? indexNumber : null;

  bool get isMovie => type == 'Movie';
  bool get isSeries => type == 'Series';
  bool get isSeason => type == 'Season';
  bool get isEpisode => type == 'Episode';

  String get episodeCode {
    final s = parentIndexNumber;
    final e = indexNumber;
    if (s == null || e == null) return '';
    return 'S${two(s)}E${two(e)}';
  }

  late final List<String> genres =
      ((raw['Genres'] as List?) ?? const []).map((e) => e.toString()).toList();
  late final List<String> taglines =
      ((raw['Taglines'] as List?) ?? const []).map((e) => e.toString()).toList();

  /// ProviderIds 键统一小写:imdb / tmdb / tvdb ...
  late final Map<String, String> providerIds = {
    for (final e in ((raw['ProviderIds'] as Map?) ?? const {}).entries)
      e.key.toString().toLowerCase(): e.value.toString(),
  };

  String? get imdbId => providerIds['imdb'];
  String? get tmdbId => providerIds['tmdb'];

  String? get primaryTag => (raw['ImageTags'] as Map?)?['Primary'] as String?;
  List<String> get backdropTags =>
      ((raw['BackdropImageTags'] as List?) ?? const []).map((e) => e.toString()).toList();
  String? get parentBackdropItemId => raw['ParentBackdropItemId']?.toString();
  List<String> get parentBackdropTags =>
      ((raw['ParentBackdropImageTags'] as List?) ?? const []).map((e) => e.toString()).toList();
  String? get seriesPrimaryTag => raw['SeriesPrimaryImageTag'] as String?;

  late final UserData userData = UserData.fromJson(
    raw['UserData'] == null ? null : Map<String, dynamic>.from(raw['UserData'] as Map),
  );

  late final List<MediaSource> mediaSources = ((raw['MediaSources'] as List?) ?? const [])
      .map((e) => MediaSource(Map<String, dynamic>.from(e as Map)))
      .toList();

  late final List<Person> people = ((raw['People'] as List?) ?? const [])
      .map((e) => Person(Map<String, dynamic>.from(e as Map)))
      .toList();

  /// 播放进度 0~1,没有则为 null
  double? get progress {
    final rt = runtimeTicks;
    final pos = userData.positionTicks;
    if (rt == null || rt <= 0 || pos <= 0) return null;
    return (pos / rt).clamp(0.0, 1.0).toDouble();
  }

  bool get canResume => !userData.played && userData.positionTicks > 50000000; // > 5s
}

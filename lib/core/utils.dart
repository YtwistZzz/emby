String two(int n) => n.toString().padLeft(2, '0');

String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Emby 的时间单位是 tick(100 纳秒)。
Duration ticksToDuration(int ticks) => Duration(microseconds: ticks ~/ 10);
int durationToTicks(Duration d) => d.inMicroseconds * 10;

String formatRuntime(int? ticks) {
  if (ticks == null || ticks <= 0) return '';
  final m = ticksToDuration(ticks).inMinutes;
  if (m >= 60) return '${m ~/ 60} 小时 ${m % 60} 分';
  return '$m 分钟';
}

String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i >= 3 ? 1 : 0)} ${units[i]}';
}

String langName(String? code) {
  if (code == null || code.isEmpty) return '';
  switch (code.toLowerCase()) {
    case 'chi':
    case 'zho':
    case 'zh':
    case 'chs':
    case 'cht':
      return '中文';
    case 'eng':
    case 'en':
      return '英语';
    case 'jpn':
    case 'ja':
      return '日语';
    case 'kor':
    case 'ko':
      return '韩语';
    case 'fre':
    case 'fra':
    case 'fr':
      return '法语';
    case 'ger':
    case 'deu':
    case 'de':
      return '德语';
    case 'spa':
    case 'es':
      return '西班牙语';
    case 'rus':
    case 'ru':
      return '俄语';
    case 'und':
      return '';
    default:
      return code;
  }
}

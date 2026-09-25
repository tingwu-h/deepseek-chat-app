/// 时间显示：今天只显示 时:分，否则显示 月/日 时:分。
String formatTime(DateTime time) {
  final DateTime now = DateTime.now();
  final bool sameDay =
      time.year == now.year && time.month == now.month && time.day == now.day;
  final String hh = time.hour.toString().padLeft(2, '0');
  final String mm = time.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  return '${time.month}/${time.day} $hh:$mm';
}

/// 相对时间：刚刚 / N 分钟前 / N 小时前 / 昨天 / 月-日
String formatRelative(DateTime time) {
  final Duration d = DateTime.now().difference(time);
  if (d.inMinutes < 1) return '刚刚';
  if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
  if (d.inHours < 24) return '${d.inHours} 小时前';
  if (d.inDays == 1) return '昨天';
  if (d.inDays < 30) return '${d.inDays} 天前';
  return '${time.month}月${time.day}日';
}

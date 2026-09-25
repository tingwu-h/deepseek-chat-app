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

/// 会话标题：取第一条用户消息的前 18 个字。
String conversationTitle(List<String> userTexts) {
  if (userTexts.isEmpty) return '新对话';
  final String first = userTexts.first.replaceAll('\n', ' ').trim();
  if (first.isEmpty) return '新对话';
  return first.length <= 18 ? first : '${first.substring(0, 18)}…';
}

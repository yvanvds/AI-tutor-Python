/// Short HH:MM formatter for chat bubble timestamps.
String formatChatTime(DateTime? ts) {
  if (ts == null) return '';
  final dt = ts.toLocal();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

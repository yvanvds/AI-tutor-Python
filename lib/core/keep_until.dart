// How long the content of an oefening is kept (#228): until a day of the
// year — by default 1 July, after the deliberations at the end of June — at
// midnight, Belgian time.
//
// Cosmos expires a doc `ttl` seconds after its last write (`_ts`), so the
// writer turns the day into seconds at the moment it writes:
// [KeepUntil.ttlSeconds]. The day is the school's to set, as
// `TurnContentKeepUntil: "07-01"` in `config/global`.

/// A day of the year, `MM-DD`, at midnight in Brussels.
class KeepUntil {
  const KeepUntil(this.month, this.day);

  final int month;
  final int day;

  /// The end of the school year: 1 July, after the deliberations.
  static const KeepUntil schoolYearEnd = KeepUntil(7, 1);

  /// Reads `MM-DD` (`"07-01"`, also `"7-1"`); `null` when [raw] is not a
  /// day of the year — the caller then keeps [schoolYearEnd]. 29 February
  /// is a day; in a year without one it is 1 March.
  static KeepUntil? tryParse(Object? raw) {
    if (raw is! String) return null;
    final m = RegExp(r'^\s*(\d{1,2})-(\d{1,2})\s*$').firstMatch(raw);
    if (m == null) return null;
    final month = int.parse(m.group(1)!);
    final day = int.parse(m.group(2)!);
    if (month < 1 || month > 12 || day < 1) return null;
    // A leap year, so 29 February passes.
    final probe = DateTime.utc(2000, month, day);
    if (probe.month != month || probe.day != day) return null;
    return KeepUntil(month, day);
  }

  /// The first moment on this day, at midnight Belgian time, after [at].
  DateTime after(DateTime at) {
    final instant = at.toUtc();
    // A year back: in Brussels it can already be the next day — and the
    // next year — when it is not yet in UTC.
    for (var year = instant.year - 1; ; year++) {
      final candidate = _brusselsMidnight(year, month, day);
      if (candidate.isAfter(instant)) return candidate;
    }
  }

  /// The `ttl` of a doc about something that happened at [at], written at
  /// [now]: the whole seconds from [now] to [after] ([at]), at least 1 — a
  /// doc written after its day has passed expires at once rather than
  /// never.
  int ttlSeconds({required DateTime at, required DateTime now}) {
    final until = after(at);
    final ms = until.difference(now.toUtc()).inMilliseconds;
    final seconds = (ms / 1000).ceil();
    return seconds < 1 ? 1 : seconds;
  }

  @override
  String toString() =>
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is KeepUntil && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(month, day);

  /// Midnight on [year]-[month]-[day] in Brussels, as a UTC instant. Summer
  /// time (UTC+2) runs from the last Sunday of March to the last Sunday of
  /// October, switching in the night — 02:00 and 03:00 local — so midnight
  /// on the last Sunday of March is still winter time (UTC+1) and midnight
  /// on the last Sunday of October still summer time.
  static DateTime _brusselsMidnight(int year, int month, int day) {
    final date = DateTime.utc(year, month, day);
    final summer =
        date.isAfter(_lastSunday(date.year, 3)) &&
        !date.isAfter(_lastSunday(date.year, 10));
    return date.subtract(Duration(hours: summer ? 2 : 1));
  }

  static DateTime _lastSunday(int year, int month) {
    final last = DateTime.utc(year, month + 1, 0);
    return last.subtract(Duration(days: last.weekday % DateTime.daysPerWeek));
  }
}

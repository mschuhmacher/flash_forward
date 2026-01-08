import 'package:flash_forward/models/session.dart';

DateTime startOfWeek(DateTime date) {
  int weekStart = DateTime.monday;
  int difference = date.weekday - weekStart;
  if (difference < 0) difference += 7;
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).subtract(Duration(days: difference));
}

DateTime startOfLastWeek(DateTime date) {
  int weekStart = DateTime.monday;
  int difference = date.weekday - weekStart + 7;
  // if (difference < 0) difference += 7; // Only needed if weekStart is Sundays
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).subtract(Duration(days: difference));
}

DateTime firstOfMonth(DateTime date) {
  return DateTime(date.year, date.month, 1);
}

DateTime endOfWeek(DateTime date) {
  int weekEnd = DateTime.sunday;
  int difference = weekEnd - date.weekday;
  // if (difference < 0) difference += 7;
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).add(Duration(days: difference));
}

DateTime lastOfMonth(DateTime date) {
  // Move to the first day of the next month
  DateTime firstOfNextMonth =
      (date.month < 12)
          ? DateTime(date.year, date.month + 1, 1)
          : DateTime(date.year + 1, 1, 1);

  // Subtract one day to get the last day of the current month
  return firstOfNextMonth.subtract(const Duration(days: 1));
}

List<DateTime> daysInRange(DateTime first, DateTime last) {
  final dayCount = last.difference(first).inDays + 1;
  return List.generate(
    dayCount,
    (index) => DateTime.utc(first.year, first.month, first.day + index),
  );
}

List<Session> getSessionsForDay(List<Session> sessions, DateTime day) {
  return sessions
      .where(
        (session) =>
            session.date?.year == day.year &&
            session.date?.month == day.month &&
            session.date?.day == day.day,
      )
      .toList();
}

List<Session> getSessionsForRange(
  List<Session> sessions,
  DateTime start,
  DateTime end,
) {
  // Implementation example
  final days = daysInRange(start, end);

  return [for (final d in days) ...getSessionsForDay(sessions, d)];
}

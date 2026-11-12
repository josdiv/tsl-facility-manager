const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Today, 12:00", "Tomorrow, 09:30", "Yesterday, 16:00" or "05 Nov, 08:14".
String dateTimeLabel(DateTime value, DateTime now) {
  final time =
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
  final days = DateTime(
    value.year,
    value.month,
    value.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  final day = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    _ => '${value.day.toString().padLeft(2, '0')} ${_months[value.month - 1]}',
  };
  return '$day, $time';
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _fullMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Thursday, 05 November".
String longDateLabel(DateTime value) =>
    '${_weekdays[value.weekday - 1]}, '
    '${value.day.toString().padLeft(2, '0')} ${_fullMonths[value.month - 1]}';

String greetingFor(DateTime now) => switch (now.hour) {
  < 12 => 'Morning',
  < 17 => 'Afternoon',
  _ => 'Evening',
};

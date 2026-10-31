import 'package:flutter/material.dart';

import '../l10n/strings.dart';

String dateSectionOf(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (!day.isBefore(today)) return Strings.feedToday;
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  if (!day.isBefore(weekStart)) return Strings.feedThisWeek;
  return formatDate(day);
}

String formatDate(DateTime d) => '${d.day}. ${d.month}. ${d.year}';

String formatTime(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

String visitTimeLabel(DateTime visitedOn, DateTime visitedAt) =>
    dateSectionOf(visitedOn) == Strings.feedThisWeek
        ? '${visitedOn.day}. ${visitedOn.month}. · ${formatTime(visitedAt)}'
        : formatTime(visitedAt);

class DateSectionHeader extends StatelessWidget {
  const DateSectionHeader(
    this.title, {
    super.key,
    this.horizontalMargin = 16,
    this.topMargin = 20,
  });

  final String title;
  final double horizontalMargin;
  final double topMargin;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.fromLTRB(horizontalMargin, topMargin, horizontalMargin, 4),
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

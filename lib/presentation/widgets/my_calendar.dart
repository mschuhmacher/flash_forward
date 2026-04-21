import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:intl/intl.dart';

class MyCalendar extends StatefulWidget {
  const MyCalendar({super.key});

  @override
  State<MyCalendar> createState() => _MyCalendarState();
}

class _MyCalendarState extends State<MyCalendar> {
  DateTime _focusedDay = DateTime.now();
  final StartingDayOfWeek _startingDayOfWeek = StartingDayOfWeek.monday;

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionLogProvider>(
      builder: (BuildContext context, sessionData, Widget? child) {
        final headerButtonTextStyle = TextStyle(
          fontSize: 14.0,
          fontWeight: FontWeight.normal,
          letterSpacing: 0,
          color: context.colorScheme.primary,
        );

        // Build a Set of dates with logged sessions (for fast lookup)
        final Set<DateTime> datesWithSessions = {};

        for (var session in sessionData.loggedSessions) {
          if (session.completedAt != null) {
            // Normalize date to ignore time
            final normalizedDate = DateTime(
              session.completedAt!.year,
              session.completedAt!.month,
              session.completedAt!.day,
            );
            datesWithSessions.add(normalizedDate);
          }
        }

        return TableCalendar(
          firstDay: DateTime.now().subtract(Duration(days: 365 * 30)),
          lastDay: DateTime.now().add(Duration(days: 365 * 10)),

          focusedDay: _focusedDay,
          calendarFormat: sessionData.calendarFormat,
          startingDayOfWeek: _startingDayOfWeek,
          rowHeight: 42,

          // Event loader - return list with one item if day has sessions, empty otherwise
          eventLoader: (day) {
            final normalizedDay = DateTime(day.year, day.month, day.day);
            // Return a single-item list to show one dot, empty list for no dot
            return datesWithSessions.contains(normalizedDay) ? [Session] : [];
          },

          headerStyle: HeaderStyle(
            titleTextStyle: context.titleLarge,
            formatButtonTextStyle: headerButtonTextStyle,
            formatButtonDecoration: BoxDecoration(
              border: Border.fromBorderSide(
                BorderSide(color: context.colorScheme.secondary, width: 1.5),
              ),
              borderRadius: BorderRadius.all(Radius.circular(12.0)),
            ),
          ),

          calendarBuilders: CalendarBuilders(
            headerTitleBuilder: (context, day) {
              final title = DateFormat('MMMM yyyy').format(day);
              return Row(
                children: [
                  Text(title, style: context.titleLarge),
                  Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10.0,
                        vertical: 4.0,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide(
                        color: context.colorScheme.secondary,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      setState(() {
                        _focusedDay = DateTime.now();
                      });
                      sessionData.updateSelectedSessionsCalendarFormat(
                        focusedDay: _focusedDay,
                      );
                    },
                    child: Text('Today', style: headerButtonTextStyle),
                  ),
                  const SizedBox(width: 8),
                ],
              );
            },
          ),

          calendarStyle: CalendarStyle(
            defaultTextStyle: context.bodyMedium.copyWith(
              color: context.colorScheme.onSecondary,
            ),
            todayTextStyle: context.bodyMedium.copyWith(
              color: context.colorScheme.onSecondary,
            ),
            weekendTextStyle: context.bodyMedium.copyWith(
              color: context.colorScheme.onSecondary,
            ),

            todayDecoration: BoxDecoration(
              // color: context.colorScheme.secondary,
              shape: BoxShape.rectangle,
              border: Border.all(
                width: 1.5,
                color: context.colorScheme.secondary,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            markerDecoration: BoxDecoration(
              color: context.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            markerSize: 6.0, // Size of the dot
            cellPadding: EdgeInsets.only(
              bottom: 6,
              left: 2,
              right: 2,
              top: 2,
            ), // Moves the day number slightly up
            markersAnchor:
                1.4, // Moves the dot up so that it falls within the todayDecoration box
          ),

          /// Manually disabling the twoWeeks format.
          /// I only want to display twoWeeks if it can show last week and current week,
          /// but it can only show this week and next week. Since it is used to show loggedSessions,
          /// it doesn't make sense to display a future week.
          availableCalendarFormats: const {
            CalendarFormat.month: 'Month',
            CalendarFormat.week: 'Week',
          },

          onFormatChanged: (format) {
            sessionData.changeCalendarFormat(format);

            // Update the selectedSessions based on the new format. The range changes to the first day of the format.ß
            sessionData.updateSelectedSessionsCalendarFormat(
              focusedDay: _focusedDay,
            );

            // Call `setState()` when updating calendar format
            setState(() {});
          },
          onPageChanged: (focusedDay) {
            // No need to call `setState()` here
            _focusedDay = focusedDay;

            // Update the selectedSessions for the new calendarPage
            sessionData.updateSelectedSessionsCalendarFormat(
              // format: _calendarFormat,
              focusedDay: _focusedDay,
            );
          },
        );
      },
    );
  }
}

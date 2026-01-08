import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/providers/session_log_provider.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

/// TODO: add in eventLoader func. to add a marker (e.g. a dot) to each day on which a session was completed
/// TODO: add in 'today' button in the header

class MyCalendar extends StatefulWidget {
  const MyCalendar({super.key});

  @override
  State<MyCalendar> createState() => _MyCalendarState();
}

class _MyCalendarState extends State<MyCalendar> {
  DateTime _focusedDay = DateTime.now();
  StartingDayOfWeek _startingDayOfWeek = StartingDayOfWeek.monday;

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionLogProvider>(
      builder: (BuildContext context, sessionData, Widget? child) {
        // Build a Set of dates with logged sessions (for fast lookup)
        final Set<DateTime> datesWithSessions = {};

        for (var session in sessionData.loggedSessions) {
          if (session.date != null) {
            // Normalize date to ignore time
            final normalizedDate = DateTime(
              session.date!.year,
              session.date!.month,
              session.date!.day,
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

          headerStyle: HeaderStyle(titleTextStyle: context.titleLarge),

          calendarStyle: CalendarStyle(
            defaultTextStyle: context.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSecondary,
            ),
            todayTextStyle: context.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSecondary,
            ),
            weekendTextStyle: context.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSecondary,
            ),

            todayDecoration: BoxDecoration(
              // color: Theme.of(context).colorScheme.secondary,
              shape: BoxShape.rectangle,
              border: Border.all(
                width: 1.5,
                color: Theme.of(context).colorScheme.secondary,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            markerDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
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

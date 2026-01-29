import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flash_forward/models/session.dart';
import 'package:flash_forward/services/session_logger.dart';
import 'package:flash_forward/services/supabase_sync_service.dart';
import 'package:flash_forward/utils/date_utils.dart';

class SessionLogProvider extends ChangeNotifier {
  /// The below variables and functions all pertain to retrieving the logged sessions and
  /// loading the sessions within a certain timeframe, depending on the calenderFormat

  late DateTime currentDay;
  late DateTime startDay;
  late DateTime endDay;
  late CalendarFormat calendarFormat;

  SupabaseSyncService? _syncService;

  // startDay in a constructor because it uses currentDay to initialize.
  SessionLogProvider() {
    currentDay = DateTime.now();
    startDay = startOfWeek(currentDay);
    endDay = currentDay;
    calendarFormat = CalendarFormat.week;
  }

  // Define bools for loading and initializing the data
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // Initialization and getter functions for the loggedSessions and selectedSessions
  List<Session> _loggedSessions = [];
  List<Session> _selectedSessions = [];

  List<Session> get loggedSessions => _loggedSessions;
  List<Session> get selectedSessions => _selectedSessions;

  /// Initialization function called from the HomeScreen. This runs as the first thing on startup.
  /// Could have called in main.dart, but since loadLoggedSessions is async the UI was build before it finished loading,
  /// and thus selectedSessions would be empty --> triggering the ternary condition in the listView on the HomeScreen
  Future<void> init({String? userId}) async {
    if (_isInitialized) return; // avoid running twice
    _isInitialized = true;
    _isLoading = true;
    notifyListeners();

    if (userId != null) {
      _syncService = SupabaseSyncService(userId: userId);
    }

    // TODO: add in writing the defaultData here

    await loadLoggedSessions();
    updateSelectedSessionsCalendarFormat();

    _isLoading = false;
    notifyListeners();
  }

  /// Load logged sessions from cloud (or fallback to local)
  Future<void> loadLoggedSessions() async {
    if (_syncService != null) {
      // Try loading from cloud first
      try {
        _loggedSessions = await _syncService!.fetchLoggedSessions();
      } catch (e) {
        print(
          'Error loading from cloud, falling back to local: $e',
        ); //TODO: remove print in prod
        //TODO: add error handling and logging
        _loggedSessions = await SessionLogger.readLoggedSessions();
      }
    } else {
      // No user logged in, use local storage
      // readLogs is non-nullable, if errors then returns empty list
      _loggedSessions = await SessionLogger.readLoggedSessions();
      // await Future.delayed(Duration(seconds: 2)); // for testing the progressIndicator on HomeScreen
    }
  }

  void changeCalendarFormat(CalendarFormat format) {
    if (calendarFormat != format) {
      calendarFormat = format;
    }
    notifyListeners();
    // Needed?
  }

  /// Refresh selected sessions after completing a workout
  Future<void> refreshSelectedSessions(Session newSession) async {
    // Save to local storage (fast, works offline)
    await SessionLogger.logSession(newSession);

    // Save to cloud if available
    if (_syncService != null) {
      try {
        await _syncService!.logCompletedSession(newSession);
      } catch (e) {
        print('Error logging session to cloud: $e');
        // Continue anyway - at least it's saved locally
      }
    }

    // Add to in-memory list
    _loggedSessions.add(newSession);
    _selectedSessions = getSessionsForRange(_loggedSessions, startDay, endDay);
    notifyListeners();
  }

  void updateSelectedSessionsCalendarFormat({
    // required CalendarFormat format,
    DateTime? focusedDay,
  }) {
    // Update endDay if a focusedDay is provided
    if (focusedDay != null) {
      endDay = focusedDay;
    }

    // Determine the startDay based on format
    // And set endDay to the end of the week / month respectively
    switch (calendarFormat) {
      case CalendarFormat.week:
        startDay = startOfWeek(endDay);
        endDay = endOfWeek(endDay);
        break;
      case CalendarFormat.twoWeeks:
        startDay = startOfLastWeek(endDay);
        endDay = endOfWeek(endDay);

        break;
      case CalendarFormat.month:
        startDay = firstOfMonth(endDay);
        endDay = lastOfMonth(endDay);
        break;
    }
    // print('StartDay: $startDay');
    // print('EndDay: $endDay');
    _selectedSessions = getSessionsForRange(_loggedSessions, startDay, endDay);

    notifyListeners();
  }

  /// Clear all logged sessions (local and cloud)
  Future<void> clearAllLoggedSessions() async {
    _selectedSessions.clear();
    _loggedSessions.clear();

    // Clear local storage
    await SessionLogger.clearLoggedSessions();

    // Clear cloud storage if available
    if (_syncService != null) {
      try {
        await _syncService!.clearLoggedSessions();
      } catch (e) {
        print('Error clearing cloud sessions: $e');
      }
    }

    notifyListeners();
  }

  /// Reset provider state on logout
  /// This allows re-initialization with a different user
  void reset() {
    _isInitialized = false;
    _isLoading = false;
    _syncService = null;
    _loggedSessions = [];
    _selectedSessions = [];
    currentDay = DateTime.now();
    startDay = startOfWeek(currentDay);
    endDay = currentDay;
    calendarFormat = CalendarFormat.week;
    notifyListeners();
  }

  /// Check if there are pending sync operations
  bool get hasPendingSync => _syncService?.hasPendingSync ?? false;

  /// Get count of pending sync operations
  int get pendingSyncCount => _syncService?.pendingSyncCount ?? 0;

  /// Process any pending sync operations
  /// Call this when connectivity is restored
  Future<int> processPendingSync() async {
    if (_syncService == null) return 0;
    return await _syncService!.processPendingSync();
  }
}

/// Character limits for text fields to prevent UI overflow
class FieldLimits {
  // Titles
  static const int sessionTitleMaxLength = 30;
  static const int workoutTitleMaxLength = 30;
  static const int exerciseTitleMaxLength = 25;

  // Descriptions
  static const int sessionDescriptionMaxLength = 100;
  static const int workoutDescriptionMaxLength = 100;
  static const int exerciseDescriptionMaxLength = 100;

  // Sets, reps, load, timers
  static const int setLimit = 999;
  static const int repLimit = 999;
  static const int loadLimit = 9999;
  static const int timeLimit = 9999;
}

/// Reusable validators for text fields
class FieldValidators {
  static String? sessionTitle(
    String? value, {
    List<String>? existingTitles,
    String? ownTitle,
  }) {
    if (value == null || value.isEmpty) {
      return 'Please enter a title';
    }
    if (value == 'title') {
      return "Session cannot be named 'title'";
    }
    if (value.length > FieldLimits.sessionTitleMaxLength) {
      return 'Title must be ${FieldLimits.sessionTitleMaxLength} characters or less';
    }
    if (existingTitles != null) {
      final trimmed = value.trim().toLowerCase();
      final isDuplicate = existingTitles
          .where((t) => t.toLowerCase() != (ownTitle?.toLowerCase() ?? ''))
          .any((t) => t.toLowerCase() == trimmed);
      if (isDuplicate) return 'A session with this title already exists';
    }
    return null;
  }

  static String? workoutTitle(
    String? value, {
    List<String>? existingTitles,
    String? ownTitle,
  }) {
    if (value == null || value.isEmpty) {
      return 'Please enter a title';
    }
    if (value == 'title') {
      return "Workout cannot be named 'title'";
    }
    if (value.length > FieldLimits.workoutTitleMaxLength) {
      return 'Title must be ${FieldLimits.workoutTitleMaxLength} characters or less';
    }
    if (existingTitles != null) {
      final trimmed = value.trim().toLowerCase();
      final isDuplicate = existingTitles
          .where((t) => t.toLowerCase() != (ownTitle?.toLowerCase() ?? ''))
          .any((t) => t.toLowerCase() == trimmed);
      if (isDuplicate) return 'A workout with this title already exists';
    }
    return null;
  }

  static String? exerciseTitle(
    String? value, {
    List<String>? existingTitles,
    String? ownTitle,
  }) {
    if (value == null || value.isEmpty) {
      return 'Please enter a title';
    }
    if (value == 'title') {
      return "Exercise cannot be named 'title'";
    }
    if (value.length > FieldLimits.exerciseTitleMaxLength) {
      return 'Title must be ${FieldLimits.exerciseTitleMaxLength} characters or less';
    }
    if (existingTitles != null) {
      final trimmed = value.trim().toLowerCase();
      final isDuplicate = existingTitles
          .where((t) => t.toLowerCase() != (ownTitle?.toLowerCase() ?? ''))
          .any((t) => t.toLowerCase() == trimmed);
      if (isDuplicate) return 'An exercise with this title already exists';
    }
    return null;
  }

  static String? sessionDescription(String? value) {
    if (value != null &&
        value.length > FieldLimits.sessionDescriptionMaxLength) {
      return 'Description must be ${FieldLimits.sessionDescriptionMaxLength} characters or less';
    }
    return null;
  }

  static String? workoutDescription(String? value) {
    if (value != null &&
        value.length > FieldLimits.workoutDescriptionMaxLength) {
      return 'Description must be ${FieldLimits.workoutDescriptionMaxLength} characters or less';
    }
    return null;
  }

  static String? exerciseDescription(String? value) {
    if (value != null &&
        value.length > FieldLimits.exerciseDescriptionMaxLength) {
      return 'Description must be ${FieldLimits.exerciseDescriptionMaxLength} characters or less';
    }
    return null;
  }

  static String? label(String? value) {
    if (value == null || value.isEmpty || value == 'label') {
      return 'Please select a label';
    }
    return null;
  }
}

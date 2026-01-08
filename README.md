# Flash Forward

A Flutter-based climbing and calisthenics training app for iOS and Android.

## What It Does

Flash Forward helps climbers and athletes follow structured training sessions with built-in timers, progress tracking, and customizable workouts. Users can follow preset training programs or create their own sessions, workouts, and exercises.

## Features

- **Guided Training Sessions**: Follow timed workouts with automatic transitions between exercises, sets, and reps
- **Progress Tracking**: Log completed sessions with calendar view and historical data
- **Customizable Workouts**: Create custom sessions, workouts, and exercises or use the built-in preset library
- **Smart Timer System**: Automatic timing for reps, rest periods, sets, and exercise transitions
- **Label & Filter System**: Organize workouts by type (finger strength, endurance, power, etc.)

## Tech Stack

- **Framework**: Flutter 3.7+
- **State Management**: Provider
- **Database**: Supabase (PostgreSQL) + Local JSON storage
- **Authentication**: Supabase Auth
- **Local Storage**: path_provider for JSON persistence

## Project Structure
```
lib/
├── models/          # Data models (Session, Workout, Exercise)
├── providers/       # State management (Provider pattern)
├── services/        # Business logic & data services
├── presentation/    # UI screens and widgets
├── themes/          # App styling and theming
├── data/            # Default preset data
└── utils/           # Helper functions
```

## Key Concepts

- **Session**: A complete training day (e.g., "Monday Strength Training")
- **Workout**: A group of exercises (e.g., "Finger Strength Block")
- **Exercise**: Individual movements with sets/reps/timing (e.g., "Repeaters on 20mm edge")

## Development Status

Active development. Currently implementing user authentication and cloud sync for future monetization.

## Setup

1. Clone the repository
2. Run `flutter pub get`
3. Create `.env` file with Supabase credentials
4. Run `flutter run`

## Requirements

- Flutter SDK 3.7.2 or higher
- Dart 3.0+
- iOS 12.0+ / Android SDK 21+

## License

Private project - not for distribution

---

*Built for climbers who take their training seriously.*
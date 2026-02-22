import 'package:flutter/material.dart';

final TextTheme appTextTheme = TextTheme(
  displayLarge: TextStyle(
    // Use for very large headlines
    fontSize: 32,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
    height: 1.2,
  ),
  displayMedium: TextStyle(
    // Section titles
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 1.3,
  ),
  headlineSmall: TextStyle(
    // Smaller headings
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
  ),
  titleLarge: TextStyle(
    // For subtitles, list titles
    fontSize: 18,
    fontWeight: FontWeight.w500,
  ),
  titleMedium: TextStyle(
    // For subtitles, list titles
    fontSize: 16,
    fontWeight: FontWeight.w500,
  ),
  bodyLarge: TextStyle(
    // Main body text
    fontSize: 16,
    fontWeight: FontWeight.normal,
  ),
  bodyMedium: TextStyle(
    // Secondary body text
    fontSize: 14,
    fontWeight: FontWeight.normal,
  ),
  labelLarge: TextStyle(
    // Buttons / labels
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  ),
);

extension AppText on BuildContext {
  TextStyle get h1 => Theme.of(this).textTheme.displayLarge!.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  TextStyle get h2 => Theme.of(this).textTheme.displayMedium!.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  TextStyle get h3 => Theme.of(this).textTheme.headlineSmall!.copyWith(
    color: Theme.of(this).colorScheme.primary,
  );

  TextStyle get h4 => Theme.of(this).textTheme.headlineSmall!.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  TextStyle get titleLarge => Theme.of(
    this,
  ).textTheme.titleLarge!.copyWith(color: Theme.of(this).colorScheme.onSurface);

  TextStyle get titleMedium => Theme.of(this).textTheme.titleMedium!.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  TextStyle get bodyLarge => Theme.of(
    this,
  ).textTheme.bodyLarge!.copyWith(color: Theme.of(this).colorScheme.onSurface);

  TextStyle get bodyMedium => Theme.of(this).textTheme.bodyMedium!.copyWith(
    color: Theme.of(this).colorScheme.onSurface.withValues(alpha: 0.8),
  );

  TextStyle get label => Theme.of(
    this,
  ).textTheme.labelLarge!.copyWith(color: Theme.of(this).colorScheme.primary);
}

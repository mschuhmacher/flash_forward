import 'package:flutter/material.dart';

// Also define different levels of shadow (small, medium, big), so it's easy to play around with
// Make selected UI element lighter or darker than the rest, and increase shadow to push it forward

// Define main colors and lighter variants of the same color for highlighting, shadows, and depth in the design
// different shades of background color

/// Utility extension to lighten or darken HSL colors.
extension HSLColorUtils on HSLColor {
  HSLColor lighten(double amount) =>
      this.withLightness((lightness + amount).clamp(0.0, 1.0));
  HSLColor darken(double amount) =>
      this.withLightness((lightness - amount).clamp(0.0, 1.0));
}

class AppColorsLight {
  // current:
  // static final textColor = HSLColor.fromAHSL(1, 244, 0.36, 0.07).toColor();
  // static final surfaceColor = HSLColor.fromAHSL(1, 250, 0.44, 0.97).toColor();
  // static final primaryColor = HSLColor.fromAHSL(1, 248, 0.68, 0.51).toColor();
  // static final onPrimaryColor = HSLColor.fromAHSL(1, 250, 0.44, 0.97).toColor();
  // static final secondaryColor = HSLColor.fromAHSL(1, 248, 0.79, 0.74).toColor();
  // static final onSecondaryColor =
  //     HSLColor.fromAHSL(1, 244, 0.36, 0.07).toColor();
  // static final accentColor = HSLColor.fromAHSL(1, 254, 0.94, 0.61).toColor();
  // static final onAccentColor = HSLColor.fromAHSL(1, 250, 0.44, 0.97).toColor();

  static final textColor = Color(0xFF030822);
  static final backgroundColor = Color(0xFFf0f1fe);
  static final primaryColor = Color(0xFF1c29ec);
  static final primaryFgColor = Color(0xFFf0f1fe);
  static final accentColor = Color(0xFFf58c89);
  static final accentFgColor = Color(0xFF030822);
  static final secondaryColor = Color(0xFFf0ba49);
  static final secondaryFgColor = Color(0xFF030822);

  // --- Derived colors ---
  static final _hslSurface = HSLColor.fromColor(backgroundColor);
  static final _hslText = HSLColor.fromColor(textColor);

  static final surfaceDim = _adjust(_hslSurface, -0.05).toColor();
  static final surfaceBright = _adjust(_hslSurface, 0.06).toColor();

  static final surfaceContainerLowest = _adjust(_hslSurface, -0.03).toColor();
  static final surfaceContainerLow = _adjust(_hslSurface, -0.06).toColor();
  static final surfaceContainer = _adjust(_hslSurface, -0.09).toColor();
  static final surfaceContainerHigh = _adjust(_hslSurface, -0.12).toColor();
  static final surfaceContainerHighest = _adjust(_hslSurface, -0.15).toColor();

  static final onSurfaceVariant = _deriveOnSurfaceVariant(_hslText).toColor();

  // === Outline & Inverse tones ===
  static final outline =
      HSLColor.fromColor(onSurfaceVariant).lighten(0.25).toColor();

  static final inverseSurface =
      HSLColor.fromColor(
        backgroundColor,
      ).darken(0.8).toColor(); // near dark overlay
  static final inverseOnSurface =
      HSLColor.fromColor(textColor).lighten(0.9).toColor(); // white-like text

  // === helper functions ===
  static HSLColor _adjust(HSLColor base, double delta) =>
      base.withLightness((base.lightness + delta).clamp(0.0, 1.0));

  static HSLColor _deriveOnSurfaceVariant(HSLColor text) => HSLColor.fromAHSL(
    1,
    text.hue,
    text.saturation * 0.5,
    (text.lightness + 0.25).clamp(0.0, 1.0),
  );

  static final colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: primaryColor,
    onPrimary: primaryFgColor,
    secondary: secondaryColor,
    onSecondary: secondaryFgColor,
    tertiary: accentColor,
    onTertiary: accentFgColor,
    surface: backgroundColor,
    surfaceDim: surfaceDim,
    surfaceBright: surfaceBright,
    surfaceContainerLowest: surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
    onSurface: textColor,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    inverseSurface: inverseSurface,
    inversePrimary: inverseOnSurface,
    error: const Color(0xffB3261E),
    onError: const Color(0xffFFFFFF),
  );

  // // --- Derived colors ---
  // static final _hslSurface = HSLColor.fromColor(surfaceColor);
  // static final _hslText = HSLColor.fromColor(textColor);

  // static final surfaceDim = _adjust(_hslSurface, -0.05).toColor();
  // static final surfaceBright = _adjust(_hslSurface, 0.06).toColor();

  // static final surfaceContainerLowest = _adjust(_hslSurface, -0.03).toColor();
  // static final surfaceContainerLow = _adjust(_hslSurface, -0.06).toColor();
  // static final surfaceContainer = _adjust(_hslSurface, -0.09).toColor();
  // static final surfaceContainerHigh = _adjust(_hslSurface, -0.12).toColor();
  // static final surfaceContainerHighest = _adjust(_hslSurface, -0.15).toColor();

  // static final onSurfaceVariant = _deriveOnSurfaceVariant(_hslText).toColor();

  // // === Outline & Inverse tones ===
  // static final outline =
  //     HSLColor.fromColor(onSurfaceVariant).lighten(0.25).toColor();

  // static final inverseSurface =
  //     HSLColor.fromColor(
  //       surfaceColor,
  //     ).darken(0.8).toColor(); // near dark overlay
  // static final inverseOnSurface =
  //     HSLColor.fromColor(textColor).lighten(0.9).toColor(); // white-like text

  // // === helper functions ===
  // static HSLColor _adjust(HSLColor base, double delta) =>
  //     base.withLightness((base.lightness + delta).clamp(0.0, 1.0));

  // static HSLColor _deriveOnSurfaceVariant(HSLColor text) => HSLColor.fromAHSL(
  //   1,
  //   text.hue,
  //   text.saturation * 0.5,
  //   (text.lightness + 0.25).clamp(0.0, 1.0),
  // );

  // static final colorScheme = ColorScheme(
  //   brightness: Brightness.light,
  //   primary: primaryColor,
  //   onPrimary: onPrimaryColor,
  //   secondary: secondaryColor,
  //   onSecondary: onSecondaryColor,
  //   tertiary: accentColor,
  //   onTertiary: onAccentColor,
  //   surface: surfaceColor,
  //   surfaceDim: surfaceDim,
  //   surfaceBright: surfaceBright,
  //   surfaceContainerLowest: surfaceContainerLowest,
  //   surfaceContainerLow: surfaceContainerLow,
  //   surfaceContainer: surfaceContainer,
  //   surfaceContainerHigh: surfaceContainerHigh,
  //   surfaceContainerHighest: surfaceContainerHighest,
  //   onSurface: textColor,
  //   onSurfaceVariant: onSurfaceVariant,
  //   outline: outline,
  //   inverseSurface: inverseSurface,
  //   inversePrimary: inverseOnSurface,
  //   error: const Color(0xffB3261E),
  //   onError: const Color(0xffFFFFFF),
  // );
}

class AppColorsDark {
  static final textColor = HSLColor.fromAHSL(1, 245, 0.38, 0.92).toColor();
  static final surfaceColor = HSLColor.fromAHSL(1, 247, 0.54, 0.04).toColor();
  static final primaryColor = HSLColor.fromAHSL(1, 247, 0.66, 0.49).toColor();
  static final onPrimaryColor = HSLColor.fromAHSL(1, 245, 0.38, 0.92).toColor();
  static final accentColor = HSLColor.fromAHSL(1, 252, 0.82, 0.26).toColor();
  static final onAccentColor = HSLColor.fromAHSL(1, 245, 0.38, 0.92).toColor();
  static final secondaryColor = HSLColor.fromAHSL(1, 252, 0.94, 0.38).toColor();
  static final onSecondaryColor =
      HSLColor.fromAHSL(1, 245, 0.38, 0.92).toColor();

  // --- Derived colors ---
  static final _hslSurface = HSLColor.fromColor(surfaceColor);
  static final _hslText = HSLColor.fromColor(textColor);

  static final surfaceDim = _adjust(_hslSurface, -0.06).toColor();
  static final surfaceBright = _adjust(_hslSurface, 0.08).toColor();

  static final surfaceContainerLowest = _adjust(_hslSurface, 0.03).toColor();
  static final surfaceContainerLow = _adjust(_hslSurface, 0.06).toColor();
  static final surfaceContainer = _adjust(_hslSurface, 0.09).toColor();
  static final surfaceContainerHigh = _adjust(_hslSurface, 0.12).toColor();
  static final surfaceContainerHighest = _adjust(_hslSurface, 0.15).toColor();

  static final onSurfaceVariant = _deriveOnSurfaceVariant(_hslText).toColor();

  // === Outline & Inverse tones ===
  static final outline =
      HSLColor.fromColor(onSurfaceVariant).darken(0.25).toColor();

  static final inverseSurface =
      HSLColor.fromColor(
        surfaceColor,
      ).lighten(0.85).toColor(); // bright overlay
  static final inverseOnSurface =
      HSLColor.fromColor(textColor).darken(0.9).toColor(); // black-like text

  // === helper functions ===
  static HSLColor _adjust(HSLColor base, double delta) =>
      base.withLightness((base.lightness + delta).clamp(0.0, 1.0));

  static HSLColor _deriveOnSurfaceVariant(HSLColor text) => HSLColor.fromAHSL(
    1,
    text.hue,
    text.saturation * 0.5,
    (text.lightness - 0.25).clamp(0.0, 1.0),
  );

  static final colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: primaryColor,
    onPrimary: onPrimaryColor,
    secondary: secondaryColor,
    onSecondary: onSecondaryColor,
    tertiary: accentColor,
    onTertiary: onAccentColor,
    surface: surfaceColor,
    surfaceDim: surfaceDim,
    surfaceBright: surfaceBright,
    surfaceContainerLowest: surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
    onSurface: textColor,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    inverseSurface: inverseSurface,
    inversePrimary: inverseOnSurface,
    error: const Color(0xffF2B8B5),
    onError: const Color(0xff601410),
  );
}

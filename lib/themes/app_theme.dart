import 'package:flutter/material.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'app_colors.dart';

final ThemeData lightAppTheme = ThemeData(
  useMaterial3: true,
  colorScheme: AppColorsLight.colorScheme,
  textTheme: appTextTheme,
  fontFamily: 'Poppins',

  appBarTheme: const AppBarTheme(
    scrolledUnderElevation: 0,
    backgroundColor: Colors.transparent,
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColorsLight.colorScheme.primary,
      foregroundColor: AppColorsLight.colorScheme.onPrimary,
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColorsLight.colorScheme.surfaceBright, // background color
    labelStyle: appTextTheme.bodyMedium!,

    // Default border
    border: OutlineInputBorder(
      borderSide: BorderSide(
        color: AppColorsLight.colorScheme.secondary,
        width: 1.5,
      ),
      borderRadius: BorderRadius.circular(25),
    ),

    // Border when focused
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(
        color: AppColorsLight.colorScheme.secondary,
        width: 1.5,
      ),
      borderRadius: BorderRadius.circular(25),
    ),

    // Border when hovered
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(
        color: AppColorsLight.colorScheme.secondary,
        width: 1.5,
      ),
      borderRadius: BorderRadius.circular(25),
    ),

    // Border when disabled
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: AppColorsLight.colorScheme.surfaceDim,
        width: 0.8,
      ),
    ),
  ),

  // Dialog theme (for the pop-ups)
  dialogTheme: DialogThemeData(
    backgroundColor: AppColorsLight.colorScheme.surface,
  ),
  // Popup Menu theme (for the sign out)
  popupMenuTheme: PopupMenuThemeData(color: AppColorsLight.colorScheme.surface),
);

final ThemeData darkAppTheme = ThemeData(
  useMaterial3: true,
  colorScheme: AppColorsDark.colorScheme,
  textTheme: appTextTheme,
  fontFamily: 'Poppins',

  appBarTheme: const AppBarTheme(
    scrolledUnderElevation: 0,
    backgroundColor: Colors.transparent,
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColorsDark.colorScheme.primary,
      foregroundColor: AppColorsDark.colorScheme.onPrimary,
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor:
        AppColorsDark
            .colorScheme
            .surfaceBright, // background color TODO: change to surfaceDim?
    labelStyle: appTextTheme.labelLarge!.copyWith(
      color: AppColorsDark.colorScheme.primary,
    ),

    // Default border
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: AppColorsDark.colorScheme.outline,
        width: 1.0,
      ),
    ),

    // Border when focused
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: AppColorsDark.colorScheme.primary,
        width: 1.5,
      ),
    ),

    // Border when hovered
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: AppColorsDark.colorScheme.outlineVariant,
        width: 1.0,
      ),
    ),

    // Border when disabled
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: AppColorsDark.colorScheme.surfaceDim,
        width: 0.8,
      ),
    ),
  ),

  // Dialog theme (for the pop-ups)
  dialogTheme: DialogThemeData(
    backgroundColor: AppColorsDark.colorScheme.surface,
  ),
  // Popup Menu theme (for the sign out)
  popupMenuTheme: PopupMenuThemeData(color: AppColorsDark.colorScheme.surface),
);

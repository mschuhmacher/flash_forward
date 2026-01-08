import 'package:flutter/material.dart';
import 'package:flash_forward/themes/app_colors.dart'; // adjust import

class ColorSchemeDemoScreen extends StatefulWidget {
  const ColorSchemeDemoScreen({super.key});

  @override
  State<ColorSchemeDemoScreen> createState() => _ColorSchemeDemoScreenState();
}

class _ColorSchemeDemoScreenState extends State<ColorSchemeDemoScreen> {
  bool _isDark = false;

  @override
  Widget build(BuildContext context) {
    // Pick the color scheme based on toggle
    final scheme =
        _isDark ? AppColorsDark.colorScheme : AppColorsLight.colorScheme;

    final surfaceDim =
        _isDark ? AppColorsDark.surfaceDim : AppColorsLight.surfaceDim;
    final surfaceBright =
        _isDark ? AppColorsDark.surfaceBright : AppColorsLight.surfaceBright;
    final surfaceContainerLowest =
        _isDark
            ? AppColorsDark.surfaceContainerLowest
            : AppColorsLight.surfaceContainerLowest;
    final surfaceContainerLow =
        _isDark
            ? AppColorsDark.surfaceContainerLow
            : AppColorsLight.surfaceContainerLow;
    final surfaceContainer =
        _isDark
            ? AppColorsDark.surfaceContainer
            : AppColorsLight.surfaceContainer;
    final surfaceContainerHigh =
        _isDark
            ? AppColorsDark.surfaceContainerHigh
            : AppColorsLight.surfaceContainerHigh;
    final surfaceContainerHighest =
        _isDark
            ? AppColorsDark.surfaceContainerHighest
            : AppColorsLight.surfaceContainerHighest;
    final inverseSurface =
        _isDark ? AppColorsDark.inverseSurface : AppColorsLight.inverseSurface;
    final inverseOnSurface =
        _isDark
            ? AppColorsDark.inverseOnSurface
            : AppColorsLight.inverseOnSurface;

    Widget labeledBox(String label, Color background, Color textColor) {
      return Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outline, width: 0.5),
        ),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            label,
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Theme(
      data: ThemeData(colorScheme: scheme, useMaterial3: true),
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Color Scheme Demo"),
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          actions: [
            IconButton(
              icon: Icon(_isDark ? Icons.wb_sunny : Icons.nightlight_round),
              onPressed: () => setState(() => _isDark = !_isDark),
              tooltip: _isDark ? "Switch to Light Mode" : "Switch to Dark Mode",
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              Text(
                "Core Colors",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  labeledBox(
                    "primary\n(onPrimary)",
                    scheme.primary,
                    scheme.onPrimary,
                  ),
                  labeledBox(
                    "secondary\n(onSecondary)",
                    scheme.secondary,
                    scheme.onSecondary,
                  ),
                  labeledBox(
                    "tertiary\n(onTertiary)",
                    scheme.tertiary,
                    scheme.onTertiary,
                  ),
                  labeledBox("error\n(onError)", scheme.error, scheme.onError),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                "Surfaces & Variants",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  labeledBox(
                    "surface\n(onSurface)",
                    scheme.surface,
                    scheme.onSurface,
                  ),
                  labeledBox("surfaceDim", surfaceDim, scheme.onSurface),
                  labeledBox("surfaceBright", surfaceBright, scheme.onSurface),
                  labeledBox(
                    "surfaceContainerLowest",
                    surfaceContainerLowest,
                    scheme.onSurface,
                  ),
                  labeledBox(
                    "surfaceContainerLow",
                    surfaceContainerLow,
                    scheme.onSurface,
                  ),
                  labeledBox(
                    "surfaceContainer",
                    surfaceContainer,
                    scheme.onSurface,
                  ),
                  labeledBox(
                    "surfaceContainerHigh",
                    surfaceContainerHigh,
                    scheme.onSurface,
                  ),
                  labeledBox(
                    "surfaceContainerHighest",
                    surfaceContainerHighest,
                    scheme.onSurface,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                "Outline & Inverses",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  labeledBox("outline", scheme.outline, scheme.onSurface),
                  labeledBox(
                    "onSurfaceVariant",
                    scheme.onSurfaceVariant,
                    _isDark ? Colors.white : Colors.black,
                  ),
                  labeledBox(
                    "inverseSurface\n(inverseOnSurface)",
                    inverseSurface,
                    inverseOnSurface,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                "Buttons",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                    ),
                    onPressed: () {},
                    child: const Text("primary / onPrimary"),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.secondary,
                      foregroundColor: scheme.onSecondary,
                    ),
                    onPressed: () {},
                    child: const Text("secondary / onSecondary"),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      side: BorderSide(color: scheme.outline),
                    ),
                    onPressed: () {},
                    child: const Text("onSurface / outline"),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

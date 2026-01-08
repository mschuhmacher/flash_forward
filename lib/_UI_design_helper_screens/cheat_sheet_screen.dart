import 'package:flutter/material.dart';
import 'package:flash_forward/themes/app_colors.dart'; // adjust your import

class Material3ColorCheatSheet extends StatefulWidget {
  const Material3ColorCheatSheet({super.key});

  @override
  State<Material3ColorCheatSheet> createState() =>
      _Material3ColorCheatSheetState();
}

class _Material3ColorCheatSheetState extends State<Material3ColorCheatSheet> {
  bool _isDark = false;

  @override
  Widget build(BuildContext context) {
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

    Widget labeledWidget(String label, Widget child) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
          ),
          child,
        ],
      );
    }

    return Theme(
      data: ThemeData(colorScheme: scheme, useMaterial3: true),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Material 3 Cheat Sheet'),
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
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              labeledWidget(
                "Scaffold / AppBar",
                Container(
                  padding: const EdgeInsets.all(16),
                  color: scheme.surface,
                  child: Text(
                    'background: surface\ntext: onSurface',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              labeledWidget(
                "ElevatedButton",
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                  ),
                  onPressed: () {},
                  child: const Text('primary / onPrimary'),
                ),
              ),
              labeledWidget(
                "FilledButton",
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.secondary,
                    foregroundColor: scheme.onSecondary,
                  ),
                  onPressed: () {},
                  child: const Text('secondary / onSecondary'),
                ),
              ),
              labeledWidget(
                "OutlinedButton",
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.outline),
                  ),
                  onPressed: () {},
                  child: const Text('onSurface / outline'),
                ),
              ),
              labeledWidget(
                "FloatingActionButton",
                FloatingActionButton(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  onPressed: () {},
                  child: const Icon(Icons.add),
                ),
              ),
              labeledWidget(
                "Card",
                Card(
                  color: surfaceContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'surfaceContainer / onSurface',
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  ),
                ),
              ),
              labeledWidget(
                "ListTile",
                ListTile(
                  tileColor: surfaceContainerLow,
                  title: Text(
                    'surfaceContainerLow / onSurface',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                  leading: Icon(Icons.label, color: scheme.onSurface),
                  trailing: Icon(Icons.chevron_right, color: scheme.onSurface),
                ),
              ),
              labeledWidget(
                "Dialog / Alert",
                Dialog(
                  backgroundColor: surfaceBright,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'surfaceBright / onSurface',
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  ),
                ),
              ),
              labeledWidget(
                "SnackBar",
                Container(
                  color: inverseSurface,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'inverseSurface / inverseOnSurface',
                    style: TextStyle(color: inverseOnSurface),
                  ),
                ),
              ),
              labeledWidget(
                "TextField",
                TextField(
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: surfaceContainerHighest,
                    labelText: 'Hint Text',
                    labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: scheme.outline),
                    ),
                  ),
                  style: TextStyle(color: scheme.onSurface),
                ),
              ),
              labeledWidget(
                "Slider",
                Slider(
                  value: 0.5,
                  onChanged: (_) {},
                  activeColor: scheme.primary,
                  inactiveColor: scheme.surfaceVariant,
                ),
              ),
              labeledWidget(
                "Checkbox / Switch",
                Row(
                  children: [
                    Checkbox(
                      value: true,
                      onChanged: (_) {},
                      fillColor: MaterialStateProperty.all(scheme.primary),
                    ),
                    Switch(
                      value: true,
                      onChanged: (_) {},
                      activeColor: scheme.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

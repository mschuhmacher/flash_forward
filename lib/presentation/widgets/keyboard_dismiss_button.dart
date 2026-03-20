import 'package:flash_forward/themes/app_shadow.dart';
import 'package:flutter/material.dart';

/// Renders as nothing in the layout, but inserts a floating keyboard-dismiss
/// icon into the Overlay whenever the keyboard is open.
///
/// Drop this anywhere in a screen's widget tree — it self-manages its overlay.
class KeyboardDismissButton extends StatefulWidget {
  const KeyboardDismissButton({super.key});

  @override
  State<KeyboardDismissButton> createState() => _KeyboardDismissButtonState();
}

class _KeyboardDismissButtonState extends State<KeyboardDismissButton>
    with WidgetsBindingObserver {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final keyboardHeight =
        View.of(context).viewInsets.bottom / View.of(context).devicePixelRatio;
    if (keyboardHeight > 0) {
      _showOrUpdate();
    } else {
      _hide();
    }
  }

  void _showOrUpdate() {
    if (_entry == null) {
      _entry = OverlayEntry(builder: _buildButton);
      Overlay.of(context).insert(_entry!);
    } else {
      _entry!.markNeedsBuild();
    }
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  Widget _buildButton(BuildContext overlayContext) {
    final keyboardHeight = MediaQuery.of(overlayContext).viewInsets.bottom;
    final colorScheme = Theme.of(overlayContext).colorScheme;

    return Positioned(
      bottom: keyboardHeight + 8,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Container(
            width: 60,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.surfaceBright,
              borderRadius: BorderRadius.circular(12),
              border: BoxBorder.all(color: colorScheme.primary),
            ),
            child: Icon(
              Icons.keyboard_hide_rounded,
              size: 28,
              color: colorScheme.primary.withValues(alpha: 0.6),
              // Matches shadowSmall values from AppShadow
              shadows: context.shadowSmall,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

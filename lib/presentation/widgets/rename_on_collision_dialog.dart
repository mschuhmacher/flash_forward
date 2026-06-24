import 'package:flutter/material.dart';

/// Shows a dialog asking the user to pick a new title when the original title
/// already exists in the catalog.
///
/// [currentTitle] is pre-filled in the text field.
/// [existingTitles] is the set of titles the new value must not collide with.
///
/// Returns the user-chosen title, or null if the user cancelled.
Future<String?> showRenameOnCollisionDialog({
  required BuildContext context,
  required String currentTitle,
  required List<String> existingTitles,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _RenameOnCollisionDialog(
      currentTitle: currentTitle,
      existingTitles: existingTitles,
    ),
  );
}

class _RenameOnCollisionDialog extends StatefulWidget {
  const _RenameOnCollisionDialog({
    required this.currentTitle,
    required this.existingTitles,
  });

  final String currentTitle;
  final List<String> existingTitles;

  @override
  State<_RenameOnCollisionDialog> createState() =>
      _RenameOnCollisionDialogState();
}

class _RenameOnCollisionDialogState extends State<_RenameOnCollisionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentTitle);
  }

  @override
  void dispose() {
    // Close any live IME connection before disposing controllers.
    FocusManager.instance.primaryFocus?.unfocus();
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Title cannot be empty.';
    if (widget.existingTitles.contains(trimmed)) {
      return 'A catalog item with that title already exists.';
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename before restoring'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${widget.currentTitle}" already exists in the catalog. '
              'Choose a new title for the restored item.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'New title'),
              validator: _validate,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

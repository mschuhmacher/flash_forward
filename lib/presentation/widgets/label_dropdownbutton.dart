import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/models/label.dart';

class MyLabelDropdownButton extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final FormFieldValidator<String>? validator;
  final Map<String, Label> labels;
  final String hintText;
  final String labelText;

  const MyLabelDropdownButton({
    super.key,
    required this.value,
    required this.onChanged,
    this.validator,
    this.labels = kDefaultLabels,
    this.hintText = 'Label',
    this.labelText = 'Label',
  });

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: value,
      validator: validator,
      builder: (state) {
        return DropdownMenu<String>(
          initialSelection: value,
          expandedInsets: EdgeInsets.zero,
          hintText: hintText,
          label: Text(labelText),
          errorText: state.errorText,
          menuStyle: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(
              context.colorScheme.surfaceBright,
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            fillColor: context.colorScheme.surfaceBright,
            filled: true,
          ),
          onSelected: (val) {
            state.didChange(val);
            onChanged(val);
          },
          dropdownMenuEntries:
              labels.entries.map((entry) {
                return DropdownMenuEntry<String>(
                  value: entry.key,
                  label: entry.value.name,
                  leadingIcon: Icon(
                    entry.value.icon,
                    color: entry.value.color,
                    size: 20,
                  ),
                  style: ButtonStyle(
                    textStyle: WidgetStatePropertyAll(context.bodyLarge),
                  ),
                );
              }).toList(),
        );
      },
    );
  }
}

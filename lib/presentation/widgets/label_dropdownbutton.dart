import 'package:flutter/material.dart';
import 'package:flash_forward/data/labels.dart';
import 'package:flash_forward/models/label.dart';
import 'package:flash_forward/themes/app_text_styles.dart';

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
    return DropdownButtonFormField<String>(
      value: value,
      hint: Text(hintText, style: context.bodyMedium),
      items:
          labels.entries.map((entry) {
            return DropdownMenuItem<String>(
              value: entry.key,
              child: Row(
                children: [
                  Icon(entry.value.icon, color: entry.value.color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.value.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
      selectedItemBuilder: (context) {
        return labels.values.map((option) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(option.icon, color: option.color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    option.name,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: context.bodyMedium.copyWith(height: 1.25),
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
      isExpanded: true,
      borderRadius: BorderRadius.circular(25),
      decoration: InputDecoration(
        fillColor: Theme.of(context).colorScheme.surfaceBright,
      ),
      onChanged: onChanged,
      validator: validator,
    );
  }
}

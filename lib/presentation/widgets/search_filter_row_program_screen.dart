import 'package:flash_forward/presentation/widgets/label_dropdownbutton.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';

class SearchFilterRow extends StatefulWidget {
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onFilterLabelChanged;

  const SearchFilterRow({
    super.key,
    required this.onQueryChanged,
    required this.onFilterLabelChanged,
  });

  @override
  State<SearchFilterRow> createState() => _SearchFilterRowState();
}

class _SearchFilterRowState extends State<SearchFilterRow> {
  bool _isFiltering = false;
  final _searchController = TextEditingController();
  final _filterLabelController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _filterLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0),
      child: Row(
        children: [
          _isFiltering
              ? OutlinedButton(
                key: const ValueKey('searchButton'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colorScheme.onSecondary,
                  backgroundColor: context.colorScheme.surfaceBright,
                  minimumSize: const Size(0, 48),
                  iconSize: 20,
                  iconColor: context.colorScheme.onSurface,
                  side: BorderSide(
                    color: context.colorScheme.secondary,
                    width: 1.5,
                  ),
                ),
                onPressed: () => setState(() => _isFiltering = false),
                child: const Icon(Icons.search),
              )
              : SizedBox(
                key: const ValueKey('searchField'),
                height: 48,
                width: MediaQuery.of(context).size.width * 0.75,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    hintStyle: context.bodyMedium,
                    fillColor: context.colorScheme.surfaceBright,
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          FocusScope.of(context).unfocus();
                        });
                        widget.onQueryChanged('');
                      },
                    ),
                  ),
                  onChanged: widget.onQueryChanged,
                ),
              ),

          Spacer(),
          _isFiltering
              ? SizedBox(
                key: const ValueKey('filterField'),
                height: 48,
                width: MediaQuery.of(context).size.width * 0.75,
                child: Row(
                  children: [
                    Expanded(
                      child: MyLabelDropdownButton(
                        value:
                            _filterLabelController.text.isNotEmpty
                                ? _filterLabelController.text
                                : null,
                        onChanged: (value) {
                          setState(() {
                            _filterLabelController.text = value ?? '';
                          });
                          widget.onFilterLabelChanged(value);
                        },
                        validator:
                            (value) =>
                                value == null || value.isEmpty
                                    ? 'Please select a label'
                                    : null,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _isFiltering = false;
                          _filterLabelController.clear();
                          FocusScope.of(context).unfocus();
                        });
                        widget.onFilterLabelChanged(null);
                      },
                    ),
                  ],
                ),
              )
              : OutlinedButton(
                key: const ValueKey('filterButton'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colorScheme.onSecondary,
                  backgroundColor: context.colorScheme.surfaceBright,
                  minimumSize: const Size(0, 48),
                  iconSize: 20,
                  iconColor: context.colorScheme.onSurface,
                  side: BorderSide(
                    color: context.colorScheme.secondary,
                    width: 1.5,
                  ),
                ),
                onPressed: () => setState(() => _isFiltering = true),
                child: const Icon(Icons.filter_alt_outlined),
              ),
        ],
      ),
    );
  }
}

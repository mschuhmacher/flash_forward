import 'package:flash_forward/models/exercise.dart';
import 'package:flash_forward/models/superset_config.dart';
import 'package:flash_forward/themes/app_colors.dart';
import 'package:flash_forward/themes/app_text_theme.dart';
import 'package:flutter/material.dart';

/// Result returned by the superset modal.
///
/// Empty/single-member [memberIds] means the caller should dissolve the
/// superset. [dissolveRequested] is true when the user tapped the destructive
/// "Remove superset" button explicitly.
class SupersetModalResult {
  final List<String> memberIds;
  final int restSeconds;
  final int supersetSets;
  final int supersetSetRest;
  final bool dissolveRequested;

  const SupersetModalResult({
    required this.memberIds,
    required this.restSeconds,
    required this.supersetSets,
    required this.supersetSetRest,
    this.dissolveRequested = false,
  });
}

class SupersetModal extends StatefulWidget {
  final List<Exercise> workoutExercises;
  final List<SupersetConfig> otherSupersets;
  final List<Exercise> initialMembers;
  final SupersetConfig? existing;

  const SupersetModal({
    super.key,
    required this.workoutExercises,
    required this.otherSupersets,
    required this.initialMembers,
    this.existing,
  });

  @override
  State<SupersetModal> createState() => _SupersetModalState();
}

class _SupersetModalState extends State<SupersetModal> {
  late List<Exercise> _members;
  late final Set<String> _addCandidates;
  late final TextEditingController _restCtrl;
  late final TextEditingController _setsCtrl;
  late final TextEditingController _setRestCtrl;

  @override
  void initState() {
    super.initState();
    _members = List.from(widget.initialMembers);
    _addCandidates = {};
    _restCtrl = TextEditingController(
      text: '${widget.existing?.restSeconds ?? 15}',
    );
    _setsCtrl = TextEditingController(text: '${_initialSupersetSets()}');
    _setRestCtrl =
        TextEditingController(text: '${_initialSupersetSetRest()}');
  }

  /// Editing → use existing.supersetSets (or first member's sets if null).
  /// Creating with uniform members → that uniform value.
  /// Creating with mismatched members → max() — the prompt is implicit
  /// (the value is editable and the inline notice explains).
  int _initialSupersetSets() {
    if (widget.existing != null) {
      final ss = widget.existing!.supersetSets;
      if (ss != null) return ss;
      if (_members.isNotEmpty) return _members.first.sets;
      return 3;
    }
    if (_members.isEmpty) return 3;
    final setCounts = _members.map((e) => e.sets).toSet();
    if (setCounts.length == 1) return setCounts.single;
    return _members.map((e) => e.sets).reduce((a, b) => a > b ? a : b);
  }

  /// Same logic as supersetSets, but for `timeBetweenSets`. Used as the
  /// rest between rounds of the superset (routes through exerciseRest in
  /// the state machine).
  int _initialSupersetSetRest() {
    if (widget.existing != null) {
      final ssr = widget.existing!.supersetSetRest;
      if (ssr != null) return ssr;
      if (_members.isNotEmpty) return _members.first.timeBetweenSets;
      return 60;
    }
    if (_members.isEmpty) return 60;
    final restCounts = _members.map((e) => e.timeBetweenSets).toSet();
    if (restCounts.length == 1) return restCounts.single;
    return _members
        .map((e) => e.timeBetweenSets)
        .reduce((a, b) => a > b ? a : b);
  }

  @override
  void dispose() {
    // Close any live IME connection before disposing controllers.
    FocusManager.instance.primaryFocus?.unfocus();
    _restCtrl.dispose();
    _setsCtrl.dispose();
    _setRestCtrl.dispose();
    super.dispose();
  }

  void _removeMember(Exercise e) {
    setState(() => _members.remove(e));
  }

  void _toggleAdd(String id, bool? value) {
    setState(() {
      if (value == true) {
        _addCandidates.add(id);
      } else {
        _addCandidates.remove(id);
      }
    });
  }

  void _confirm() {
    // Build ordered member list: existing members keep their modal-defined
    // order; newly-checked exercises append in workout-list order.
    final memberIds = <String>[for (final e in _members) e.id];
    for (final e in widget.workoutExercises) {
      if (_addCandidates.contains(e.id) && !memberIds.contains(e.id)) {
        memberIds.add(e.id);
      }
    }
    final rest = int.tryParse(_restCtrl.text) ?? 15;
    final sets = int.tryParse(_setsCtrl.text) ?? _initialSupersetSets();
    final setRest =
        int.tryParse(_setRestCtrl.text) ?? _initialSupersetSetRest();
    Navigator.pop(
      context,
      SupersetModalResult(
        memberIds: memberIds,
        restSeconds: rest,
        supersetSets: sets,
        supersetSetRest: setRest,
      ),
    );
  }

  void _confirmDissolve() {
    Navigator.pop(
      context,
      const SupersetModalResult(
        memberIds: [],
        restSeconds: 0,
        supersetSets: 0,
        supersetSetRest: 0,
        dissolveRequested: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memberIds = _members.map((e) => e.id).toSet();
    final addable = widget.workoutExercises.where((e) {
      if (memberIds.contains(e.id)) return false;
      for (final ss in widget.otherSupersets) {
        if (ss.exerciseIds.contains(e.id)) return false;
      }
      return true;
    }).toList();

    final mismatched = widget.existing == null &&
        _members.map((e) => e.sets).toSet().length > 1;
    final restMismatched = widget.existing == null &&
        _members.map((e) => e.timeBetweenSets).toSet().length > 1;

    return AlertDialog(
      title: Text(widget.existing == null ? 'Create superset' : 'Edit superset'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Members',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (_members.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No members yet — add exercises below.'),
                ),
              if (_members.isNotEmpty)
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // Disable Flutter's default trailing drag handle — our
                  // trailing slot is occupied by the delete icon. Use an
                  // explicit leading handle below.
                  buildDefaultDragHandles: false,
                  itemCount: _members.length,
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      final m = _members.removeAt(oldIndex);
                      _members.insert(newIndex, m);
                    });
                  },
                  itemBuilder: (ctx, i) {
                    final e = _members[i];
                    return ListTile(
                      key: ValueKey(e.id),
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle_rounded),
                      ),
                      title: Text(e.title),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _removeMember(e),
                        tooltip: 'Remove from superset',
                      ),
                    );
                  },
                ),
              const SizedBox(height: 16),
              if (addable.isNotEmpty) ...[
                const Text('Add exercises',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                ...addable.map((e) => CheckboxListTile(
                      dense: true,
                      title: Text(e.title),
                      value: _addCandidates.contains(e.id),
                      onChanged: (v) => _toggleAdd(e.id, v),
                    )),
                const SizedBox(height: 16),
              ],
              if (mismatched)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: context.colorScheme.tertiaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Members have different set counts (${_members.map((e) => e.sets).join(', ')}). '
                    'Pick the number of sets the whole superset will run.',
                    style: context.bodyMedium,
                  ),
                ),
              Row(
                children: [
                  const Expanded(child: Text('Sets')),
                  SizedBox(
                    width: 60,
                    child: TextFormField(
                      controller: _setsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            vertical: 8, horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('Rest between exercises (s)')),
                  SizedBox(
                    width: 60,
                    child: TextFormField(
                      controller: _restCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            vertical: 8, horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (restMismatched)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: context.colorScheme.tertiaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Members have different rest-between-sets values '
                    '(${_members.map((e) => e.timeBetweenSets).join(', ')}). '
                    'Pick the rest between rounds for the whole superset.',
                    style: context.bodyMedium,
                  ),
                ),
              Row(
                children: [
                  const Expanded(child: Text('Rest between rounds (s)')),
                  SizedBox(
                    width: 60,
                    child: TextFormField(
                      controller: _setRestCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            vertical: 8, horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.existing != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: _confirmDissolve,
                    icon: Icon(Icons.link_off_rounded,
                        color: context.colorScheme.error),
                    label: Text(
                      'Remove superset',
                      style: context.bodyMedium
                          .copyWith(color: context.colorScheme.error),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _confirm,
          child: Text(widget.existing == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

Future<SupersetModalResult?> showSupersetModal({
  required BuildContext context,
  required List<Exercise> workoutExercises,
  required List<SupersetConfig> otherSupersets,
  required List<Exercise> initialMembers,
  SupersetConfig? existing,
}) =>
    showDialog<SupersetModalResult>(
      context: context,
      builder: (_) => SupersetModal(
        workoutExercises: workoutExercises,
        otherSupersets: otherSupersets,
        initialMembers: initialMembers,
        existing: existing,
      ),
    );

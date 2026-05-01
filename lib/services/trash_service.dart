import 'dart:convert';
import 'dart:io';
import 'package:flash_forward/models/trash_entry.dart';
import 'package:path_provider/path_provider.dart';

class TrashService {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/trash.json');
  }

  Future<List<TrashEntry>> readAll() async {
    final file = await _file();
    if (!await file.exists()) return [];
    final content = await file.readAsString();
    if (content.isEmpty) return [];
    final data = json.decode(content) as List<dynamic>;
    return data
        .map((e) => TrashEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> add(TrashEntry entry) async {
    final entries = await readAll();
    entries.removeWhere((e) => e.id == entry.id);
    entries.add(entry);
    await _write(entries);
  }

  Future<TrashEntry?> restore(String id) async {
    final entries = await readAll();
    final index = entries.indexWhere((e) => e.id == id);
    if (index == -1) return null;
    final entry = entries.removeAt(index);
    await _write(entries);
    return entry;
  }

  Future<int> purgeOlderThan(Duration ttl, {DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(ttl);
    final entries = await readAll();
    final before = entries.length;
    entries.removeWhere((e) => e.deletedAt.isBefore(cutoff));
    await _write(entries);
    return before - entries.length;
  }

  Future<void> _write(List<TrashEntry> entries) async {
    final file = await _file();
    await file.writeAsString(
      json.encode(entries.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }
}

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

  /// Purges entries older than [ttl] from the local trash file and returns the
  /// ids that were removed. Callers that also sync to the cloud use the returned
  /// ids to delete the corresponding cloud rows.
  ///
  /// Default-derived entries (a deleted/customized default — `shadowId != id`,
  /// i.e. `templateId` is set) are **never** auto-purged: they are the durable
  /// record that keeps a stock default hidden, and there are only ever a few.
  Future<List<String>> purgeOlderThan(Duration ttl, {DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(ttl);
    bool isExpired(TrashEntry e) =>
        e.deletedAt.isBefore(cutoff) && e.shadowId == e.id;
    final entries = await readAll();
    final purged = entries.where(isExpired).toList();
    if (purged.isEmpty) return const [];
    entries.removeWhere(isExpired);
    await _write(entries);
    return purged.map((e) => e.id).toList();
  }

  /// Removes every entry from the local trash file (used by factory reset).
  Future<void> clear() async => _write(const []);

  Future<void> _write(List<TrashEntry> entries) async {
    final file = await _file();
    await file.writeAsString(
      json.encode(entries.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }
}

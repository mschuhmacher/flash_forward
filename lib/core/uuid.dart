/// Shared UUID helpers.
///
/// Single source of truth for "is this string a UUID?" — used by the sync
/// queue (to drop poison ops whose entity id is a non-uuid slug) and by the
/// catalog heal (to detect slug-id user items that must be re-id'd).
library;

final RegExp _uuidRe = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Returns true if [s] is a canonical 8-4-4-4-12 hex UUID.
bool isUuid(String s) => _uuidRe.hasMatch(s);

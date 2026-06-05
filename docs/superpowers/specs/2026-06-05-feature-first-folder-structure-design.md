# Feature-first folder structure (logic layers)

**Date:** 2026-06-05
**Status:** Approved design — ready for implementation planning
**Scope:** Reorganize `lib/providers/`, `lib/services/`, `lib/utils/` into a feature-first structure. Logic layers only; UI co-location deferred.

## Motivation

The codebase splits logic across three role-based folders — `providers/` (15 files), `services/` (10), `utils/` (4) — and the boundaries have become leaky:

- **`providers/` conflates state with helpers.** Only 7 of 15 files are `ChangeNotifier`s; the other 8 are non-notifier helpers that landed there by proximity during a recent refactor (`session_state_machine`, `session_progress`, `sound_dispatcher`, `session_telemetry_recorder`, `preset_loader`, `preset_sync_merger`, `edit_commit_controller`, `synced_item_ops`).
- **`services/` vs `utils/` is a fuzzy line.** Both hold stateless code. You cannot articulate why `progress_extractor` is a "service" but `superset_utils` is a "util" — they are the same kind of thing (pure functions on models).
- **`presentation/` is already feature-organized** (`session_flow/`, `catalog_flow/`, `auth_flow/`, `profile_flow/`), while the logic layers are role-organized. The mismatch is the deeper tension.

The dependency direction across layers is otherwise clean (providers → services → models; no upward imports), so this is a re-grouping, not an untangling.

## Goals

- Group logic by feature, not by technical role.
- Make each feature folder cohesive and (at the inter-feature level) acyclic.
- Pure file-moves plus import-path updates. **No logic changes.**

## Non-goals (explicitly out of scope)

- **UI co-location.** `presentation/` stays as-is; co-locating screens/widgets into features is a deferred follow-up. Only its import paths change.
- **Breaking the catalog↔trash coupling.** Trash and catalog are two halves of one bounded context (see below); their coupling is intra-feature and stays as-is. No interface/port inversion.
- **Moving `isMaxExercise`/`sessionHasMaxExercise` onto the `Exercise` model.** A reasonable micro-refactor, but not bundled here.
- **`models/`, `data/`, `constants/`, `themes/`.** Unchanged.

## Target layout

```
lib/
├── features/
│   ├── auth/
│   │   ├── auth_provider.dart
│   │   └── auth_service.dart
│   ├── catalog/                    # saved library: presets, editing, trash
│   │   ├── catalog_provider.dart
│   │   ├── edit_commit_controller.dart
│   │   ├── preset_loader.dart
│   │   ├── preset_sync_merger.dart
│   │   ├── preset_logger.dart
│   │   ├── trash_provider.dart
│   │   └── trash_service.dart
│   ├── session_active/             # running a session
│   │   ├── session_state_provider.dart
│   │   ├── session_state_machine.dart
│   │   ├── session_progress.dart
│   │   ├── session_telemetry_recorder.dart
│   │   ├── sound_dispatcher.dart
│   │   ├── audio_beep_player.dart
│   │   └── beep_scheduler.dart
│   └── session_log/                # historical completed sessions + analysis
│       ├── session_log_provider.dart
│       ├── session_logger.dart
│       └── progress_extractor.dart
├── core/
│   ├── settings_provider.dart
│   ├── nullable.dart
│   ├── date_utils.dart
│   ├── timer_utils.dart
│   ├── superset_utils.dart
│   └── sync/
│       ├── supabase_config.dart
│       ├── supabase_sync_service.dart
│       ├── sync_queue_service.dart
│       ├── synced_item_ops.dart
│       └── sync_status_provider.dart
├── models/          # unchanged
├── presentation/    # unchanged (import paths update only)
├── data/            # unchanged
├── constants/       # unchanged
├── themes/          # unchanged
└── main.dart        # import paths update only
```

The old `providers/`, `services/`, `utils/` folders are removed. Folders are **flat** inside each feature (chosen over nested-by-role to avoid recreating the split this refactor escapes; role is conveyed by filename suffix, e.g. `_provider`, `_service`).

## Complete file-move mapping

All 29 files in the three old folders are placed.

| Old path | New path |
|---|---|
| `providers/auth_provider.dart` | `features/auth/auth_provider.dart` |
| `services/auth_service.dart` | `features/auth/auth_service.dart` |
| `providers/catalog_provider.dart` | `features/catalog/catalog_provider.dart` |
| `providers/edit_commit_controller.dart` | `features/catalog/edit_commit_controller.dart` |
| `providers/preset_loader.dart` | `features/catalog/preset_loader.dart` |
| `providers/preset_sync_merger.dart` | `features/catalog/preset_sync_merger.dart` |
| `services/preset_logger.dart` | `features/catalog/preset_logger.dart` |
| `providers/trash_provider.dart` | `features/catalog/trash_provider.dart` |
| `services/trash_service.dart` | `features/catalog/trash_service.dart` |
| `providers/session_state_provider.dart` | `features/session_active/session_state_provider.dart` |
| `providers/session_state_machine.dart` | `features/session_active/session_state_machine.dart` |
| `providers/session_progress.dart` | `features/session_active/session_progress.dart` |
| `providers/session_telemetry_recorder.dart` | `features/session_active/session_telemetry_recorder.dart` |
| `providers/sound_dispatcher.dart` | `features/session_active/sound_dispatcher.dart` |
| `services/audio_beep_player.dart` | `features/session_active/audio_beep_player.dart` |
| `services/beep_scheduler.dart` | `features/session_active/beep_scheduler.dart` |
| `providers/session_log_provider.dart` | `features/session_log/session_log_provider.dart` |
| `services/session_logger.dart` | `features/session_log/session_logger.dart` |
| `services/progress_extractor.dart` | `features/session_log/progress_extractor.dart` |
| `providers/settings_provider.dart` | `core/settings_provider.dart` |
| `utils/nullable.dart` | `core/nullable.dart` |
| `utils/date_utils.dart` | `core/date_utils.dart` |
| `utils/timer_utils.dart` | `core/timer_utils.dart` |
| `utils/superset_utils.dart` | `core/superset_utils.dart` |
| `services/supabase_config.dart` | `core/sync/supabase_config.dart` |
| `services/supabase_sync_service.dart` | `core/sync/supabase_sync_service.dart` |
| `services/sync_queue_service.dart` | `core/sync/sync_queue_service.dart` |
| `providers/synced_item_ops.dart` | `core/sync/synced_item_ops.dart` |
| `providers/sync_status_provider.dart` | `core/sync/sync_status_provider.dart` |

## Key placement decisions and rationale

- **Trash lives in `catalog`, not `sync`.** `TrashProvider` is constructed with a `CatalogProvider` and drives catalog mutations during restore/heal (`upsertSession/Workout/Exercise`, `removeSessionLocal`, `presetSessions`…); `CatalogProvider` holds a `TrashProvider?`, listens to it, and filters its merged lists by `trashedIdsOf(...)`. They are two halves of one bounded context — the saved library and its trash can. Placing trash with catalog makes this tight coupling *intra-feature* (acceptable) instead of an inter-feature cycle.

- **Sync is `core/` infrastructure, not a feature.** After trash moves to catalog, what remains (`supabase_sync_service`, `sync_queue_service`, `synced_item_ops`, `sync_status_provider`, `supabase_config`) has no domain knowledge, no user-facing story, and no upward dependencies — it is plumbing every feature depends on. That is the definition of `core` infrastructure. This is also what makes the inter-feature graph acyclic: the only back-edge into catalog was `trash → catalog`, which is now internal to the catalog feature.

- **`session` is split into `session_active` and `session_log`.** Running a session (state machine, sound, telemetry) is a distinct concern from the store of historical completed sessions (`session_logger` file persistence + `session_log_provider` read model/calendar).

- **`progress_extractor` lives in `session_log`.** It is a pure, stateless transform on a `List<Session>` it is handed (imports only models; computes `extractLoads`/`extractGrades`/`extractBodyWeight`/`discoverMaxExercises`). It reads nothing from `session_logger` directly. Its dominant use is longitudinal charts over logged sessions (profile screens, 2×); its single active-session use (`session_active_bottom_bar`) is itself a read over logged history (`lastKnownBodyWeight(sessionLogData.loggedSessions)`) plus a trivial `isMaxExercise` label check. So it belongs with the historical-sessions folder it analyzes, not the active-session subsystem.

- **`superset_utils` and `date_utils` go to `core/` (flat).** `superset_utils` is domain logic about exercises/supersets/workouts consumed by *both* catalog and session_active — cross-feature, so it has no single home feature. `date_utils` is generic date formatting (only `session_log_provider` uses it today, but it is not session-specific).

- **`settings_provider` goes to `core/`.** App-wide settings read across features (session_active, sound_dispatcher, and several screens).

## Inter-feature dependency shape (post-move)

- `core/` (incl. `core/sync/`) depends only on `models/`. Nothing points back into the features.
- `auth`, `catalog`, `session_active`, `session_log` depend downward on `core/` and on `models/`.
- `catalog` contains the previously-cyclic `catalog ↔ trash` coupling internally.
- No inter-feature cycles.

## Import-update strategy

65 files reference the old `providers/ | services/ | utils/` path segments (41 in `lib/`, 24 in `test/`).

1. **Move the 29 files** to their new paths (preserve git history with `git mv`).
2. **Rewrite imports** across `lib/` and `test/`. Most are package imports (`package:flash_forward/<old>/<file>.dart`); rewrite each old path → new path per the mapping table. This is a mechanical, scriptable find/replace keyed on the 29 filenames.
3. **Fix relative imports inside moved files.** Some movers use relative imports (e.g. `catalog_provider.dart` → `../models/session.dart`, `../data/default_session_data.dart`; `auth_service.dart` → `../models/user_profile.dart`; `session_logger.dart` → `../models/session.dart`). The new depth differs (`features/<x>/` and `core/sync/` are deeper than the old single-level folders), so these break. Convert all relative imports in moved files to `package:flash_forward/...` imports for consistency and depth-independence.

## Test layout

`test/` currently mirrors the old structure (`test/providers/`, `test/services/`, `test/utils/`). Mirror the new layout: move test files to `test/features/<feature>/` and `test/core/[sync/]` matching their subject, and update their imports. Tests follow the logic they cover, keeping parity with `lib/`.

## Verification

No behavior changes are intended, so the existing suite is the safety net:

- `flutter analyze` — zero new errors (catches missed/broken imports).
- `scripts/run_tests.sh` — full suite green (project's required test runner; avoids oversized output).
- Spot-check that no `import .../providers/`, `.../services/`, or `.../utils/` references remain anywhere in `lib/` or `test/`.
- Confirm the three old folders are empty and removed.

## Risks

- **Missed import reference** → caught by `flutter analyze` before tests.
- **Relative-import breakage from depth change** → mitigated by converting all moved-file relative imports to package imports (step 3).
- **Churn in git blame** → mitigated by `git mv` (preserves history) and keeping this a moves-only commit with no logic edits, so review is path-diff only.

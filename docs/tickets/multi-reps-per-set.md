# Multi-reps-per-set

## Summary

`Exercise.reps` is a single `int?` today, encoding "do this many reps every set." Many training schemes (descending sets, pyramid, rep-ranges) need a per-set plan, e.g. `[8, 8, 6, 6]` or `[10, 8, 6]`.

## Why

- Real-world programs don't always use a flat rep count per set.
- Tied to the [edit-logged-set-values](edit-logged-set-values.md) ticket: once the *plan* is per-set, editing the *actual* (`SetEvent.repsCompleted`) is naturally per-set too. Co-designing these avoids two UI rewrites.

## Scope

- Decide model shape: `repsPerSet: List<int>?` alongside (or replacing) `reps: int?`. Open question whether to keep `reps` as a derived getter for backward compatibility or migrate fully.
- Migration for existing presets and active sessions (single value → list of same value).
- Update `setsForExerciseInWorkout`, `_getDurationForPhase`, and the per-set rep counter in `SessionStateProvider` to read from the per-set plan.
- Update the per-exercise edit modal (`_showEditExerciseDialog`) to show per-set rep editing instead of a single field.
- Update `NewExerciseScreen` (or wherever exercises are created/edited in the catalog) to match.

## Out of scope

- Per-set load / RPE / time. Could be follow-up tickets but not bundled here unless trivial.

## Related

- [edit-logged-set-values](edit-logged-set-values.md) — should ship together or immediately after.
- Mid-session structural editor (shipped) — already supports clamping current progress when `reps` changes. Will need clamp logic updated when `reps` becomes a list.

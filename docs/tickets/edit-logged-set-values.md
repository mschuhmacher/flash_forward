# Edit logged set values

## Summary

Allow users to correct values on a completed `SetEvent` — primarily `repsCompleted`, likely also `load` and `rpe` — from the existing logged-session view on the home page.

## Why

The mid-session structural editor edits the *plan* (what the user intends to do going forward). It deliberately does not touch `_setEvents` because the log records what actually happened. But users genuinely need to correct the log too: "I did 6 reps instead of 8 on that set." That correction belongs on the log object, not the plan.

The home page already hosts logged-session viewing (`home_screen.dart`), so it's the natural surface for this. No new top-level navigation needed.

## Scope

- From a logged session on the home page, allow tapping a completed set to edit its logged values.
- Fields: `repsCompleted` (definite), `load` and `rpe` (likely — confirm during design).
- Persist edits to the same store the logged session lives in (Supabase / local cache via the existing session-persistence path).
- No retroactive recomputation of `SessionSummary` totals unless the edited field affects them. `repsCompleted` doesn't affect time totals, so summary likely stays stable. `load` and `rpe` are not in the summary today either.

## Out of scope

- Editing `RestEvent` durations. Time tracking is the source of truth; user-edited durations would corrupt analytics.
- Bulk edit ("change reps on all sets of this exercise"). Per-set only.
- Mid-session log editing. The log is only editable from the post-session review surface, not from the active session.

## Design questions to resolve

- Tap-target: tap the set row directly, or a dedicated edit affordance (icon, slidable)?
- Validation: clamp `repsCompleted` to what range? Probably `0..planned reps * 2` to allow over- and under-performance without typo accidents.
- Display: should edited sets be visually marked ("edited" badge) for honesty about the log?

## Related

- [multi-reps-per-set](multi-reps-per-set.md) — should ship together or immediately after. Once the plan is per-set, the edit UI naturally mirrors that shape.
- Mid-session structural editor (shipped) — deliberately leaves `_setEvents` untouched; this ticket fills that gap from the correct surface.

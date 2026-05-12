# Flash Forward v2.1.0 — Release Notes

## What's new

### Supersets

You can now group exercises in a workout into supersets — back-to-back sets with a short configurable rest between them instead of the full exercise rest.

- **Create a superset** from the workout editor: swipe left on any exercise and tap the new Superset action. Pick "Create new superset" or add the exercise to an existing superset in the same workout.
- **Superset modal** lets you manage members (add or remove exercises), set a shared set count (`supersetSets`) for the whole group, and configure the intra-superset rest duration. A "Remove superset" button at the bottom dissolves the group while keeping all exercises in the workout.
- **Color bar** on each exercise card shows which superset the exercise belongs to — the same color appears in the session player during that group's sets and rest phase.
- **Whole-block reorder**: dragging any member of a superset moves the entire block. Members can only be reordered relative to each other via the modal.
- **`supersetSets` in session**: if a superset has a shared set count, the sets field for all members is driven by that value during an active session. Editing sets mid-session or from the catalog updates `supersetSets`, not the individual exercise — all members in the group reflect the change immediately.
- **`supersetRest` phase** in the session player shows a countdown and color-coded header between exercises in a group so you always know how long before the next movement.

---

### Smarter propagation — per-consumer checkbox selection

When you save a catalog item (workout or exercise) that is used in multiple sessions or workouts, the propagation prompt now shows a **checkbox for each consumer** instead of a binary "keep local / update all" choice.

- All consumers are checked by default — confirming without changes matches the previous behaviour.
- Uncheck any session or workout to leave it on the previous version and only push the update to the ones you selected.
- "Select all" / "Select none" shortcuts are available per section.
- When a workout and one of its exercises both changed, the prompt groups them into separate sections so each can be propagated independently.

---

### Unified edit model and 90-day trash

Editing catalog items is now cleaner and safer end-to-end.

**Edit model changes**

- Editing a default workout or exercise no longer silently creates a fork — it edits in place. The first save promotes it into your personal catalog at the same ID; defaults remain seeded but are shadowed by your copy.
- Nested edits (exercise inside a workout, workout inside a session) now stay **local until the outermost Save fires**. Cancelling at any level discards all pending changes below it — nothing reaches the catalog until you confirm.
- A single combined propagation prompt covers all changes accumulated across a nested edit in one pass.

**Trash**

- Deleting any catalog item (session, workout, or exercise — including defaults) now moves it to a **90-day trash** instead of permanently removing it.
- The confirmation dialog lists every session or workout that currently uses the item so you know what the delete affects. Items in other sessions are not removed — they keep their embedded copy.
- An **Undo snackbar** appears for 5 seconds after each delete so you can recover immediately without going into settings.
- Deleted items sync to your account and appear in trash on all your devices.

**Restore items (Settings)**

- A new **Restore items** screen in Settings (replaces the old "Restore defaults" button) shows everything in your trash organized by type — Sessions, Workouts, Exercises.
- Each row shows the item name and an "Expires in N days" label (turns red when fewer than 7 days remain).
- Select any combination and tap **Restore selected**. If a restored item's name conflicts with something already in your catalog, a rename dialog lets you pick a new name before restoring.

**Save to catalog**

- A new **Save to catalog** slidable action appears on workout cards inside a session edit and on exercise cards inside a workout edit — visible whenever the item's ID is not already in your catalog.
- Tapping it lifts the embedded item into your personal catalog. A rename dialog fires if the name would collide with an existing catalog item.

---

## Bug fixes

- Propagating a workout edit no longer resets the workout to its catalog ID inside sessions that already had a custom embedded copy.
- Edits to an exercise opened from inside a workout edit no longer mutate the catalog object before you tap Save.
- Deduplication fixed for sessions and workouts when computing which consumers are affected by a propagation.
- Catalog workouts are now correctly included when computing exercise propagation targets.
- Propagating session changes now promotes default sessions into the user list so the update is persisted.
- Restoring defaults after a delete no longer conflicts with trash state — cloud catalog tables are kept in sync with local trash on each sync cycle.

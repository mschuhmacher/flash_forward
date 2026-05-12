# Flash Forward v2.1.0 — Release Notes

## New features

### View logged session details
Tapping a session in the history list on the Home screen now opens a detail sheet showing every workout and exercise that was logged — the same card layout used in the session editor. Logged sessions can also be deleted directly from the list with a swipe.

### Filter progress chart by value
The progress chart now supports tap-to-filter: tap any data point or label to narrow the view to that value.

### Audio beeps before a rep starts
The app now plays a short 3-count audio beep sequence in the final seconds before the rest period ends — so you can hear when it's time to go without watching the screen. The beeps work in the background and with the screen off. A rationale dialog asks for exact-alarm permission the first time you start a session (Android). Four sound modes are available: notification, in-app audio, both, or silent.

### Timer keeps running with the screen off or in another app
The session timer is now driven by elapsed wall-clock time rather than tick counts. Locking the screen or switching apps no longer causes the timer to drift or stop. When you return to the app, the timer reconciles automatically.

### Rest overtime
When the rest period ends, the timer can now enter **overtime** instead of auto-advancing. During overtime the counter ticks upward so you can see how long you've been resting over. Long-press the pause button at any point to enter overtime manually. A setting in the session menu controls whether overtime kicks in automatically when you're in the background.

### Supersets
Exercises in a workout can now be grouped into a **superset** — a chain of sets performed back-to-back with a short configurable rest between them.

- Swipe left on any exercise in the workout editor and tap **Superset** to create a new superset or add the exercise to an existing one.
- The **superset modal** lets you manage members, set a shared set count for the whole group, configure the intra-superset rest, and dissolve the group.
- Each superset gets a **color bar** on its exercise cards so you can identify groups at a glance. The same color appears in the session player during the group's sets and the rest between them.
- Dragging any member moves the **entire block** as a stack. Members can be reordered relative to each other inside the modal.
- A new **supersetRest phase** in the session player shows a countdown and the name of the next exercise before each movement in the group.
- Editing the sets field during a session (or from the catalog) writes to the superset's shared set count — all members reflect the change immediately.
- Two default workouts now include supersets to demonstrate the feature.

### Per-consumer checkbox propagation
When you save a catalog item that is used in multiple sessions or workouts, the propagation prompt now shows a **checkbox for each consumer** instead of a binary keep/update choice. Uncheck any session or workout to leave it on the previous version. All consumers are checked by default, so confirming without changes matches the previous behavior. "Select all" and "Select none" shortcuts are available per section.

### 90-day trash
Deleting a session, workout, or exercise from the catalog now moves it to a **90-day trash** instead of permanently removing it.

- The confirmation dialog lists every session or workout currently using the item.
- An **Undo snackbar** appears for 5 seconds after each delete.
- Trash syncs to your account and is visible across all your devices.
- A new **Restore items** screen in Settings (replacing "Restore defaults") shows everything in your trash organized by type. Each row shows the item name and "Expires in N days" (turns red when fewer than 7 days remain). Select any combination and tap **Restore selected**; a rename dialog fires if the name would conflict with something already in your catalog.

### Unified edit model
Editing a catalog item no longer silently creates a hidden fork.

- Default items now edit in place — the first save promotes the item into your personal catalog at the same ID; defaults are shadowed by your copy.
- Nested edits (exercise inside a workout, workout inside a session) stay local until the outermost Save fires. Cancelling at any level discards all pending changes below it.
- A single combined propagation prompt covers all changes accumulated during a nested edit in one pass.
- A new **Save to catalog** slidable action on embedded workout and exercise cards lets you lift a session-embedded item into your personal catalog. Visible only when the item's ID isn't already in the catalog; a rename dialog fires on title collision.

---

## Improvements

- **Catalog list** is now sorted by label first, then alphabetically within each label. Card layout is more consistent.
- **Rest phase UI**: during the rest between exercises the screen now shows the *next* exercise (not the one just completed), and the edit button targets the next exercise. Set-count controls are hidden during rest since they don't apply to a completed exercise.
- **Mid-session set/rep edits**: you can now decrease sets or reps below the value the session started with. Progress is clamped to the new lower value immediately so the session stays consistent.
- **Progress chart tick density**: the chart switches from per-data-point labels to weekly ticks when there are more than 4 data points, preventing label crowding.
- **Calendar**: added a "Today" button to jump back to the current date.
- **Delete confirmation dialogs** for sessions, workouts, and exercises in the catalog.
- Default exercise data reviewed and updated.

---

## Bug fixes

- Fixed the save button on new exercises not persisting to the preset provider.
- Fixed mid-session edits being unable to decrease reps or sets below the initial session value.
- Propagating a workout edit no longer resets the workout to its catalog ID inside sessions that already held a custom embedded copy.
- Propagation now correctly includes catalog workouts when computing exercise propagation targets.
- Propagating session changes now promotes default sessions into the user list so the update persists.
- Deduplication fixed for sessions and workouts when computing propagation consumers.
- Selection filter for exercises inside bagged workouts now applies correctly; cancelling the propagation prompt no longer leaves the screen in an inconsistent state.
- Cancelled session no longer causes the next session's first jump to skip to the next workout instead of the next exercise.
- Beep notifications are now cancelled when a session is cancelled or completed.
- Cloud catalog tables are kept in sync when items are moved to or restored from trash.
- Expired Supabase refresh tokens are now handled gracefully instead of crashing.

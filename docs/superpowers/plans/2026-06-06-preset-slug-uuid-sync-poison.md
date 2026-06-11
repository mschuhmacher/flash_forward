# Preset slug ↔ uuid sync poison — diagnosis & fix spec

**Status:** Diagnosis complete, fix not started.
**Trigger:** Sentry `PostgrestException … invalid input syntax for type uuid: "projecting-session" (22P02)`, recurring **every app startup**.

---

## Symptom

`PostgrestException(message: invalid input syntax for type uuid: "projecting-session", code: 22P02)` reported to Sentry repeatedly, once per startup. `projecting-session` is the first **default preset** session id in `lib/data/default_session_data.dart:17` — a kebab-case slug, not a UUID.

## Root cause (two independent bugs)

### Bug A — a preset slug is written into a `uuid` column

Cloud schema types both `user_sessions.id` (PK) and `session_logs.session_id` as `uuid`. Preset ids are slugs. They are **deliberately stable keys** (see the warning at `lib/data/default_workout_data.dart:14-17`): referenced by trash entries (local + Supabase), session templates via `templateId`, and used to **shadow defaults** in the user catalog. So we cannot simply renumber presets to UUIDs.

**How a slug reaches the cloud** — *not* via running a session. Traced and cleared the run path:
- `start(preset)` → `Session.deepCopy()` (keepId=false) → fresh UUID. (`session_state_provider.dart:638`)
- finish → `activeSession.copyWith(...)` keeps that UUID. (`session_active_bottom_bar.dart:441-460`)
- `editActive` → seeded with `activeSession` (UUID), `deepCopy(keepId:true)` preserves it. (`new_session_screen.dart:51-52`, `483-484`)
- `editBeforeStart` → keeps slug, but `onSaveAndStart` → `start()` re-forks to UUID.

The live vector is **editing or propagating a default preset in the catalog**:
`upsertSession` *"promotes a default into the user list at the same id, where it shadows the default"* (`catalog_provider.dart:207-209`, and propagation at `:482`). The promoted entry keeps the slug id, then `cloudOp` → `SupabaseSyncService.uploadSession` writes the slug into `user_sessions.id` (uuid PK) → `22P02`.

This is a design knot: same-id shadowing of defaults requires the slug; the uuid PK rejects it.

### Bug B — the sync queue has no poison-message handling

`uploadSession` (and `logCompletedSession`) **enqueue a retry op on failure** (`supabase_sync_service.dart:51-58`, `117-127`). The queue is designed so *"failed retries stay in the queue for the next attempt"* with **no attempt cap and no dead-letter** (`sync_queue_service.dart:72`, `228`). At startup, `loading_screen.dart` → `processPendingSync` (`supabase_sync_service.dart:410`) replays the op → fails identically → re-reports to Sentry → returns `false` → stays queued. A permanently-failing op becomes immortal and re-fires every startup. **Any** malformed op does this, not just this one.

### Why it recurs at startup
Bug A created an `uploadSession` poison op once (when a default was customized). Bug B replays it on every launch. That is the "multiple times, each at startup" pattern.

---

## Fix shape

### A — fork-on-promote + one unified trash (defaults never purge) *(chosen)*

Two ideas. **(1) Fork-on-promote:** when a stock default is promoted into the user list, fork it to a fresh UUID with `templateId = <default slug>` (`deepCopy(keepId: false)`) instead of keeping the slug — so a real UUID lands in the uuid PK and `templateId` preserves the "shadows default X" link. **(2) One unified trash:** a deleted default is just a trash entry that never auto-purges; its non-purging `templateId` *is* the durable suppression record. **No separate tombstone, no new table.**

Consistent with an existing pattern: all three models already have `templateId`, and propagation already matches by `id` OR `templateId` (`catalog_provider.dart:369-462`). The only holdouts still keying on raw `id` are the promote-on-upsert path (the bug) and the shadow getters.

Required changes:
1. **Fork on promote** in the three `upsert*` methods (`catalog_provider.dart:216`+ and propagation at `:482`). Fork **only when the item's id is a stock default slug**. Items already carrying a UUID — including a fork re-added via trash restore — upsert unchanged, so restore is idempotent and never re-forks.
2. **Fork on delete-of-a-default.** Deleting a *never-customized* default must also produce a UUID-bearing trash entry (`deepCopy(keepId:false)` → uuid + `templateId = slug`), so `trash_entries` ids stay uuid-clean and the entry can suppress the default via `templateId`.
3. **Retention by origin** in the trash purge. User-created entries purge at 90 days (today's behaviour). **Default-derived entries** (`templateId` resolves to a known default) **never auto-purge** — a bounded set, so cheap, and the customization stays recoverable indefinitely. Deleted defaults sync cross-device via the existing `trash_entries` table (uuid ids, no new schema).
4. **Shadow by breadcrumb.** The catalog shadow getters (`catalog_provider.dart:53-85`) currently hide a default when a user item shares its `id`. Replace with:
   ```
   shadowedDefaultIds = {active override.(templateId ?? id)} ∪ {default-derived trash entry.(templateId ?? id)}
   default hidden  ⇔  default.id ∈ shadowedDefaultIds
   ```
   User-item self-filtering still uses raw `id`. Because default-derived trash entries never purge, suppression is durable for free.
5. **One-time local heal.** Existing customized defaults sit in local JSON with slug ids (their cloud uploads always failed, so there are **no** slug rows in the cloud to migrate). On load, re-id any user item whose id isn't a valid UUID → fresh UUID + `templateId = oldId`, and drop the matching poison queue op. Folds bug C into the same pass.

**UX requirement (decided):** trashing a customized default must also suppress the generic default, durably past the 90-day purge — deleting something and having the plain version pop back is wrong. The non-purging default trash entry (steps 2–4) provides this; restoring it brings the customization back.

Model change: none. **Schema change: none** (reuses `trash_entries`; the only new behaviour is per-origin retention).

### Restore screen UX *(chosen)*

Settings → **"Restore items"** (`root_screen.dart:330-340` → `RestoreItemsScreen`) is the single restore surface; the separate "restore defaults" concept is removed.
- **Main list:** all trash entries, recency-sorted (`deletedAt` desc). Default-derived entries carry a small **"default"** tag to distinguish them from the user's own items.
- **Collapsed "Older" section:** entries older than 90 days — necessarily all defaults, since user items are purged by then. Expand (chevron) to multi-select individually.
- **"Restore all defaults" = reset to factory:** restores *every* deleted default (recent + old), de-emphasized at the foot of the "Older" section since it's the heavy-hitting action.
- Individual restore is the existing `restoreFromTrash` (re-adds the fork by its UUID → idempotent upsert).

### B — make the sync queue poison-resistant *(chosen)*

Disposition is **silent discard** (sync ops only push local→cloud; local data is never lost on discard) with **one Sentry capture at the moment of discard** carrying full context (op type, id, attempts, last error). No dead-letter store (YAGNI for a single-user app).

1. **`attempts` counter on `SyncOperation`**, persisted. The replace-on-re-enqueue path (`sync_queue_service.dart:122-136`, replaces an op with the same id) must **carry the counter over**, not reset it. Existing queued ops with no field deserialize to `0`.
2. **Classify the failure** in `processQueue`'s catch:
   - **Permanent** client errors (`PostgrestException` `22P02` / HTTP `400` / `422`) will never succeed → **discard on first occurrence**, capture to Sentry once. Kills a poison op on its *first* replay, not after N launches.
   - **Transient** errors (network, timeout, `5xx`) → retry up to **N = 5** across launches, then discard + capture once. Real multi-day outages still drain and retry rather than getting dropped early.
3. **Sentry policy:** report **once at terminal state** (discard) with the attempt count; suppress the per-retry re-reporting that caused the original noise.

### C — clear already-stuck ops on affected devices *(chosen)*

**Targeted heal + cap (belt-and-suspenders).** A's load pass (A step 5) already walks the user lists to re-id slug-id customized defaults; in the **same pass**, drop any queued op whose payload id isn't a valid UUID. This silences the *known* poison on the **very next launch** rather than waiting for B's cap to drain it over N launches. B's attempt-cap remains the general backstop for any *unanticipated* future poison-op kinds.

**Sequencing note:** B alone stops the Sentry noise even before A lands and guards future cases; A closes the source; C clears existing debris on first launch.

---

## Open decisions
1. ~~Data fix approach~~ — **decided: fork-on-promote with `templateId` breadcrumb.**
2. ~~90-day pop-back~~ — **decided: one unified trash; default-derived entries never auto-purge (no separate tombstone). Customization recoverable indefinitely.**
3. ~~Resurfacing a deleted default~~ — **decided: unified "Restore items" screen — recency-sorted main list (defaults tagged), collapsed "Older" (>90d, all defaults), "Restore all defaults" = reset-to-factory at its foot.**
4. ~~Bug B disposition~~ — **decided: silent discard + Sentry-once-at-discard; classify permanent (`22P02`/`400`/`422`, discard on first) vs transient (network/`5xx`, retry to N=5).**
5. ~~Bug C~~ — **decided: targeted heal in A's load pass (drop ops with non-uuid payload ids) + B's cap as general backstop.**

*No open decisions remain — spec is build-ready.*

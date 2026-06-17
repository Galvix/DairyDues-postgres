# DairyDues — offline-first + sync

Built on branch **`offline-sync`** (on top of `firebase-to-postgres`). The app no
longer needs Tailscale/Pi reachable to be used: it reads from an on-device cache,
lets you create/edit/delete offline, and syncs to the server whenever it can.

## Behaviour

- **Reads** come from a local cache → instant, and work fully offline.
- **Writes** (add/edit/delete milkman, milk, khoya, paneer, loan, settings,
  weekly payment + mark-paid) apply to the cache immediately and queue an
  **outbox** op. The UI updates at once.
- **Sync** flushes the outbox to the server, then pulls fresh data back into the
  cache. It runs automatically on: app start, regained connectivity
  (`connectivity_plus`), and after each mutation; plus **pull-to-refresh** and a
  **"Sync now"** action in the status banner. The banner shows
  offline / N-queued / syncing / error and hides when everything's synced.
- **Printing** is the one online-only action (you can't reach the home printer
  offline); it surfaces a network error if attempted offline.

## How offline creates stay consistent

Records get a **client-generated UUID** (`uuid` pkg) the moment they're created,
and the backend **upserts by that id** (`ON CONFLICT (id) DO UPDATE`). So a milk
entry created offline already references the right milkman id, and replaying the
queued ops in FIFO order (milkman → delivery → paneer) keeps relations intact. No
temp-id remapping. Re-syncing the same op is idempotent. Creating then deleting a
record that never synced collapses to a no-op.

## Components (Flutter)

| File | Role |
|------|------|
| `lib/database/local_store.dart` | JSON-file cache (per collection) + outbox, mirrored in memory. Persists via `path_provider`. **Web = in-memory only** (no docs dir). |
| `lib/database/sync_service.dart` | Sync engine: flush outbox (FIFO), pull server→cache, re-overlay pending ops. Connectivity-driven. Holds `cacheApply` (local effect) and `replayOp` (network effect) shared with the repo. |
| `lib/database/repository.dart` | Offline-first facade = the screens' `db`. Reads cache, writes cache+outbox, delegates prints to `ApiService`. |
| `lib/database/api_service.dart` | Unchanged role: the pure network layer, used only by the sync engine + prints. |
| `lib/widgets/sync_status_banner.dart` | Cross-screen status + "Sync now". |

Pull = server truth, then **re-overlay still-pending outbox ops**, so the cache is
always `server ⊕ local-unsynced-changes` (locally-created rows survive a pull;
locally-deleted rows stay deleted until their delete op syncs).

## Backend changes (`./api`) — you must redeploy these

No schema change (ids are already uuid PKs). The FastAPI code changed:

- Creates (milkman, milk/khoya delivery, paneer, loan) accept an optional client
  `id` and **upsert** by it.
- New `DELETE /milkmen/{id}/deliveries/{id}` and `/milkmen/{id}/khoya/{id}`
  (also closes the delete-endpoint gap from the migration report).
- New `PATCH /milkmen/{id}/payments/mark-paid` (by `week_start_date`) so settling
  a week doesn't need the server-assigned payment id.
- Fixed `payments.py` `pool = get_pool(),` tuple bug (would 500 the payments list).

All are additive/backward-compatible (online clients without ids still work).

## Trade-offs / notes

- Reads are cache-only on tab-focus (instant, offline-safe). Freshness comes from
  auto-sync, pull-to-refresh, and "Sync now" — not a live fetch on every focus.
- The pull fans out per-milkman (the backend has no cross-milkman endpoints); fine
  for a dairy's data size. A future date-scoped endpoint would make it lighter.
- First-ever launch while offline shows empty screens until the first sync; once
  synced, the cache persists across launches.
- Settings load from cache at startup (defaults match the seeded backend values),
  and refresh on the first successful sync.
- Web builds persist nothing (no `path_provider` docs dir) — in-memory only. The
  Android/desktop targets persist to a JSON file in the app documents directory.

## .env keys (unchanged)

```
API_BASE_URL=http://<your-pi>.<tailnet>.ts.net:8000   # still needed for syncing
API_TOKEN=<backend API_TOKEN>
```

You still set the Pi URL — but the app is now usable offline between syncs, so
Tailscale only needs to be up when you actually want to push/pull data.

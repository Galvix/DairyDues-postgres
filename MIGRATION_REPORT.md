# DairyDues — Firebase → FastAPI/PostgreSQL migration report

Full Flutter-side cutover from Firebase/Firestore to the self-hosted FastAPI +
PostgreSQL backend in `./api`. Done on branch **`firebase-to-postgres`**, one
commit per checkpoint.

## 0. Resolved inputs (the prompt left these as placeholders)

| Input | Resolution |
|-------|-----------|
| Backend source | **`./api`** — the FastAPI app lives in this same repo. It is the authoritative contract used throughout. |
| API base URL | Left for you to fill: `API_BASE_URL` in `.env` (gitignored). The app reads it via `flutter_dotenv`. |
| App API token | Already present in `.env` as `API_TOKEN` (the app token, not `PRINT_AGENT_TOKEN`). The app sends it as `Authorization: Bearer …`. |
| Keep rollback copy of `firestore_service.dart`? | **No** — deleted. Rollback is the **`baseline:` commit on `main`** (the repo had no prior commits, so I created one before branching). |

## 1. API contract extracted from `./api` (single source of truth)

All routes require `Authorization: Bearer <API_TOKEN>` except the print-agent
routes (which use `PRINT_AGENT_TOKEN` and are **not** called by the app). No
global path prefix is mounted (`api/app/main.py` is empty — see BACKEND GAPS),
so routers sit at root with the prefixes shown.

### Milkmen — `api/app/routers/milkmen.py`
| Method | Path | Query | Request body | Response |
|---|---|---|---|---|
| GET | `/milkmen/` | `active_only: bool` | — | `[Milkman]` |
| POST | `/milkmen/` | — | `MilkmanCreate{name, milk_rate, khoya_rate, supplies_khoya, is_active}` | `Milkman` |
| GET | `/milkmen/{id}` | — | — | `Milkman` |
| PATCH | `/milkmen/{id}` | — | `MilkmanUpdate{any subset}` | `Milkman` |
| DELETE | `/milkmen/{id}` | — | — | 204 |

`Milkman` = `{id: uuid, name, milk_rate, khoya_rate, supplies_khoya, is_active}`.

### Deliveries (milk / khoya / paneer) — `api/app/routers/deliveries.py`
| Method | Path | Query | Request body | Response |
|---|---|---|---|---|
| GET | `/milkmen/{milkman_id}/deliveries` | `from_date, to_date` (date) | — | `[MilkDelivery]` |
| POST | `/milkmen/{milkman_id}/deliveries` | — | `MilkDeliveryCreate{delivery_date(datetime), gross_weight, can_weight, net_milk, notes}` | `MilkDelivery` |
| GET | `/milkmen/{milkman_id}/khoya` | `from_date, to_date` | — | `[KhoyaDelivery]` |
| POST | `/milkmen/{milkman_id}/khoya` | — | `KhoyaDeliveryCreate{delivery_date, weight, notes}` | `KhoyaDelivery` |
| GET | `/milkmen/{milkman_id}/paneer` | `from_date, to_date` | — | `[PaneerEntry]` |
| POST | `/milkmen/{milkman_id}/paneer` | — | `PaneerEntryCreate{milkman_id, delivery_id, entry_date(date), total_milk_used, expected_paneer, actual_paneer, tolerance_kg}` | `PaneerEntry` |

- `MilkDelivery` response adds `id, milkman_id, billable_milk, paneer_adjusted`.
  `billable_milk` starts `= net_milk`; **the backend overwrites it** when a paneer
  test is posted (`billable_milk = net_milk * actual_paneer/expected_paneer`).
- `PaneerEntry` response adds `id, yield_ratio, adjustment_applied, adjusted_milk_total`.
  The POST handler **requires** that `delivery_id` belongs to `milkman_id`, and
  rejects `expected_paneer <= 0` (400).

### Loans + Weekly payments + Hisab — `api/app/routers/payments.py`
| Method | Path | Query | Body | Response |
|---|---|---|---|---|
| GET | `/milkmen/{milkman_id}/loans` | — | — | `[Loan]` |
| POST | `/milkmen/{milkman_id}/loans` | — | `LoanCreate{amount, loan_date, notes}` | `Loan` |
| DELETE | `/loans/{loan_id}` | — | — | 204 |
| GET | `/milkmen/{milkman_id}/payments` | — | — | `[WeeklyPayment]` |
| POST | `/milkmen/{milkman_id}/payments` | — | `WeeklyPaymentCreate{…, milk_rate_applied, khoya_rate_applied}` (upsert on `(milkman, week_start)`) | `WeeklyPayment` |
| PATCH | `/payments/{payment_id}/mark-paid` | — | — | `WeeklyPayment` |
| GET | `/milkmen/{milkman_id}/hisab` | `week_start, week_end` (datetime) | — | computed summary JSON (NOT adopted — see GAPS) |

`WeeklyPaymentCreate` carries the snapshotted `milk_rate_applied` /
`khoya_rate_applied`. Response adds `id, milkman_id, paid_at`.

### Settings — `api/app/routers/settings.py`
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/settings/` | — | `[{key, value}]` |
| GET | `/settings/{key}` | — | `{key, value}` (404 if missing) |
| PUT | `/settings/{key}` | `{value: float}` (upsert) | `{key, value}` |

Seeded keys: `standard_paneer_kg=6.5`, `sample_milk_kg=24.0`, `paneer_tolerance_kg=0.5`.

### Print jobs — `api/app/routers/print_jobs.py`
| Method | Path | Query | Body | Auth | Response |
|---|---|---|---|---|---|
| POST | `/print-jobs/` | — | `{job_type, params}` | app | `PrintJob` |
| GET | `/print-jobs/` | `status_filter` | — | app | `[PrintJob]` (recent 50) |
| GET | `/print-jobs/pending` | — | — | **agent** | `[PrintJob]` |
| GET | `/print-jobs/{id}/pdf` | — | — | **agent** | pdf bytes |
| PATCH | `/print-jobs/{id}/status` | — | `{status, error}` | **agent** | `PrintJob` |

`PrintJob` = `{id, job_type, params, status(pending|printing|done|failed), attempts, error, created_at, updated_at, printed_at}` (no `pdf` in list). The app
uses only POST + GET; status is polled by re-reading the recent list.

## 2. Files deleted / created / rewritten

**Deleted**
- `lib/database/firestore_service.dart`
- `firebase.json`, `firestore.indexes.json`
- FlutterFire Gradle plugin lines in `android/settings.gradle.kts` and
  `android/app/build.gradle.kts`
- (`google-services.json`, `GoogleService-Info.plist`, `lib/firebase_options.dart`
  were gitignored and never on disk; nothing to delete)

**Created**
- `lib/database/api_service.dart` — the Dio-backed data layer (replaces FirestoreService)
- `.env.example` — documents the runtime keys
- `AUDIT.md`, `MIGRATION_REPORT.md`
- `test/widget_test.dart` — repurposed from the dead counter template into real
  offline unit tests

**Substantially rewritten**
- `lib/database/models.dart` — snake_case JSON + ISO-8601 dates; uuid→String;
  new `PaneerEntry.deliveryId`, `WeeklyPayment.milk/khoyaRateApplied`; new `PrintJob`
- `lib/providers/app_provider.dart` — holds `ApiService`; server-side paneer
- `lib/main.dart` — dotenv + ApiService instead of Firebase init
- `lib/screens/{milkmen,daily_entry,dashboard,paneer,loans}` — streams → FutureBuilder + refresh
- `lib/screens/payment/payment_screen.dart` — added "Send to home printer" + status polling
- `pubspec.yaml` — dropped `firebase_core`/`cloud_firestore`, added `dio`/`flutter_dotenv`, registered `.env` asset

## 3. Real-time replacement pattern

REST has no push, so **one** pattern everywhere a `.snapshots()` StreamBuilder
existed:

- **StreamBuilder → FutureBuilder** over an `ApiService.get*` call.
- **Load on focus for free:** the shell renders `_screens[index]` directly (not an
  `IndexedStack`), so switching tabs remounts a screen → `initState` reloads it.
  Data loads in `initState`; combined screens fetch in parallel via `Future.wait`.
- **Pull-to-refresh:** every list/scroll body is wrapped in `RefreshIndicator`.
- **Refresh-after-mutation:** add/delete/save sheets return a success flag (or bump
  a `reloadToken` passed to child widgets) and the parent re-issues its future.
- **Polling — only for print jobs:** after "Send to home printer", a small dialog
  polls `getPrintJob` every 2 s (≤60 s) to reflect `pending → printing → done/failed`.
  No other polling was added.

## 4. LOGIC MOVED SERVER-SIDE

- **Paneer billable-milk adjustment.** Previously
  `FirestoreService.applyPaneerAdjustmentForMilkman` batch-wrote
  `billableMilk = netMilk × ratio` on the client. Now POSTing a paneer entry makes
  the backend compute `yield_ratio` and write `billable_milk` on the delivery.
  The provider posts one entry per delivery the milkman made that day to reproduce
  the old whole-day adjustment. **Behaviour change to note:** the backend *always*
  applies the ratio and sets `adjustment_applied = TRUE`, whereas the old client only
  *reduced* milk when sample `<` standard. So when a sample yield is **above**
  standard, the server now **increases** `billable_milk` (ratio > 1). The client-side
  `PaneerValidation` is retained **only** for the live preview / result dialog.
- **Paneer `yield_ratio` / `adjusted_milk_total`** are computed by the server (not sent).

## 5. BACKEND GAPS (stubbed with TODOs, or worked around)

1. **No DELETE for milk or khoya deliveries.** The routers expose create/list only.
   `ApiService.deleteMilkDelivery` / `deleteKhoyaDelivery` are stubbed to throw a
   clearly-worded `ApiException`; the delete buttons now show that message in a
   snackbar instead of silently doing nothing. **TODO(backend):** add
   `DELETE /milkmen/{id}/deliveries/{id}` and `DELETE /milkmen/{id}/khoya/{id}`.
2. **No cross-milkman "by date" endpoints.** Deliveries/khoya/paneer are per-milkman
   only, but the dashboard, daily-entry and paneer screens need "everything on date D".
   `getDeliveriesForDate` / `getKhoyaForDate` / `getPaneerEntriesForDate` /
   `getRecentPaneerEntries` **fan out** (one request per milkman) and merge client-side.
   Correct but N+1; fine for a small dairy. **TODO(backend):** add date-scoped
   collection endpoints (e.g. `GET /deliveries?date=`).
3. **`GET /milkmen/{id}/hisab` not adopted.** Its loan model differs from the app's:
   it deducts **all** pending loans (not week-windowed) and has **no carry-forward**.
   The payment UI depends on `thisWeekLoans`, `carriedOverLoan`, `loanCarryForward`,
   so to *preserve screen behaviour* the weekly aggregation stays client-side
   (`WeeklyPaymentSummary.calculate`), reading the server-adjusted `billable_milk`.
   **TODO(backend):** extend hisab with week-windowed loans + carry-forward if you
   want this server-side.
4. **`api/app/main.py` is empty (0 bytes).** No `FastAPI()` app, router includes, or
   global prefix is wired in the committed source. The app assumes routers are mounted
   at root with no version prefix. **TODO(backend):** confirm the real app wiring; if a
   prefix like `/api/v1` is added, set it on `API_BASE_URL` (e.g. `…:8000`), no app
   code change needed.
5. **`api/app/routers/payments.py:67` has a bug:** `pool = get_pool(),` (trailing
   comma makes `pool` a tuple → `list_payments` will 500). Not a Flutter issue, but it
   will break `getPaymentsForMilkman` / payment screen until fixed server-side.
   **TODO(backend):** drop the trailing comma.

## 6. Other assumptions / TODOs

- **IDs:** Postgres PKs are `uuid`, which serialize as JSON strings → Dart `id` stays
  `String`. **No call site that assumed a string id needed to change** (the prompt
  anticipated possible int/uuid changes; uuid-as-string made it a no-op).
- **Dates:** timestamptz/`date` are sent as `toUtc().toIso8601String()` (datetimes) or
  `YYYY-MM-DD` (calendar dates), and parsed back with `DateTime.parse(...).toLocal()`
  so date-grouping by local day round-trips. Week/day filters are applied client-side
  after a bounded query, matching the old inclusive `[weekStart, weekStart+7)` window
  and avoiding the `timestamptz <= date` boundary edge.
- **Query params:** `active_only`, `from_date`/`to_date`, `status_filter` taken verbatim
  from the routers. `from_date`/`to_date` are sent as `YYYY-MM-DD`.
- **Trailing slashes** match the routers exactly (`/milkmen/`, `/settings/`, `/print-jobs/`).
- **Errors:** `ApiException{kind: auth|network|server|unknown}` — 401→auth (bad token),
  no-response→network (URL/Tailscale), 5xx→server, other 4xx surface the backend
  `detail`. Screens show a reachability view with Retry; `main()` swallows a failed
  startup settings load so the app still opens.
- **Print job `params` keys** assumed `snake_case` (`milkman_id`, `week_start`,
  `week_end`) since the backend stores `params` as opaque JSONB. Adjust if the
  server-side PDF renderer expects different keys.
- **Two historical code comments** still contain the words "FirestoreService"/"Firestore
  model" (in `api_service.dart` / `models.dart`) — documentation only, no active refs.
- The pre-existing Kotlin-Gradle-plugin deprecation warning and the ~50 info-level
  lints (`withOpacity`, `prefer_const`) are unrelated to this migration and were left
  as-is to keep the diff a pure data-layer swap.

## 7. .env keys you must set

```
API_BASE_URL=http://<your-pi>.<tailnet>.ts.net:8000   # no trailing slash — CURRENTLY EMPTY, set this
API_TOKEN=<already set in .env to the backend API_TOKEN>
```

`.env` is gitignored; `.env.example` documents both keys.

## 8. Verification

- `flutter analyze` → **0 errors, 0 warnings** (50 info-level lints, all pre-existing style).
- `flutter test` → **5/5 pass** (paneer + payment + date logic).
- `flutter build apk --debug` → **success** (`build/app/outputs/flutter-apk/app-debug.apk`).

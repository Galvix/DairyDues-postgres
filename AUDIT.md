# Firebase Surface Audit — DairyDues

Complete inventory of the Firebase/Firestore footprint **before** the cutover to
the self-hosted FastAPI + PostgreSQL backend. Captured on the `firebase-to-postgres`
branch.

## 1. The data layer

- **`lib/database/firestore_service.dart`** — the entire data access layer. Wraps
  `FirebaseFirestore.instance` and exposes collections: `milkmen`, `deliveries`,
  `khoya`, `paneer`, `loans`, `weeklyPayments`, `settings`. Operations:
  - Settings: `getStandardPaneerKg`, `getSampleMilkKg`, `getToleranceKg`, `setSetting`.
  - Milkmen: `watchActiveMilkmen` (stream), `getActiveMilkmen`, `addMilkman`,
    `updateMilkman`, `deactivateMilkman`.
  - Milk: `addMilkDelivery`, `deleteMilkDelivery`, `watchDeliveriesForDate` (stream),
    `getAllDeliveriesForDate`, `getDeliveriesForWeek`, `applyPaneerAdjustment`.
  - Khoya: `addKhoyaDelivery`, `deleteKhoyaDelivery`, `watchKhoyaForDate` (stream),
    `getKhoyaDeliveriesForWeek`, `getTotalKhoyaForWeek`.
  - Paneer: `addPaneerEntry`, `getPaneerEntryForDateAndMilkman`,
    `watchPaneerEntriesForDate` (stream), `watchRecentPaneerEntries` (stream),
    `applyPaneerAdjustmentForMilkman` (client-side billable_milk batch write).
  - Loans: `addLoan`, `deleteLoan`, `watchLoansForMilkman` (stream),
    `getTotalLoansForWeek`, `getCarriedOverLoan`.
  - Payments: `getPaymentForWeek`, `upsertWeeklyPayment`, `markPaymentPaid`.

## 2. Files that consume FirestoreService

| File | How it uses Firestore |
|------|------------------------|
| `lib/main.dart` | `Firebase.initializeApp()`, constructs `FirestoreService`, injects into `AppProvider`. |
| `lib/providers/app_provider.dart` | Holds `FirestoreService db`; orchestrates milk entry, paneer validation+adjustment, weekly payment calc. |
| `lib/screens/milkmen/milkmen_screen.dart` | `watchActiveMilkmen`, `addMilkman`, `updateMilkman`, `deactivateMilkman`; Firestore-specific error text. |
| `lib/screens/daily_entry/daily_entry_screen.dart` | `watchDeliveriesForDate`, `watchActiveMilkmen`, `watchKhoyaForDate`, `getActiveMilkmen`, `deleteMilkDelivery`, `addKhoyaDelivery`, `deleteKhoyaDelivery`. |
| `lib/screens/dashboard/dashboard_screen.dart` | `watchDeliveriesForDate`, `watchRecentPaneerEntries`, `calculateWeeklyPayments`. |
| `lib/screens/paneer/paneer_screen.dart` | `watchDeliveriesForDate`, `watchActiveMilkmen`, `watchPaneerEntriesForDate`, `watchRecentPaneerEntries`, `validateAndSavePaneerForMilkman`. |
| `lib/screens/loans/loans_screen.dart` | `watchActiveMilkmen`, `watchLoansForMilkman`, `getActiveMilkmen`, `addLoan`, `deleteLoan`. |
| `lib/screens/payment/payment_screen.dart` | `calculateWeeklyPayments`, `getDeliveriesForWeek`, `getKhoyaDeliveriesForWeek`, `getPaymentForWeek`, `markPaymentPaid`; local PDF/Excel export. |
| `lib/screens/settings/settings_screen.dart` | via provider `updateSampleMilkKg`/`updateStandardPaneerKg`; "Firebase Edition" label. |

## 3. Firestore real-time streams (`.snapshots()` / StreamBuilder) — lose push, need replacement

Every `watch*` method above uses `.snapshots()`. Consumers (each is a `StreamBuilder`):

- `milkmen_screen` → `watchActiveMilkmen`
- `daily_entry_screen` → `watchDeliveriesForDate`, `watchActiveMilkmen` (milk tab),
  `watchKhoyaForDate`, `watchActiveMilkmen` (khoya tab)
- `dashboard_screen` → `watchDeliveriesForDate`, `watchRecentPaneerEntries`
- `paneer_screen` → `watchDeliveriesForDate`, `watchActiveMilkmen`,
  `watchPaneerEntriesForDate`, `watchRecentPaneerEntries`
- `loans_screen` → `watchActiveMilkmen`, `watchLoansForMilkman` (×2: subtitle + body)

(`dashboard`'s `_WeekSummaryCard` and `payment_screen` already use `Future` +
manual refresh, not streams.)

## 4. pubspec.yaml Firebase packages

- `firebase_core: ^3.6.0`
- `cloud_firestore: ^5.4.4`

(No `firebase_auth`, `firebase_storage`, `firebase_messaging`.)

## 5. main.dart

- `import 'package:firebase_core/firebase_core.dart';`
- `import 'firebase_options.dart';`
- `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);`

## 6. Platform / config

- **`lib/firebase_options.dart`** — gitignored; not currently present on disk
  (FlutterFire-generated). `main.dart` imports it.
- **`android/app/google-services.json`** — gitignored; not present on disk.
- **`ios/Runner/GoogleService-Info.plist`** — not present on disk.
- **`android/settings.gradle.kts`** — `id("com.google.gms.google-services") version("4.3.15") apply false`
  (inside `// START/END: FlutterFire Configuration`).
- **`android/app/build.gradle.kts`** — `id("com.google.gms.google-services")` in the
  `plugins {}` block (inside `// START/END: FlutterFire Configuration`).
- **`android/build.gradle.kts`** — no Firebase lines.
- **`web/index.html`** — no Firebase `<script>` tags (clean).
- **`firebase.json`** (root) — FlutterFire platform config (projectId `hisaab-b44c8`).
- **`firestore.indexes.json`** (root) — Firestore composite indexes.

## 7. Model serialization tied to Firestore

`lib/database/models.dart` — all six models use:
- `factory X.fromFirestore(String id, Map<String,dynamic>)` — takes the Firestore
  **document id** as a separate `String` argument (the model `id` is the Firestore
  string doc id).
- `Map<String,dynamic> toMap()` — writes `Timestamp.fromDate(...)` for every date.
- `_toDateTime(dynamic)` helper converts Firestore `Timestamp` → `DateTime`.
- JSON keys are **camelCase** (`milkRate`, `deliveryDate`, `milkmanId`, …).

### Post-migration mapping
- Postgres PKs are **uuid** → represented as JSON/Dart **`String`**, so model `id`
  stays `String` and **no call site that passed a string id needs to change**.
- `Timestamp` → ISO-8601 `timestamptz`/`date` strings, parsed with
  `DateTime.parse(...).toLocal()`.
- JSON keys become **snake_case** to match the Pydantic models.
- `WeeklyPayment` gains `milk_rate_applied` / `khoya_rate_applied` (snapshot fields the
  Firestore model lacked). `PaneerEntry` gains `delivery_id`.

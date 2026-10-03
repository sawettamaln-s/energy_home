# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Energy Home: a Flutter app (thesis/education project) for tracking household electricity and water costs in Thailand per billing cycle. The user sets a billing day and enters the meter reading from their latest bill (the cycle's start reading), then records readings during the cycle. The app estimates costs with real MEA/PEA (electricity) and MWA/PWA (water) tariffs, including TOU meters (On-Peak/Off-Peak), forecasts the cycle total and next month, and compares against past bills. Backend is Firebase (Auth + Firestore).

## Conventions

- Code comments, UI strings and docs are in Thai. Comments describe current behavior only, with no history ("เดิมเป็น X เปลี่ยนเป็น Y").
- UI text is polite Thai ending in "ค่ะ". Use one term per concept: วันตัดรอบบิล (billing day), เลขมิเตอร์ต้นรอบ (cycle start reading; its settings page is "เลขมิเตอร์จากใบแจ้งหนี้"), รายจ่ายประจำ (fixed costs), สิ้นรอบบิล (end of cycle, not "สิ้นเดือน").
- Colors live only in `lib/styles/app_colors.dart` (`AppColors`, mirrored by `DashboardStyles`). Don't hardcode new `Color(0x...)` values in screens. Material `Colors.grey.shadeN` etc. are fine.
- Changes that alter app behavior, data or flow get confirmed with the user before they're made.

## Commands

```bash
flutter pub get
flutter run
flutter analyze                        # lint (flutter_lints; platform dirs excluded)
flutter test                           # all tests, no real Firebase needed
flutter test test/record_meter_screen_test.dart                       # single file
flutter test test/fixed_cost_item_test.dart --plain-name "<test name>"   # single test
```

**Firebase config:** `lib/firebase_options.dart` is gitignored. For a build or analysis without a real project, copy `lib/firebase_options.sample.dart` to `lib/firebase_options.dart` (CI does this). Use `flutterfire configure` for a real project.

CI (`.github/workflows/flutter-ci.yml`) runs `flutter analyze` and then `flutter test` on pushes and PRs to `master`.

## Architecture

- **Startup:** `main.dart` initializes Firebase and `NotificationService`, clamps the system text scale to 0.85–1.3, and opens `AuthGate`. `AuthGate` listens to `authStateChanges` and routes to `WelcomeScreen`, `SetupScreen` (only when the user doc doesn't exist; a load error shows a retry screen instead, so the doc is never overwritten) or `MainShell`. It's keyed by uid so switching accounts reloads the data. To log out, push a fresh `AuthGate()` with `pushAndRemoveUntil`.
- **New-user flow:** `SetupScreen` asks only for area and meter type. The dashboard then shows a 3-step checklist (billing day → meter reading from the bill → optional past bills) until a start reading exists, and an onboarding dialog on first visit.
- **`MainShell`** keeps all 4 tabs (dashboard, analysis, appliance, settings) alive in a single `IndexedStack`, so `initState` does not run again when the user switches tabs. Cross-tab refresh goes through **`DataRefreshBus`** (`lib/utils/data_refresh_bus.dart`): `FirestoreService` calls `notifyChanged()` after writes/deletes of the user doc, bills, logs and start readings, and `DashboardScreen`/`AnalysisScreen` listen to `DataRefreshBus.instance.version`. Appliances are not on the bus; their screens listen to the Firestore stream (`getAppliances`). A new write method other screens depend on has to call `notifyChanged()`.
- **`FirestoreService`** (`lib/services/firestore_service.dart`) is the only Firestore access layer. User data lives under `users/{uid}` with the subcollections `bills`, `appliances`, `electricity_logs`, `water_logs`, `fixed_costs` and `start_meter_history`. The Ft rate is in `app_config/electricity_rates`, read-only from the client (see `firestore.rules`). The service accepts an injected `FirebaseFirestore`, and `AuthGate`/auth screens accept an injected `FirebaseAuth`. Tests use `FakeFirebaseFirestore` and `MockFirebaseAuth` (plus `mock_exceptions` to simulate `FirebaseAuthException`). Keep new Firebase-touching code injectable. `DashboardScreen` and `AnalysisService` still use `FirebaseAuth.instance`/`FirebaseFirestore.instance` directly, so they can't be widget-tested yet.
- **Billing-cycle rules** (break these and the dashboard/analysis go wrong):
  - Cycle boundaries come only from `EnergyForecaster` (`lib/utils/forecaster.dart`). The billing day is the *first* day of the new cycle.
  - A bill's `year`/`month` is the cycle's *closing* month (the invoice month). A `start_meter_history` record's `billingMonth` is the month the cycle *started*. Editing the current cycle's start reading overwrites its record.
  - Log `cost`/`usedFromStart` are cumulative from the cycle start. For TOU, `meterValue` stores units used since the cycle start; the real readings are `peakMeterValue`/`offPeakMeterValue`.
- **Dashboard load** (`_loadData`): only what the screen shows is loaded (in parallel), then the screen paints. Fixed-cost recalc, bill compilation/backfill and notification checks run afterwards in `_runBackgroundTasks`. Overlapping loads are queued, and a reload keeps the old content on screen. The fixed cost shown is the one for the current bill month (same rule as `compileBill`), not `user.fixedCost`.
- **Bill compilation:** on each dashboard load, `compileBill()` turns the just-closed cycle's logs into a `'compiled'` bill (and backfills missed cycles back to `startBillingMonth`). Bill sources are `'compiled'`, `'imported'` (past bills entered by the user) and `'startMeter'` (created with a start reading; editable only from that page).
  - Totals start from the cycle's latest log and are projected to the cycle end with `cycle_projection.dart` (the same projection as the "current cycle" forecast). A `'startMeter'` bill for the same month later overwrites it with invoice figures. The bill-history page lists all three sources; compiled bills there can be edited (saved as `'imported'`) but not deleted.
  - The fixed cost is recomputed for that cycle's month (`isActiveInMonth`). It does not come from the `user.fixedCost` cache, which only holds the current month's value.
  - TOU peak/off-peak usage is subtracted from the start record of the month the compiled cycle started, not from the user's current start values.
  - `migrateTouCompiledBills()` repairs compiled TOU bills from the logs and has no UI entry point. `tool/migrate_tou_bills.dart` mirrors its logic, so changes to that calculation must be made in both places.
- **Meter entry rules** (`record_meter_screen.dart`): a reading must not be below the cycle start reading or the latest reading of the current cycle (TOU checks each field). Invalid input disables the save button and shows a fix shortcut (start-meter setup or the meter-log history).
- **Notifications** (`NotificationService`, singleton): toggles, history and de-dup keys are stored in SharedPreferences, scoped per uid (`uidProvider` can be overridden in tests). Instant checks run from the dashboard's `_runNotificationChecks`, which catches its own errors. The billing reminder is scheduled for 09:00 on the billing day. `syncDeliveredScheduledNotifications()` must run before `scheduleBillingReminder()`, or a delivered reminder never reaches the history.
- **Pure logic in `lib/utils/`** (no Firebase or widgets, so it's easy to test):
  - `calculator.dart` (`EnergyCalculator`): tariff tables and cost formulas. Only `getFtRate()` touches Firestore. `calculateUsed` never returns a negative value.
  - `forecaster.dart` (`EnergyForecaster`): cycle boundaries, the end-of-cycle unit projection from the daily rate (`projectToCycleEnd`), the seasonal next-month forecast, and the linear regression fallback used when area/meterType are unknown.
  - `cycle_projection.dart`: end-of-cycle forecast used by the dashboard, the analysis current-cycle card and `compileBill`. It projects *units* (TOU: On/Off-Peak separately) and prices them with `EnergyCalculator`. Never scale the cumulative cost by days: the service fee and the water minimum charge don't grow with usage.
  - `appliance_rate.dart` (`ApplianceRate`): the baht/unit rate for appliance estimates = electricity cost ÷ units of the latest usable bill, falling back to 4.5. The appliance screen and the analysis appliance tab must use the same rate.
  - `seasonal_curves.dart` is **generated** from real monthly residential statistics (EPPO residential electricity for MEA/PEA, MWA residential water for Bangkok, PWA total water sold for upcountry — PWA publishes no residential split). Don't edit it by hand. Regenerate it with `python tool/seasonal_curves/build_seasonal_curves.py` (add `--fetch` to re-download the source data).
- **Styling:** `lib/styles/` holds colors, typography (`AppTypography.sN`) and spacing (`AppSpacing.vN`). `responsive.dart` provides `context.rf()`/`context.rs()`, which scale against a 375px base width. `DashboardStyles` (exported with all style files) holds shared text styles and card decorations.

## Tools (`tool/`)

Standalone scripts, not part of the app. Scripts that write to Firestore are dry runs until `--apply` is passed. `migrate_tou_bills.dart` and `demo_data/generate_demo_account.dart` carry copies of the tariff formulas (they can't import `calculator.dart`, which depends on `cloud_firestore`), so tariff changes must be made there too.
- `seasonal_curves/` (Python): `build_seasonal_curves.py` builds the seasonal curves; `backtest_forecast_methods.py` reports MAPE of the forecast methods on the same real data.
- `backtest_forecast.dart`: walk-forward backtest of the app's forecast functions on one account's real bills.
- `demo_data/generate_demo_account.dart` fills an existing account with demo data for one of the 4 cases (`bangkok_normal`, `bangkok_tou`, `upcountry_normal`, `upcountry_tou`) using the app's own cycle rules and seasonal curves. `--reset` clears the account's data first.
- `migrate_tou_bills.dart`: see `tool/README_migrate_tou_bills.md`.
- `list_bills.dart`: read-only listing of one account's bills.

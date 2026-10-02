# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Energy Home: a Flutter app (thesis/education project) for tracking household electricity and water usage in Thailand. Users record daily meter readings; the app estimates bills using real MEA/PEA (electricity) and MWA/PWA (water) tariff structures, including TOU meters (On-Peak/Off-Peak), and forecasts future usage. Backend is Firebase (Auth + Firestore). Code comments, UI strings, and docs are in Thai. Match that when editing.

## Commands

```bash
flutter pub get
flutter run
flutter analyze                        # lint (flutter_lints; platform dirs excluded)
flutter test                           # all tests, no real Firebase needed
flutter test test/login_screen_test.dart                 # single file
flutter test test/fixed_cost_item_test.dart --plain-name "<test name>"   # single test
```

**Firebase config:** `lib/firebase_options.dart` is gitignored. For a build or analysis without a real project, copy `lib/firebase_options.sample.dart` to `lib/firebase_options.dart` (CI does this). Use `flutterfire configure` for a real project.

CI (`.github/workflows/flutter-ci.yml`) runs `flutter analyze` and then `flutter test` on pushes and PRs to `master`.

## Architecture

- **Startup:** `main.dart` initializes Firebase and `NotificationService`, clamps the system text scale to 0.85–1.3, and opens `AuthGate`. `AuthGate` listens to `authStateChanges` and routes to `WelcomeScreen`, `SetupScreen` (when the user doc is missing or incomplete) or `MainShell`. It's keyed by uid so switching accounts reloads the data. To log out, push a fresh `AuthGate()` with `pushAndRemoveUntil`.
- **`MainShell`** keeps all 4 tabs (dashboard, analysis, appliance, settings) alive in a single `IndexedStack`, so `initState` does not run again when the user switches tabs. Cross-tab refresh therefore goes through **`DataRefreshBus`** (`lib/utils/data_refresh_bus.dart`): `FirestoreService` calls `DataRefreshBus.instance.notifyChanged()` after every write or delete, and screens that need fresh data `addListener` on `DataRefreshBus.instance.version`. A new write method has to call `notifyChanged()`, and a new screen that depends on another tab's data has to listen to the bus.
- **`FirestoreService`** (`lib/services/firestore_service.dart`) is the only Firestore access layer. All user data lives under `users/{uid}` with the subcollections `bills`, `appliances`, `electricity_logs`, `water_logs`, `fixed_costs` and `start_meter_history`. The global rates (Ft rate) are in `app_config/electricity_rates`, which is read-only from the client (see `firestore.rules`). The service accepts an injected `FirebaseFirestore`, and `AuthGate`/auth screens accept an injected `FirebaseAuth`. Tests use `FakeFirebaseFirestore` and `MockFirebaseAuth` (plus `mock_exceptions` to simulate `FirebaseAuthException`). Keep new Firebase-touching code injectable in the same way.
- **Billing logic:**
  - `compileBill()` turns a *closed* billing cycle's logs into a `BillModel`.
  - The fixed cost is recomputed for that cycle's month (`isActiveInMonth`). It does not come from the `user.fixedCost` cache, which only holds the current month's value.
  - TOU peak/off-peak usage is calculated against the `start_meter_history` record whose billing month is the month the compiled cycle *started* (the bill's own month is the closing month = the next cycle's start), not against the user's current start values.
  - `migrateTouCompiledBills()` is a one-off admin fix with no UI entry point. `tool/migrate_tou_bills.dart` mirrors its logic, so changes to that calculation must be made in both places.
- **Pure logic in `lib/utils/`** (no Firebase or widgets, so it's easy to test):
  - `calculator.dart` (`EnergyCalculator`): tariff tables and cost formulas. Only `getFtRate()` touches Firestore.
  - `forecaster.dart` (`EnergyForecaster`): the single source of truth for billing-cycle boundaries and forecasting. It projects the end of the current cycle from the daily rate (`projectToCycleEnd`), forecasts next month with a seasonal curve when area and meterType are known, and falls back to linear regression. Screens must not compute cycle boundaries on their own.
  - `seasonal_curves.dart` is **generated** from real monthly residential statistics (EPPO electricity for MEA/PEA, MWA water). Don't edit it by hand. Regenerate it with `python tool/seasonal_curves/build_seasonal_curves.py` (add `--fetch` to re-download the source data).
- **Styling:** `lib/styles/` holds the colors, spacing and typography. `responsive.dart` provides `context.rf()` and `context.rs()`, which scale against a 375px base width. Use them for new layouts. `DashboardStyles.primaryGreen` seeds the theme.

## Tools (`tool/`)

These are standalone `dart run` scripts, not part of the app:
- `backtest_forecast.dart` runs a walk-forward backtest of linear regression against the seasonal forecast, using the real functions from `lib/utils`.
- `migrate_tou_bills.dart`: see `tool/README_migrate_tou_bills.md`. Always run it as a dry run first; `--apply` writes to Firestore.
- `seasonal_curves/` (Python): `build_seasonal_curves.py` builds the seasonal curves; `backtest_forecast_methods.py` reports MAPE of the forecast methods on the same real data.
- `demo_data/generate_demo_account.dart` fills an existing account with demo data for one of the 4 cases (`bangkok_normal`, `bangkok_tou`, `upcountry_normal`, `upcountry_tou`) using the app's own cycle rules and seasonal curves. Dry run by default; `--apply` writes, `--reset` clears the account's data first.

# ZIZOUIT Manager

Flutter manager based on `ZIZOUIT_Manager_Rules_Updated.pdf` (10 October 2026), with local mode, optional Firebase authentication/synchronization, and structured bulk-to-selling-container recipes. Firebase integration is implemented but the live project still needs connection/configuration under the owner's Google account.

## Run

```powershell
flutter pub get
flutter run -d chrome
```

For Android, connect a device or start an emulator and run `flutter run`. On this computer the SDK is at `C:\Users\HP EliteBook\OneDrive\Desktop\flutter\bin\flutter.bat` if Flutter is absent from PATH. Windows desktop plugins require Developer Mode or appropriate symlink privileges; this project does not change system settings.

## Firebase activation

1. Connect the official Firebase plugin to the Gmail/Google account that should own the project, or create a project in [Firebase Console](https://console.firebase.google.com/). No Google account, project, billing plan, or production deployment is created automatically by this repository.
2. Register Android (`com.example.zizouit_manager`), iOS (`com.example.zizouitManager`), and web apps as needed. Enable **Authentication → Email/Password** and create the Firestore database in production/locked mode. Project ownership through Gmail is separate from the app's email/password accounts.
3. Install the Firebase CLI, sign in as the project owner, and deploy the deny-by-default rules: `firebase deploy --only firestore:rules --project YOUR_PROJECT_ID`. Do this before sharing the app with staff. The app does not grant itself database permissions.
4. Copy `firebase_config.example.json` to ignored `firebase_config.json`, filling the actual SDK app IDs, API keys and messaging sender ID. These are client SDK configuration, not a service-account key. Platform-specific API-key fields override `FIREBASE_API_KEY`. Never embed admin credentials.
5. Run `flutter run --dart-define-from-file=firebase_config.json`. For web add `-d chrome`; for a release web build use `./tool/build_web.ps1 -FirebaseConfig firebase_config.json`.
6. Create the manager's app account through the sign-in screen. Copy its displayed Firebase Auth UID. The project owner must use Firebase Console to create `workspaces/zizouit/members/UID` with exactly `{role: "المدير", active: true}`. This is the only bootstrap step; unassigned accounts cannot appoint themselves admin.
7. Sign in again. The manager can assign staff roles by UID through **الإعدادات → عين صلاحية حساب**. Supported roles are المدير, نجاة, سلمى, حسن and لقمان. Roles come from Firestore, not a device dropdown. Existing local data can be exported from local mode and explicitly restored as the authenticated manager; no local dataset is silently uploaded or overwritten.

On this computer, `./tool/firebase.ps1` uses the project-local Firebase CLI when available. Run `./tool/firebase.ps1 login` for the official Google sign-in flow. If Firebase returns an authorization code, complete it privately in the IDE terminal with `./tool/firebase.ps1 login YOUR_AUTHORIZATION_CODE`; do not commit or paste credentials into source files. The helper does not choose a Google account or grant consent on the user's behalf.

The unconfigured/default build stays in clearly marked local demonstration mode. Setting `FIREBASE_ENABLED=true` requires valid Firebase configuration and sign-in; initialization or membership failures never fall back to an unrestricted local admin.

## Synchronization and access control

- `state/private` is the canonical dataset and is readable/writable only by active managers. `state/public` contains operational records with debts, ledger, payments, salary records, closing records, financial audit, costs and collection amounts removed. Staff never fetch the private document.
- Staff submit immutable, UID-owned commands. The manager device automatically replays them against current canonical stock using the same domain validation, then atomically updates both datasets and marks each command applied/rejected. Multiple manager devices are safe: transactions read the command status and canonical state, preventing double application.
- Staff commands are persisted in a per-account outbox and retried with a stable ID; failed delivery is visible. Pending actions do not pretend to be completed inventory. A staff device cannot transfer a newly queued production lot before its authoritative result has arrived.
- A manager app must be open, signed in and connected for automatic command processing. When all manager apps are closed or offline, staff requests remain pending. This avoids a paid Cloud Functions deployment. An always-on trusted processor could be added later if its hosting/costs are approved.
- Manager edits require an online Firestore transaction. Revision conflicts reject the edit rather than overwrite another device; refresh and repeat the operation. Staff retain their last authorized operational view during an open offline session, but starting a Firebase session requires an online membership check.
- Membership changes/revocation lock the UI; Firestore rules independently enforce access. Finance/debt/report/settings pages are restricted to the manager. Private cached account snapshots are cleared on sign-out. Device preferences/outbox files are not encrypted against physical-device access.
- Firebase SDK disk persistence is disabled to avoid sharing its private cache across accounts. The unencrypted app-managed staff outbox remains scoped to workspace, UID and role.
- This first version uses two aggregate Firestore documents with a 750 KB UTF-8 snapshot limit. It refuses oversized snapshots; large histories require migration to per-record collections. It is not an unlimited-scale data model.

See the official [Flutter setup guide](https://firebase.google.com/docs/flutter/setup) and [Firestore access-control guide](https://firebase.google.com/docs/firestore/security/rules-conditions) for provider setup.

## Automatic selling-container recipes

Define bulk material, packaging and the selling product as separate SKUs with their actual stock units. For one 250 g honey jar, a recipe can use **0.25 kg bulk honey + 1 jar + 1 lid + 1 label**, producing **1 selling unit**. Ingredients are recorded in each ingredient SKU's own unit: no guessed kg/litre or density conversion.

Use **الإنتاج → حفظ وصفة** to choose output SKU, basis output quantity, and measured ingredient quantities. Select **عبأت بالوصفة**, then enter actual output count, LOT, participants, hours and optional labor/overhead allocation. Eight outputs consume 2 kg and eight of each packaging component automatically.

The conversion uses eligible workshop lots, earliest expiry first, splitting across lots if required. It refuses expired inputs, shortages, fractional piece counts and an output expiry later than an input. Empty output expiry inherits the earliest input expiry. All deductions and the finished-stock addition are one operation; failure rolls everything back. Finished units enter workshop stock and can then be sold or partially transferred normally. The production record retains the recipe as used. Unknown input/labor costs remain unknown. Legacy text-only recipes stay readable but cannot run automatic conversion until recreated with measured ingredients.

## Working local workflows

- Darija interface, RTL, large buttons, phone and desktop navigation.
- Product families, variants/sizes, units, process types, IDs and search.
- Documented opening inventory, individual LOTs, expiry, counts and movement history.
- Supplier records, order/arrival/agreed due dates and deferred receipts. Najat confirms quantities; the manager approves costs. Confirmed lot costs retain their history; unknown prices remain unknown. Confirming costs after consuming or moving a previously unknown-cost lot requires reconciliation.
- Production with multiple actual inputs including packaging, participants, hours, waste, labor allocation and overhead. Measured/estimated cost flags propagate through lots. Actual output first enters workshop stock; input and output products retain their own units instead of assuming a pressing yield.
- Partial transfers, open shipments, actual receipt confirmation and shipment returns. Transfers create neither sales nor cash expenses.
- Lot/location-specific sales, wholesale, independent discovery/fulfilment channels, partial collection, reservations, delivery/cancellation, below-cost approval and customer returns.
- Separate historical establishment debt, supplier liabilities and customer receivables. Initial payments preserve original debt principal. Unlimited installments must sum to the remaining balance. Payments update the account and debt once and allocate to earliest due installments.
- Customer returns reduce receivables before refunding cash. Supplier returns credit merchandise against payables before recording actual cash recovery; transport is not assumed refundable. Returns require the manager. Existing installment schedules are cleared for review and rescheduling after a credit.
- Workshop/shop/bank/exhibition accounts, opening balances, funding, expenses, account transfers and personal withdrawals. Payments cannot exceed recorded liquidity; withdrawals are not automatically operating expenses.
- Monthly employee payments prevent duplicates for the same employee/month. Hassan's reference salary is 1,000 MAD, recorded only when paid. Production labor allocation is not a second cash payment.
- Daily cash reconciliation records counted/recorded balances and explained variance without inventing a balancing transaction.
- Exhibition files, linked stock/sales/expenses, dedicated cash accounts and Arabic PDF reports. Campaigns with explicitly attributed sales and actual linked costs.
- Local audit, JSON backups/restores with schema/reference checks, previous snapshot retention and rollback after a failed save. No untracked deletion is exposed.

## First use

1. Define real products and suppliers as manager.
2. Record documented opening inventory and account balances. Leave unknown costs blank.
3. Use **تسلمت السلعة**, **صنعت**, **صيفطت السلعة** and **بعت**. Select the actual lot/location.
4. Salma confirms actual shop receipts; the manager approves costs, payments and corrections.
5. Back up with **الإعدادات → نسخة احتياطية JSON** and save the complete copied JSON in a safe file. Restore replaces this device's dataset after an explicit confirmation word.

Data starts empty: no invented prices, balances, transactions, wages, debts or inventory.

## Storage and offline web build

The pilot uses `SharedPreferencesAsync` (mobile/desktop preferences and browser local storage). Each operation saves the aggregate JSON snapshot, retaining the previous successful snapshot. Failed persistence rolls back memory. Optional domain command IDs prevent replays; invoice numbers are unique per supplier. This is not a production transactional database or concurrent multi-tab system. Use one active instance per local dataset.

```powershell
./tool/build_web.ps1
```

Serve `build/web` over HTTPS or localhost. The build script bundles renderer/font resources and generates a versioned asset list for the project's own service worker. A custom bootstrap prevents Flutter's generated unregistering worker from competing for the same scope. Offline loading requires the initial installation/cache to complete. Updates wait for existing tabs to close to avoid changing app versions during work. Development `flutter run` is not an offline installation test. Web PDF export downloads a generated PDF without fetching a viewer from a CDN. Offline loading was verified in isolated headless Chrome; real devices still need acceptance testing.

Clearing browser/app storage deletes local data and unsent outbox entries. Backups are unencrypted JSON. In local demonstration mode, role switching does **not** authenticate people. Cross-device synchronization is available only after Firebase configuration and rule deployment. The offline web smoke check covers local mode; Firebase session startup needs the network and Firebase's web SDK resources.

## Pending production work and decisions

| PDF area | Remaining work/dependency |
| --- | --- |
| Core operations | Structured recipe conversion implemented; real workflow acceptance with Najat and Salma remains |
| Security | Auth, fixed roles and Firestore rules implemented; live rule deployment and device encryption remain |
| Synchronization | Per-user outbox, idempotent manager processing and revision conflicts implemented; connect/create/configure the live Firebase project and test actual devices |
| Inventory valuation | Selected-lot actual costs work; FIFO/weighted-average policy and certified aggregate valuation are undecided |
| Historical debt | Opening outstanding principal is recorded; original historical principal and prior-payment import need verified records |
| Supplier schedules | In-app calendar/overdue display works; background notifications and richer rescheduling/discount settlements remain |
| Wages | Wage rules, accruals, allocation reconciliation and partial monthly wage payments need agreement |
| Reports | Revenue, liquidity, known-cost margins and PDFs work; certified net profit, full general ledger and monthly trends remain |
| Zakat 2026 | Ownership/shares, lunar anniversary, nisab, market valuation and Maliki treatment of debts must be independently reviewed before a final calculator |
| Repayment recommendations | Manager review requested until essential expenses, liquidity reserve, material consumption, replenishment lead times and reliable forecasts exist; no fabricated scenarios or automatic transfers |
| AI/forecasting | Invoice OCR, language assistant and forecasts are not connected; require reviewed provider/backend setup |
| Product images/barcodes | Real photo capture/catalog and barcode scanning not implemented |
| Other decisions | Luqman's appointment/pay, worker hours/wages, budget and hosting remain pending. Luqman is read-only locally; Wiam excluded |

The full production plan is **not** claimed complete. Firebase source integration is present, but no live project/deployment or paid service has been configured. The final zakat ruling remains pending.

## Validation

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

Tests cover partial receipts, deferred purchases, initial and subsequent payments, unknown costs, production, duplicate requests, returns, reservations/cancellation, insufficient stock/cash, role guards, failed saves, invalid backups, phone/desktop navigation, product creation and bundled-font Arabic PDF generation.

The original local version passed 25 tests and an isolated Chrome offline reload. The Firebase/recipe update adds stock-conversion, fixed-role and financial-redaction tests. Native mobile binaries, live Firebase accounts and real-user acceptance have not been tested. The local offline screenshot is `build/web-offline-preview.png`.

Firestore permission tests are in `firebase_tests/`. Install its development dependencies and run `firebase emulators:exec --only firestore --project demo-zizouit-manager "npm --prefix firebase_tests test"`. This uses a demo emulator project; it does not deploy or bill a real Firebase project. Tests cover private-data denial, self-promotion denial, immutable commands, queue ownership, revoked accounts and atomic state revision updates.

To repeat the browser smoke check on Windows with Chrome installed, run `dart tool/verify_web.dart` after the offline build. It uses a fresh profile under `build/` and a temporary loopback server, then closes both.

Noto Naskh Arabic is bundled under the SIL Open Font License in `assets/fonts/OFL.txt`.

# ZIZOUIT Manager

Flutter local working version based on `ZIZOUIT_Manager_Rules_Updated.pdf` (10 October 2026). The user chose Flutter for mobile and web and confirmed there is no configured backend or selected inventory valuation method.

## Run

```powershell
flutter pub get
flutter run -d chrome
```

For Android, connect a device or start an emulator and run `flutter run`. On this computer the SDK is at `C:\Users\HP EliteBook\OneDrive\Desktop\flutter\bin\flutter.bat` if Flutter is absent from PATH. Windows desktop plugins require Developer Mode or appropriate symlink privileges; this project does not change system settings.

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

Clearing browser/app storage deletes local data. Backups are unencrypted JSON. Local role switching demonstrates workflow guards; it does **not** authenticate people or protect data from device access. No cross-device synchronization exists.

## Pending production work and decisions

| PDF area | Remaining work/dependency |
| --- | --- |
| Core operations | Real workflow acceptance with Najat and Salma; production recipes are reference notes, not automated unit conversions |
| Security | Backend identity, database access policies, encrypted storage/queue, tamper-resistant audit |
| Synchronization | Backend configuration, durable operation queue, idempotency across devices and conflict resolution |
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

The full production plan is **not** claimed complete. No paid service, backend, external deployment or final zakat ruling is configured.

## Validation

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

Tests cover partial receipts, deferred purchases, initial and subsequent payments, unknown costs, production, duplicate requests, returns, reservations/cancellation, insufficient stock/cash, role guards, failed saves, invalid backups, phone/desktop navigation, product creation and bundled-font Arabic PDF generation.

Verified on 13 October 2026: 25 tests passed, analyzer reported no issues, release web build succeeded, and isolated Chrome loaded the app online, installed the custom worker, reloaded with network disabled and retained a local-storage marker. The offline screenshot is `build/web-offline-preview.png`. Native mobile binaries and real-user acceptance have not been tested.

To repeat the browser smoke check on Windows with Chrome installed, run `dart tool/verify_web.dart` after the offline build. It uses a fresh profile under `build/` and a temporary loopback server, then closes both.

Noto Naskh Arabic is bundled under the SIL Open Font License in `assets/fonts/OFL.txt`.

# Time Sheets — macOS menu bar app

A lightweight macOS menu bar client for the Time Sheets service at
`lkgeorge.org`. Click the clock icon in the menu bar, fill in your days, and
sign & submit — without opening a browser.

Built with **SwiftUI** (`MenuBarExtra`) as a Swift Package, so there's no
`.xcodeproj` to keep in sync. It runs as a background *agent* — no Dock icon, no
app-switcher entry.

- **Auth:** you paste a personal access token once; it's stored in the macOS
  **Keychain** (never on disk in plaintext) and sent as `Authorization: Bearer tsk_…`.
- **Environments:** develops against the **dev** server by default
  (`timesheets-dev.lkgeorge.org`); flip to **prod** from the gear menu. Dev and
  prod tokens are stored separately.

## Requirements

- macOS 13 (Ventura) or newer — `MenuBarExtra` needs it.
- Xcode 15+ **or** the Xcode command line tools (`xcode-select --install`).

## Build & run

From this folder (`timesheet-menubar/`):

```bash
# Quick dev run (foreground; Ctrl-C to stop):
swift run

# Or build a proper "Time Sheets.app" bundle and launch it:
chmod +x build_app.sh
./build_app.sh --run
```

You can also just open `Package.swift` in Xcode and hit Run.

`build_app.sh` produces `dist/Time Sheets.app`. Drag it to `/Applications`, and
add it under **System Settings → General → Login Items** to launch at login.

## First-time setup

1. In the Time Sheets web app, go to **Settings → API access** and generate a
   personal access token (`tsk_…`).
2. Click the menu bar clock icon → paste the token → **Connect**.
   The app verifies it against `GET /me` and stores it in the Keychain.
3. If a token is ever rejected (HTTP 401), the app drops back to the paste
   screen automatically.

## How it maps to the API

Base URL: `https://timesheets-dev.lkgeorge.org/api/v1` (dev) /
`https://timesheets.lkgeorge.org/api/v1` (prod).

| App action | Request |
|---|---|
| Verify token / greeting | `GET /me` |
| Populate the period picker | `GET /periods` (picks `isCurrent`) |
| Load the 14-day card | `GET /timesheet/{id}` |
| Save one day's edits | `PUT /timesheet/{id}/day` |
| Sign & submit | `POST /timesheet/{id}/submit` |

Times are `"HH:MM"` 24-hour (`""` clears a field); dates `"YYYY-MM-DD"`;
timezone US Eastern. Notes:

- `GET /periods` returns `{ "periods": [...] }`; period ids are integers.
- Editing sends the **whole day** in one `PUT`, so the server can reconcile
  worked time and time off together. A full-day off (`offReason` + `offPortion:"full"`)
  clears the times; a half day (`am`/`pm`) keeps the worked half.
- `submitBlockedUntil` is a human-readable string (e.g. `"Fri Jul 17 at 3:30 PM"`),
  not a timestamp — the app shows it verbatim and disables Submit until the
  server returns `null`.
- Locked/early-submit attempts (HTTP 409/422) surface the server's `error`
  message inline.

## Project layout

```
Sources/TimesheetMenuBar/
  TimesheetApp.swift     App entry, MenuBarExtra scene, accessory-policy delegate
  Config.swift           Dev/prod base URLs, Keychain + defaults keys
  Keychain.swift         Per-environment token storage (Security framework)
  APIClient.swift        Async URLSession client, bearer auth, error mapping
  Models.swift           Codable models for every endpoint (matches API.md)
  AppState.swift         @MainActor view model; owns all API traffic
  Formatting.swift       Date/time parsing + "HH:MM" validation/normalisation
  Views/
    RootView.swift       Router + header/footer (env badge, refresh, quit)
    TokenEntryView.swift  Paste-token screen
    TimesheetView.swift   Period picker, day list, totals, submit
    DayEditView.swift     Single-day editor (worked / time-off)
```

## Schema

The Codable models in `Models.swift` match the field-level reference in
`timesheets-dev/API.md`: `Me`, `Period` (+ the wrapping `PeriodsResponse`),
`PeriodInfo`, `HourTotals` (used for both per-day `hours` and period `totals`),
`DayType` (`slug`/`label`), `OffPortionOption` (`value`/`label`), `Day`, and
`Timesheet`. `dayTypes` and `offPortions` are driven entirely by what the server
returns, so new time-off types or portions appear in the pickers automatically —
nothing is hard-coded.

Day decoding coerces any `null` string field to `""` defensively, so a sparsely
populated day never breaks the editor.

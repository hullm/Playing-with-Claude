# Time Sheets — macOS menu bar app

A lightweight macOS menu bar client for the Time Sheets service at
`lkgeorge.org`. Click the clock icon in the menu bar, fill in your days, and
sign & submit — without opening a browser.

Built with **SwiftUI** (`MenuBarExtra`) as a Swift Package, so there's no
`.xcodeproj` to keep in sync. It runs as a background *agent* — no Dock icon, no
app-switcher entry.

- **Auth:** you paste a personal access token once; it's stored in the macOS
  **Keychain** (never on disk in plaintext) and sent as `Authorization: Bearer tsk_…`.
- **Multiple servers, per-server tokens:** gear → **Servers…** lists Production
  and Development (add your own custom hosts too). Each server keeps its **own**
  token in the Keychain, so switching just reuses the stored one — no re-pasting,
  and switching never touches another server's token. A colored badge in the
  header shows where you are (loud orange for **DEV**, calm green for **PROD**).
  The Servers screen shows which servers have a token (by its 12-char prefix) and
  lets you remove a token or a custom server. A revoked token (401) prompts to
  replace it for that server only.
- **At-a-glance menu bar:** the clock icon swaps to a nudge badge when a draft
  is ready to submit.
- **Weekends hidden by default:** a "Show weekends" toggle in the gear menu
  reveals them; when off, all weekend rows are hidden.
- **Collapsed history:** the period picker keeps every active period but only
  the most recent *completed* one; a "Show all timesheets" toggle (which notes
  how many are hidden) reveals the full history. The period you're viewing is
  always shown.
- **Default hours:** a "Default hours…" gear-menu item edits your standard
  workday start/end (`GET`/`PUT /me/defaults`), which pre-fill blank days.
- **Pre-fill marker:** days you haven't saved yet (still showing default data,
  the API's `saved: false`) carry a small "default" tag so your manually
  entered days stand out.
- **Launch at login:** a toggle in the gear menu (via `SMAppService`).

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
2. Click the menu bar clock icon → confirm the **Server** (defaults to
   `timesheets.lkgeorge.org`) → paste the token → **Connect**.
   The app verifies it against `GET /me` and stores it in the Keychain.
3. If a token is ever rejected (HTTP 401), the app drops back to the paste
   screen automatically.

## Keychain prompts — making "Always Allow" stick

macOS asks for permission when an app reads a Keychain secret. The app now reads
the token **at most once per launch** (it's cached in memory), so you'll see at
most one prompt — click **Always Allow**, not just Allow.

But there's a catch: `build_app.sh` falls back to an **ad-hoc** code signature,
which changes on every build, so macOS can't remember "Always Allow" across
launches and keeps re-asking. The fix is a **stable self-signed certificate**
(free — no Apple Developer account needed). Create it once:

1. Open **Keychain Access** → menu **Certificate Assistant → Create a
   Certificate…**
2. Name: **`Time Sheets Signing`**  ·  Identity Type: *Self Signed Root*  ·
   Certificate Type: **Code Signing**. Click Create.
3. Rebuild: `./build_app.sh`. It auto-detects that identity and signs with it.

Now click **Always Allow** once more and it sticks for good. (Prefer a different
identity? Export its name: `export TIMESHEETS_SIGN_ID="Your Identity"` before
building.)

## How it maps to the API

Base URL: `https://<server>/api/v1`, where `<server>` is the host you enter
(default `timesheets.lkgeorge.org`).

| App action | Request |
|---|---|
| Verify token / greeting | `GET /me` |
| Populate the period picker | `GET /periods` (picks `isCurrent`) |
| Load the 14-day card | `GET /timesheet/{id}` |
| Save one day's edits | `PUT /timesheet/{id}/day` |
| Sign & submit | `POST /timesheet/{id}/submit` |

Times are `"HH:MM"` 24-hour (`""` clears a field); dates `"YYYY-MM-DD"`;
timezone US Eastern. Notes:

- The API uses 24-hour times, but the UI shows and accepts **12-hour AM/PM**
  (e.g. `7:30 AM`); input is converted back to `"HH:MM"` before saving. Typing
  a time with no AM/PM is read as 24-hour, so nothing is ambiguous.
- `GET /periods` returns `{ "periods": [...] }`; period ids are integers.
- A day is a list of **work periods** (`segments`, each `reg`/`ot` with its own
  note). Hours are the **sum** of the periods, never the first-in→last-out span.
  The editor lists every period and lets you add/remove them; saving sends the
  whole `segments` list (it replaces the day). When the server omits `segments`
  (older API), the editor falls back to a single Regular/Overtime pair.
- Editing sends the **whole day** in one `PUT`, reconciling worked time and time
  off together. A full-day off (`offReason` + `offPortion:"full"`) clears the
  periods; a half day (`am`/`pm`) keeps the worked half.
- `submitBlockedUntil` is a human-readable string (e.g. `"Fri Jul 17 at 3:30 PM"`),
  not a timestamp — the app shows it verbatim and disables Submit until the
  server returns `null`.
- Locked/early-submit attempts (HTTP 409/422) surface the server's `error`
  message inline.

## Project layout

```
Sources/TimesheetMenuBar/
  TimesheetApp.swift     App entry, MenuBarExtra scene, accessory-policy delegate
  Config.swift           Server host → base URL helpers, Keychain + defaults keys
  Keychain.swift         Per-server token storage (Security framework)
  LaunchAtLogin.swift    SMAppService wrapper for the login-item toggle
  APIClient.swift        Async URLSession client, bearer auth, error mapping
  Models.swift           Codable models for every endpoint (matches API.md)
  AppState.swift         @MainActor view model; owns all API traffic
  Formatting.swift       Date/time parsing + "HH:MM" validation/normalisation
  Views/
    RootView.swift       Router + header/footer (env badge, refresh, quit)
    TokenEntryView.swift  Paste-token screen
    TimesheetView.swift   Period picker, day list, totals, submit
    DayEditView.swift     Single-day editor (worked / time-off)
icon/
  make_icon.py           Pure-Python generator → AppIcon.png (no deps)
  AppIcon.png            1024×1024 source icon (committed)
make_icon.sh             Mac-side: AppIcon.png → AppIcon.icns (sips + iconutil)
```

## App icon

The icon lives in `icon/AppIcon.png` (already committed). `build_app.sh` turns it
into `AppIcon.icns` and bundles it automatically on macOS. To tweak the artwork,
edit `icon/make_icon.py`, then:

```bash
python3 icon/make_icon.py   # regenerate AppIcon.png
./make_icon.sh              # rebuild AppIcon.icns (macOS)
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

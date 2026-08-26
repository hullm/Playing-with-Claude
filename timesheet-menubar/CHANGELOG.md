# Changelog

All notable changes to the Time Sheets menu bar app. Versions track
`CFBundleShortVersionString` in `Info.plist` and `AppConfig.appVersion`.

## [Unreleased]

_Nothing yet._

## [1.02] — 2026-08-12

### Added
- **A day can be off for two reasons** — e.g. a morning at a screening and an
  afternoon sick. Split days show both reasons ("Cancer Screening (am) + Sick
  Day (pm)"). Each portion's hours are charged to the leave bucket its reason
  names. Uses the API's per-portion `off` array.
- **One chronological list of blocks** in the day editor — work and time off
  in a single ordered list. Each row picks a type (a work kind or an off
  reason); work rows carry start→end + a note, off rows carry a portion
  (**Full / AM / PM / Timed**). **Timed** off carries real start→end times and
  pays clock hours (a 2-hour appointment), versus Full/AM/PM policy hours.
- **Work can coexist with an off day** — log a call-out OT on a sick day. Work
  isn't cleared by time off (the server refuses only work that overlaps the off
  hours, surfaced inline).
- **Adding a half-day off retrims the worked half** — with 8–2 worked, marking
  the morning off leaves 11–2; flipping AM↔PM re-splits the whole day.
- **Server-driven day types** via `GET /day-types` — work kinds and off reasons
  come from the admin-managed catalog; retired reasons still label old sheets
  but aren't offered when creating. Falls back to the timesheet's list if the
  endpoint is absent.

### Changed
- The day list shows every block — work and off — in one chronological line,
  with timed off showing its hours (e.g. `Sick 8:00–10:00, 10:00–2:00, OT 6:00–8:00`).

## [1.01] — 2026-08-03

Everything landed since 1.0.

### Added
- **Multiple work periods per day (split days)** — log more than one work
  segment in a single day, with a worked/off hours breakdown.
- **Multiple servers with per-server tokens** — a server picker (Production,
  Development, and custom hosts). Each server keeps its own token in the
  Keychain, so switching reuses the stored one instead of forcing a re-paste,
  and never touches another server's token.
- **Auto-refresh** — the app quietly re-syncs with the server every 15 minutes
  and on wake from sleep, preserving the period you're viewing.
- **"Open Time Sheets website"** link in the gear menu.

### Changed
- **Environment badge only when off production** — leaving prod raises a loud
  orange **DEV** badge (gray for custom hosts); production shows no badge.
- **Half-day off auto-fills the worked half.**
- **Split-day hours breakdown ordered chronologically.**
- **Version label moved to the footer** (small, secondary, no "v" prefix).

### Fixed
- **Overlapping work periods are rejected** before saving.
- **"Today" highlight stays correct** across midnight and wake from sleep in a
  long-running session.
- **Stray scroll in the day list** when weekends are hidden.

## [1.0] — 2026-07-19

- Initial release: menu bar app for Time Sheets — view the current pay
  period, edit and save day hours, submit, per-day defaults, launch at login.

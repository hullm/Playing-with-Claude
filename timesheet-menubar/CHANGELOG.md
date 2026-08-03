# Changelog

All notable changes to the Time Sheets menu bar app. Versions track
`CFBundleShortVersionString` in `Info.plist` and `AppConfig.appVersion`.

## [Unreleased] — 1.02

_Nothing yet._

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

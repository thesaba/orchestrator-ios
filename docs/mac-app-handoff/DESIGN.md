# Orchestrator for Mac — design specification

This file describes every screen in `design/`. Each screen exists as:

- `design/html/<name>.html` — static HTML with inline styles. Read it for exact sizes, spacing, radii, font sizes and colors.
- `design/png/<name>.png` — a 2x render of the same file. Rendered on Linux, so the typeface is a fallback; the app uses SF Pro and SF Mono.
- `design/tokens.json` — the color values of both themes under semantic names.

Every screen comes in a dark and a light version with identical layout.

## How to read the mockups

- **Style is macOS native.** Use system materials, semantic colors, standard controls and SF Symbols. The hand-drawn SVG icons in the HTML are stand-ins: pick the closest SF Symbol.
- **Context is not content.** The flat desktop ground, the menu-bar strip, and the window shadow only show where a surface sits. Do not build them.
- **All data is sample data.** Server names, percentages, commit hashes, times, durations and deploy steps are invented. Real values come from the API. Real deploy steps come from the deploy stream, whatever their number and names.
- **UI text is English.**
- **Status never relies on color alone.** Healthy is a round dot, warning is a triangle, failure is a cross, and each has a text label nearby. Keep that.

## 1. Menu bar item and popover — `01-popover-*`

**Menu bar item.** App glyph, then a status mark, then the count of open alerts. No mark and no number when everything is healthy. Warning shows the triangle. While a deploy runs, the item shows an upward arrow.

**Popover.** 400 pt wide, content-height, corner radius 14, padding 14, 12 pt between sections. Top to bottom:

1. **Header.** Title "Orchestrator", a one-line summary under it ("All systems healthy" or "2 items need attention" in the warning color), then Refresh and Settings icon buttons (28 pt).
2. **Summary tiles.** Three equal cards: Servers, Sites, Alerts. Each has a caption, a large number and a one-line breakdown. The Alerts number takes the warning color when it is above zero.
3. **Segmented control.** Overview, Servers, Sites, Alerts. The mockup shows Overview. The other three show the full list of their kind with the same row design.
4. **Needs attention.** Only present when there are open alerts. Tinted card, one row per alert: triangle, title, subtitle (source and age), and one contextual button (View, Renew).
5. **Servers.** Up to four rows on Overview, sorted with unhealthy first. Row: status mark, name, location and state, then two mini meters (CPU, RAM) with percentage. A server with a warning shows the reason in the warning color in place of "Healthy". "All N" opens the Servers segment.
6. **Sites.** Up to three rows on Overview, a running deploy first. Normal row: status dot, name, branch, short commit, relative deploy time, Deploy button. Deploying row: tinted, shows the current step and a progress bar, and its button is "Show log", which opens the compact log panel.
7. **Footer.** "Updated N s ago" on the left, the command-palette shortcut on the right.

## 2. Notifications — `02-notifications-*`

Standard system notifications with action buttons. Four kinds:

| Kind | Body | Actions |
|---|---|---|
| Deploy finished | site, branch, commit, duration | none; click opens the log |
| Deploy failed | site, failed step, whether the previous release is still live | Explain, Open log, Retry |
| Server alert (disk, CPU, RAM, offline) | server, location, detail | Open server, Mute for 1 hour |
| SSL expiring | site | Renew now, Remind tomorrow |

Retry and Renew now change production. They follow the confirmation rules in `PROMPT.md`.

## 3. Command palette — `03-command-palette-*`

A floating panel opened with a global shortcut (default Option-Space, configurable). 640 pt wide, corner radius 16, centered horizontally in the upper third of the active screen. It closes on Escape and on losing focus.

- **Field.** 56 pt tall, 20 pt text, search icon on the left, "esc" hint on the right.
- **Results.** Grouped under small caps headers: Actions, Servers, Open. Row is 44 pt: a 28 pt icon tile, the title, a secondary detail on the same line, and trailing badges. The selected row uses the accent fill with white text. Arrow keys move the selection and the list scrolls when it is longer than about eight rows.
- **Touch ID badge.** Shown on every action that needs confirmation: rollback, maintenance mode, anything destructive.
- **Footer.** Key hints: Return runs, Command-Return runs and opens the log, Option-Return opens a branch or ref picker for deploys. Result count on the right.
- **Matching.** Fuzzy over the verb and the target, so "dep ci" finds "Deploy citynet.ge". Recently used commands rank higher.

Commands to support: deploy, roll back, clear cache, maintenance on and off, restart queue, run an artisan command, SSH into a server, open site logs, open the last deploy log, open a site or server in the web panel.

## 4. Deploy log, compact panel — `04-deploy-log-compact-*`

A small floating panel, 480 pt wide, corner radius 14. It appears when a deploy starts from the app, and from "Show log" in the popover.

- **Title bar.** Deploy arrow, "Deploying <site>", branch and commit, then three 26 pt buttons: keep on top (accent fill when on), expand to the full window, close. Closing never stops the deploy.
- **Progress.** "Step N of M · <step name>" with the elapsed time on the right in monospace. Below it, one segment per step: done is green, current is accent, pending is the track color.
- **Log.** Monospace, 11.5 pt, timestamp in the dim color, step headers bold. Shows the tail of the stream.
- **Footer.** "Follow output" checkbox (auto-scroll), and Copy log.

When the deploy ends, the title changes to "Deployed <site>" or "Deploy failed" and the panel stays until dismissed.

## 5. Deploy log, full window — `05-deploy-log-window-*`

A regular window, about 1120 by 648 pt, resizable. The mockup shows a failed deploy so the error state is visible.

- **Toolbar.** Site name with the outcome under it (colored by outcome), a search field, an "Errors only" toggle, Copy log, and a button that shrinks back to the compact panel.
- **Sidebar, 280 pt.** "Steps": one row per step with a check, cross or dash, the name and the duration. The failed step is tinted and bold. Skipped steps are dimmed. Clicking a step scrolls the log to it. Below, "Previous deploys": outcome, date, branch and commit, duration. Clicking one loads its log.
- **Info strip.** Branch, commit and commit message on the left, start time and total duration on the right.
- **Log.** Monospace 12 pt. Error lines get the danger tint across the full width and the danger text color.
- **Failure banner.** Tinted bar at the bottom: what failed, what state the site is in, then Copy error, Retry deploy and Explain error (accent). Explain error shows the AI explanation in a sheet. On success there is no banner.

## 6. Desktop widgets — `06-widgets-*`

Widgets are snapshots, not live views. They are read-only. A click opens the matching part of the app. Corner radius and padding follow the system.

- **Small, status.** "Orchestrator", a status mark, the number of open alerts in large type, then servers healthy and sites up. With no alerts it shows a check and "All healthy".
- **Small, last deploy.** Site, outcome, branch and commit, when and how long.
- **Medium, servers.** Four servers, unhealthy first: status mark, name, one meter and its value. The meter shows CPU, or the metric that triggered a warning.
- **Large, overview.** Three summary tiles, then Alerts (up to two), Recent deploys (three), and the busiest server.

Every widget shows "Updated HH:mm" so stale data is visible.

## States that are not drawn

Build these with standard macOS patterns and keep them consistent across surfaces:

- **Signed out.** The popover shows a short explanation and a "Sign in" button that opens a small sign-in window.
- **Loading.** Redacted placeholders on first load. Later refreshes keep the old data visible.
- **Offline or API error.** Keep the last data, show "Last updated HH:mm" and the reason in the footer, and turn the menu bar item to a neutral "unknown" mark.
- **Empty.** No servers, no sites, no alerts, no results in the palette.
- **Deploy succeeded** in the compact panel and the full window.
- **Settings window.** Account, global shortcut, refresh interval, notification kinds, launch at login.

# Orchestrator for Mac — build prompt

You are going to build a native macOS companion app for Orchestrator, my server and deployment control panel. This file is the brief. Read it fully, then read `DESIGN.md` and look at the files in `design/` before you write any code.

Talk to me in Georgian. Write code, comments, commit messages and UI text in English.

## 1. Goal

A menu bar app that lets me watch my servers and sites and run common operations without opening the web panel. It is **not** a port of the iOS app. It has four surfaces:

1. A menu bar item with a popover: live status of servers, sites and alerts.
2. A command palette on a global shortcut: deploy, roll back, clear cache, maintenance, SSH and more.
3. A live deploy log: a small floating panel that expands into a full window.
4. Desktop widgets and system notifications.

## 2. What already exists

Everything in this section was true when I last checked (August to September 2026). The repository is the source of truth: **verify each point by reading the code before you rely on it**, and tell me where reality differs.

- **Backend.** A REST API at `https://orchestrator.abesadze.digital/api`. You do not modify the backend.
- **iOS client.** This repository: a SwiftUI app, project `Orchestrator.xcodeproj`, scheme `Orchestrator`, about 74 Swift files. Deployment target iOS 26.5. `SWIFT_DEFAULT_ACTOR_ISOLATION` is `nonisolated` and view models are `@MainActor`. New Swift files under `Orchestrator/` are picked up automatically (file-system-synchronized groups). It builds with zero warnings.
- **Layers of the iOS app.**
  - `Core/`: `APIClient` (bearer auth, typed errors, SSE as `AsyncThrowingStream`, downloads), `Keychain`, `TokenStore`, `Session`, the `OrchestratorAPI` façade split into extensions, `StreamRunner` (one SSE driver for every `/stream` route, with reconnect), `ActionRunner`, `TerminalClient`, and lenient decoding helpers.
  - `DesignSystem/`: `StatusTone` and badges, money, byte and duration formatters, load-state views, a log console with an ANSI stripper.
  - `Features/`: the iOS screens.
- **Auth.** A personal access token (`orch_…`) stored in the Keychain is the primary method. JWT with TOTP is the fallback.
- **API shapes that were verified against the web panel's own client:**
  - Deploy: `POST /sites/:id/deploy?ref=<branch|tag|sha>&skipTests=1`, query parameters only, no body.
  - Maintenance: `POST /sites/:id/maintenance` with `{action: "down" | "up", secret?}`.
  - Rollback takes `{release}`. Artisan takes `{command}`.
  - Site logs: `GET /sites/:id/logs?level=&search=&lines=`.
  - Monitoring: `GET /monitor/history?hours=`, `GET /monitor/processes?limit=`.
  - AI: `/ai/explain-deploy/:id` and `/ai/explain-error/:id?force=1`.
  - `GET /sites` embeds full deploy logs, roughly 166 KB per site. Do not poll it on a short interval.
- **Reference for unknown endpoints.** `tools/probe-web-bundle.sh` extracts the web panel's JavaScript into `tools/bundle.js`. That bundle and the iOS façade are where you look up request and response shapes. The multi-server fleet features (server list, metrics, alerts, SSL status) are newer than my notes, so you must find their endpoints there.

## 3. Safety rules — the backend is production

Orchestrator hosts live client sites. Nothing you do while building may change or take down a site. These rules override everything else in this file.

1. From your own tooling (curl, scripts, tests, previews) call **GET only**. Never send POST, PATCH, PUT or DELETE to the live API.
2. Do not attach to any `/stream` endpoint yourself. The app attaches to streams only on my action.
3. You build every write path, but **I** exercise it, against a site I pick. Tell me when one is ready to try.
4. Never guess an API shape for a write. If the bundle and the iOS code do not settle it, ask me.
5. In the app, every action that changes production asks for confirmation that names the concrete consequence. Rollback, maintenance mode and anything destructive also require Touch ID (or the account password) through `LocalAuthentication`.
6. Widgets and plain notification clicks never trigger a write.
7. Never print, log or commit the access token.
8. Do not commit or push unless I ask.

## 4. Design package

- `DESIGN.md`: the specification of every screen, including states that are not drawn.
- `design/html/*.html`: static mockups with inline styles. Take exact sizes, spacing, radii and font sizes from them.
- `design/png/*.png`: renders of the same mockups. Look at them first to get the picture.
- `design/tokens.json`: both themes' colors under semantic names.

The look is **macOS native**. Use system materials, semantic colors, standard controls, SF Pro, SF Mono and SF Symbols. Take from `tokens.json` only what the system does not give you: status colors, tints and the log view. The mockups' desktop background, menu-bar strip and sample data are context, not things to build. Support light and dark by following the system appearance.

## 5. Architecture

Propose the details in phase 0. These are the constraints.

- **Shared package.** Extract the platform-neutral code from the iOS app into a local Swift package (suggested name `OrchestratorKit`): networking, Keychain and token storage, session, the API façade, stream and action runners, models, decoding helpers, and the cross-platform parts of the design system such as `StatusTone` and the formatters. The iOS app must depend on the package and still build with zero warnings and unchanged behavior. Move code, do not copy it.
- **macOS app target.** In the same Xcode project. An agent app with no Dock icon (`LSUIElement`). The menu bar item is a `MenuBarExtra` in window style, or `NSStatusItem` with `NSPopover` if `MenuBarExtra` cannot do what the design needs. The command palette and the compact log are non-activating floating `NSPanel`s. The full log and settings are ordinary windows.
- **Widget extension target.** WidgetKit. The app and the extension share data through an App Group and the token through a shared Keychain access group. The app writes a compact snapshot after each refresh and asks WidgetKit to reload. The extension can also fetch by itself on its timeline.
- **Deployment target.** macOS 26. Tell me if you see a reason to go lower.
- **Concurrency.** Same settings as the iOS target: default isolation `nonisolated`, view models `@MainActor`.
- **Refresh.** No stream is held open for monitoring unless the API offers one for it. Poll: fast while the popover is open, slow in the background, paused during sleep and when offline. Make the intervals a setting. Use lightweight endpoints, never `GET /sites` on a short interval. If no lightweight endpoint exists for something the design needs, list it for me as a possible backend change.
- **Dependencies.** Prefer system frameworks. Ask before adding any third-party package, and say why.
- **Code style.** Small files, one type per file, reusable views. Match the naming and structure of the existing iOS code.

## 6. Phases

Work one phase at a time. At the end of each phase, build, summarize what changed, list what I need to try by hand, and wait for me.

### Phase 0 — reconnaissance and plan (read-only)

Write no production code. Read the repository and report:

1. Where this file's section 2 no longer matches the code.
2. Which files move into the shared package and which stay in the iOS target, with any code that needs `#if os()` or a small refactor.
3. For every piece of data and every action in `DESIGN.md`: the endpoint, its request and response shape, and where you found it. Mark anything you could not find.
4. Whether the app can attach to the stream of a deploy that was started somewhere else (web panel, phone), and how it can learn that a deploy is running.
5. The proposed target layout, folder structure and the order of work.
6. Open questions for me.

Stop and wait for my approval.

### Phase 1 — foundation, popover, notifications

- Extract the shared package. The iOS app builds and behaves as before.
- Create the macOS target with sign-in (token in the Keychain) and a settings window.
- Menu bar item and the popover from `DESIGN.md` section 1, with all four segments and the undrawn states. Read-only: the Deploy, Renew and similar buttons are present but disabled, or open the web panel.
- Notifications for deploy results, server alerts and SSL expiry. In this phase their actions only open things.
- Launch at login.

Done when: the iOS scheme and the macOS scheme both build with zero warnings, the popover shows real data from GET requests, and status changes reach the menu bar item and Notification Center.

### Phase 2 — command palette and deploy log

- Global shortcut (default Option-Space, configurable) and the palette from `DESIGN.md` section 3, with fuzzy matching and keyboard navigation.
- All commands listed in `DESIGN.md`, each through the confirmation rules in section 3 of this file. SSH opens the system Terminal.
- Compact log panel and full log window from `DESIGN.md` sections 4 and 5, driven by the shared `StreamRunner`. Previous deploy logs. Failure banner with "Explain error".
- Wire the popover buttons and the notification actions that were inert in phase 1.

Done when: every write path is implemented and listed for me to try, and nothing in the app can change production without an explicit confirmation.

### Phase 3 — widgets and system integration

- The four widgets from `DESIGN.md` section 6.
- App Intents for the main commands, so they appear in Shortcuts and Spotlight. Intents that change production ask for confirmation.
- Deep links from widgets and notifications into the right place in the app.

Propose these separately before building them: offering a deploy after a `git push` in a local repository, and dragging a file onto the app to upload it to a site.

## 7. Quality bar

- Both schemes build with zero warnings after every phase. Use `xcodebuild`, or the XcodeBuildMCP tools if they are available to you.
- The repository has no test target. Add one for the shared package and cover the pure logic: fuzzy matching and ranking, status aggregation for the menu bar item, decoding of the responses the Mac app uses, and time and duration formatting.
- Accessibility: every control has a label, the palette and popover are fully usable from the keyboard, and VoiceOver reads status marks as words.
- No sample data in the shipped code. Previews may use fixtures.
- Keep `README.md` current when you add a target, a setting or a setup step.

## 8. How to start

Begin phase 0 now. Read `DESIGN.md`, open the PNGs, read the iOS code, and give me the report described above.

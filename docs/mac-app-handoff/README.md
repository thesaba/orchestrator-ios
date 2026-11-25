# Orchestrator for Mac — handoff package

Put this folder inside the Orchestrator repository (for example at `docs/mac-app-handoff/`) and give Claude Code the content of `PROMPT.md`, or tell it to read that file.

| Path | What it is |
|---|---|
| `PROMPT.md` | The brief for Claude Code: goal, existing code, safety rules, architecture, phases, quality bar |
| `DESIGN.md` | Screen-by-screen specification, including states that are not drawn |
| `design/png/` | 12 screenshots at 2x: six screens, each dark and light |
| `design/html/` | The same screens as static HTML with inline styles, for exact measurements |
| `design/tokens.json` | Colors of both themes under semantic names, plus radii |

The screenshots were rendered on Linux, so the typeface is a fallback. The app itself uses SF Pro and SF Mono. All data in the mockups is sample data.

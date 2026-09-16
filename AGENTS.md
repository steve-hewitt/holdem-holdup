# Agent Instructions

Godot **4.7.2** + **GDScript**. "Hold'em Holdup" is a complete, single-player
no-limit Texas Hold'em game: you play against three AI opponents at a four-seat
table. The main scene is `res://scenes/main.tscn`; the table UI is built in code
(no `.tscn` beyond the root node).

## Godot CLI (Linux)

`godot` is v4.7.2 on PATH (`~/.local/bin/godot`). Run CLI commands with `--path .`.

```bash
godot --headless --path . --import              # reimport assets; refresh .godot after adding files
godot --headless --path . --script res://foo.gd # run a script (must `extends SceneTree` and call quit())
godot --editor --path .                         # open the GUI editor
godot --path .                                  # run the game
```

- A newly added `class_name`/asset is not registered until `--import` runs.
- Headless smoke run: `godot --headless --path . --quit-after 120`.

## Godot AI MCP — intentionally disabled

This repo deliberately opts out of the editor MCP to stay isolated from the
sibling `wizards-tower` project, which owns the shared godot-ai server on
8000/9500. **Do not re-enable `addons/godot_ai` here.**

- `project.godot` has no `[editor_plugins]` entry and no `_mcp_game_helper` autoload.
- The project-local `opencode.json` sets `mcp.godot-ai.enabled = false` (only for
  this repo); `opencode debug config` confirms it while `openpencil`/`github` survive.

So `godot --editor --path .` here never starts or adopts the shared server, and
`session_manage(op="list")` will show no session — expected. Develop with the CLI
and GUT. If MCP is ever needed, give this repo its own `XDG_CONFIG_HOME` + port
pair (e.g. 8001/9501) instead of reusing 8000/9500.

## Game structure

- `scripts/core/` — pure rules, no UI:
  - `card.gd`, `deck.gd` — cards and a seedable deck.
  - `hand_evaluator.gd` — best-of-7 evaluation, categories, tiebreakers, wheels.
  - `player.gd` — per-seat runtime state.
  - `poker_game.gd` — turn/street state machine: blinds, min-raise rules, short
    all-ins, side pots, uncalled-bet refunds, split pots, odd chips, dealer
    rotation, heads-up blinds. Public API: `setup`, `start_hand`,
    `get_legal_actions`, `apply` — `start_hand`/`apply` each return a fresh Array
    of presentation events (they do **not** accumulate).
- `scripts/core/poker_ai.gd` — Monte Carlo equity plus personality-weighted
  betting (`rock` / `aggressive` / `loose` / `balanced`).
- `scripts/ui/` — `card_view.gd`, `seat_view.gd`, `table_view.gd` draw the table
  and animate events. `table_view.instant = true` applies events without
  animation (used by turbo tests).
- `scripts/main.gd` — screens, turn loop, input, pause/results.
- `scripts/audio/sound_bank.gd` — autoloaded as `SoundBank`; synthesises all SFX.

## Controls

Mouse/touch buttons; keyboard `F` fold, `C`/`Space` check/call, `R` raise
(`↑`/`↓` adjust the amount), `Esc` pause. Mobile orientation is landscape.

## Development / test flags

Pass after `--`, e.g. `godot --path . -- --autoplay`. These are test aids and
safe to leave in the code:

- `--autoplay` — an AI plays the human seat by pressing the real UI buttons.
- `--turbo` — implies `--autoplay`; skips animation and delays.
- `--hands=N` — quit after N hands, printing chip totals.
- `--shot=path.png` / `--frames=N` — start a game and screenshot after N frames.
- `--shot-title=path.png` — screenshot the title screen.
- `--shot=path.png --shot-screen=pause|result` — screenshot those screens.
- `--showdown=show-all|muck` — showdown reveal policy override (default
  `show_all`; the `holdem_holdup/showdown_reveal` project setting is the
  no-code-change default).

## Tests

**GUT 9.7.1** is installed under `addons/gut/`. Tests live in `test/`, named
`test_*.gd`, extending `GutTest`. Run them headless:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit
```

Run `--import` first after adding a test script. If `res://test` is missing,
GUT prints "Nothing was run" and still exits 0 (a silent pass). There is no
package manager / npm / pytest here — do not invent test commands.

## Conventions & gotchas

- Renderer is `mobile` with `canvas_items` stretch; 3D uses Jolt Physics.
  `rendering_device/driver.windows="d3d12"` is Windows-only — on Linux the
  mobile renderer runs on Vulkan.
- Commit Godot `.import` sidecars next to their assets. Never commit `.godot/`,
  `/android/`, or `*Zone.Identifier*` (Windows extraction artifacts) — already gitignored.
- `addons/.godot_ai_update/` is update staging and self-ignored; leave it alone.

## Beads issue tracking

Uses `bd`; run `bd prime` for the full workflow. Prefix: `holdem-holdup`.
Invoke `bd` via the shell (there is no `bd` tool). Default profile is
conservative: do not commit, push, or `bd dolt push` unless explicitly asked.
Sync remote: `git+https://github.com/steve-hewitt/holdem-holdup.git`.

`AGENTS.md` and `CLAUDE.md` are independent copies — mirror substantive edits.

# Hold'em Holdup

A small, polished single-player **Texas Hold'em** game built with **Godot 4.7.2**
(GDScript). Sit down at a four-seat table and play no-limit hold'em against three
AI opponents with distinct personalities.

## Features

- Complete no-limit Texas Hold'em rules: blinds, min-raise rules, short all-ins,
  side pots, uncalled-bet refunds, split pots, odd chips, and heads-up blinds.
- Three AI rivals with different styles (tight, aggressive, loose) that estimate
  their equity with a small Monte Carlo simulation.
- Blinds rise every 8 hands; bust the table to win.
- Mouse, keyboard, and touch controls; the game runs in landscape.
- Animated card dealing and flips, flying chips, and fully synthesised sound
  effects (no audio assets required).

## Requirements

- Godot **4.7.2** (`godot` on PATH)
- [uv](https://docs.astral.sh/uv/) — only for the Godot AI MCP server (dev tooling)

## Running

```bash
godot --path .            # play
godot --editor --path .   # open the editor
```

## Controls

| Action | Mouse / touch | Keyboard |
| --- | --- | --- |
| Fold | Fold button | `F` |
| Check / Call | Check / Call button | `C` or `Space` |
| Bet / Raise | Bet / Raise button | `R` or `Enter` |
| Adjust raise | drag the slider / quick-bet buttons | `↑` / `↓` |
| Pause | Menu button | `Esc` |

## Tests

Uses [GUT](https://github.com/bitwes/gut) 9.7.1 (`addons/gut/`); tests live in `test/`.

```bash
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit
```

The suite covers hand evaluation, betting/street transitions, side pots, all-ins,
ties and odd chips, dealer rotation, heads-up blinds, chip conservation over
hundreds of self-played hands, and AI decision legality.

## Layout

- `project.godot` — engine config (mobile renderer, Jolt 3D physics, autoloads)
- `scenes/main.tscn` — main scene (the UI is built in code)
- `scripts/core/` — rules engine, hand evaluator, players, and AI
- `scripts/ui/` — table, seats, cards, and the action bar
- `scripts/audio/` — procedural sound synthesis
- `scripts/main.gd` — screens, turn loop, and input
- `test/` — GUT tests

### Development / test flags

Pass after `--`, e.g. `godot --path . -- --autoplay`:
`--autoplay`, `--turbo`, `--hands=N`, `--shot=path.png --frames=N`,
`--shot-title=path.png`, `--shot=path.png --shot-screen=pause|result`,
`--showdown=show-all|muck` (showdown reveal policy; default `show_all`, also
settable via the `holdem_holdup/showdown_reveal` project setting).

Issue tracking is handled by [Beads](https://github.com/steveyegge/beads) (`bd`).

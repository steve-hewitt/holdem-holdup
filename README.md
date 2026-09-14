# Hold'em Holdup

A mobile Texas Hold'em game built with **Godot 4.7.2** (GDScript).

> **Status:** early scaffold. No scenes or scripts exist yet, and the project has
> no main scene — `godot --path .` will not start anything until one is added.

## Requirements

- Godot **4.7.2** (`godot` on PATH)
- [uv](https://docs.astral.sh/uv/) — only for the Godot AI MCP server (dev tooling)

## Running

```bash
godot --editor --path .   # open the editor
godot --path .            # run the game (currently errors: no main scene)
```

## Tests

Uses [GUT](https://github.com/bitwes/gut) 9.7.1 (`addons/gut/`); tests live in `test/`.

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit
```

## Layout

- `project.godot` — engine config (mobile renderer, Jolt 3D physics, `canvas_items` stretch)
- `addons/godot_ai` — MCP bridge between the editor and AI agents (dev tooling)
- `addons/gut` — test framework
- `test/` — GUT tests
- `AGENTS.md` / `CLAUDE.md` — instructions for AI coding agents

Issue tracking is handled by [Beads](https://github.com/steveyegge/beads) (`bd`).

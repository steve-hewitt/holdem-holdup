# Agent Instructions

Godot **4.7.2** + **GDScript**. "Hold'em Holdup" is a greenfield mobile-game
scaffold: no scenes, scripts, or main scene exist yet — only `project.godot`
and `icon.svg`.

## Godot CLI (Linux)

`godot` is v4.7.2 on PATH (`~/.local/bin/godot`). Run CLI commands with `--path .`.

```bash
godot --headless --path . --import              # reimport assets; refresh .godot after adding files
godot --headless --path . --script res://foo.gd # run a script (must `extends SceneTree` and call quit())
godot --editor --path .                         # open the GUI editor
godot --path .                                  # run the game — currently FAILS (no main scene)
```

- There is **no main scene**, so plain `godot --path .` exits with
  `Can't run project: no main scene defined`. Set one before relying on a run command.
- A newly added `class_name`/asset is not registered until `--import` runs.

## Godot AI MCP

`addons/godot_ai` (v4.1.0) is enabled in `project.godot`, and the `godot-ai`
server is configured in `~/.config/opencode/opencode.json` (HTTP 8000 / WS 9500).
The `godot-ai_*` tools only work while an editor with the plugin is running.

```bash
# Start a headless editor that serves MCP. GODOT_AI_ALLOW_HEADLESS=1 is REQUIRED:
# without it the plugin self-disables MCP whenever it launches headless.
GODOT_AI_ALLOW_HEADLESS=1 setsid nohup godot --headless --editor --path . \
  > /tmp/godot_ai_editor.log 2>&1 < /dev/null &
```

- Confirm with `session_manage(op="list")`; `readiness: "no_scene"` is normal until a scene exists.
- Scene/node/property edits are in-memory until `scene_save` (or `project_run(autosave=True)`).
- Stop with `editor_manage(op="quit")` or by killing the `godot --headless --editor` PID.
- If the `godot-ai` entry drifts: `client_manage(op="configure", params={"client": "opencode"})`.

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

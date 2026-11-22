# Error Log

Chronological list of problems encountered while building **Chroma Chameleon** and how they
were fixed. Kept in English like the rest of the documentation.

## 1. Godot, Git and GitHub CLI not installed

- **Symptom:** `godot`, `git` and `gh` were not available on `PATH`.
- **Fix:** Portable copies were installed under `%LOCALAPPDATA%\OpenCodeTools\`:
  - `godot\Godot_v4.7.2-stable_win64_console.exe` and `..._win64.exe`
  - `git\cmd\git.exe` (2.56.1)
  - `gh\bin\gh.exe` (2.105.0)
- **Status:** Resolved. (The user also has a GUI copy at
  `C:\Users\SANHAJI SERVER\Desktop\Godot\Godot_v4.7.2-stable_win64.exe`.)

## 2. GDScript reserved keyword `pass` used as a variable name

- **Symptom:** `Parse Error: Expected identifier` in `Main.gd` (`_on_host`) when hosting.
- **Cause:** `pass` is a reserved GDScript keyword and cannot be used as a local variable.
- **Fix:** Renamed the local variable to `pwd`.
- **Status:** Resolved.

## 3. `broadcast()` not found in `MatchDirector`

- **Symptom:** `Parse Error: Function "broadcast()" not found in base self.` at nine locations.
- **Cause:** `broadcast()` belongs to the `Net` autoload, not to `MatchDirector`.
- **Fix:** Replaced all calls with `Net.broadcast(...)`.
- **Status:** Resolved.

## 4. `Environment.fog_color` invalid in Godot 4.7

- **Symptom:** `Invalid assignment of property or key 'fog_color' ... on Environment`.
- **Fix:** In `Arena.gd`, use `env.fog_light_color = theme["fog"]` (verified against the
  4.7 class reference).
- **Status:** Resolved.

## 5. `TorusMesh.radial_segments` invalid in Godot 4.7

- **Symptom:** `Invalid assignment of property or key 'radial_segments' ... on TorusMesh`.
- **Fix:** In `Arena.gd` and `Player.gd`, use `ring_segments` instead.
- **Status:** Resolved.

## 6. Smoke test via `--script` could not see autoloads

- **Symptom:** Running `tests/SmokeTest.gd` with `--script` produced
  `Compile Error: Identifier not found: Net`, because autoloads are not registered for a
  standalone script run. The test then timed out.
- **Fix:** Removed the standalone test and added command-line hooks inside the real main
  scene: `-- --auto-practice`, `-- --auto-host`, `-- --auto-join`. Running the actual scene
  with `--headless --quit-after N` now works.
- **Status:** Resolved.

## 7. Client connected but never authenticated

- **Symptom:** Host log showed `Peer 2 handshaking...` and client showed
  `CONNECTED - authenticating`, but no `welcome` and no join event.
- **Cause:** `Net._poll_client()` set `_hello_sent = true` without ever sending the message.
- **Fix:** Send the hello payload once the socket is open:

  ```gdscript
  send({"t": "hello", "name": GameState.player_name, "password": password})
  ```

- **Verification:** Host logs `hello` then `CHAMELEON JOINED`; client logs `welcome` and
  `AUTHENTICATED AS PLAYER 2`.
- **Status:** Resolved.

## 8. Debug client raced the host startup

- **Symptom:** An early `--auto-join` run produced no output because it connected before the
  host was listening.
- **Fix:** The debug hook defers the join by 1.5 s (`_auto_join_delayed()`).
- **Status:** Resolved (test-only issue).

## 9. Wakatime editor plugin popup / CI interference

- **Symptom:** The bundled `godot_super-wakatime` plugin calls `request_api_key()` and shows a
  modal popup when the editor starts without a key. In headless export it also tried to
  download the Wakatime CLI and failed with `Could not create child process`.
- **Attempted fix:** Setting `enabled=PackedStringArray()` in `project.godot` worked until the
  running editor rewrote the file and restored the plugin entry.
- **Final fix:** Added an early return in the plugin's `_ready()` when running headless or
  when the `CI` environment variable is set, plus a null guard in `_exit_tree()`. Plugin files
  were otherwise left untouched and it still works normally in the GUI editor.
- **Status:** Resolved.

## 10. Two Godot editor instances for the same project

- **Symptom:** Launching a second editor while the project was already open resulted in a
  short-lived extra process.
- **Fix:** Kept the existing editor instance. Only one editor should edit a project at a
  time; the extra window closed by itself.
- **Status:** Resolved / informational.

## 11. Harmless typo in a one-off asset verification snippet

- **Symptom:** A throwaway check used a wrong list index on its first run while validating
  generated WAV/PNG files.
- **Fix:** Corrected and reran the check; all 16 generated assets passed validation. The
  generator scripts themselves were never affected.
- **Status:** Resolved / informational.

## 12. Movement felt broken when the keyboard focus was outside the game

- **Symptom:** Pressing WASD did nothing after clicking a menu field or a browser toolbar.
- **Cause:** The full-screen UI `Control` layers swallowed mouse events, and keyboard focus
  can stay on a `LineEdit` after a menu is hidden. The movement math itself was correct.
- **Fix:** Split input reading from movement in `Main.gd` (`_keyboard_direction()` and
  `_apply_movement()`), set the UI roots to `MOUSE_FILTER_IGNORE`, and add a mouse move pad
  in the HUD. `Input.is_key_pressed()` still works as a fallback.
- **Verification:** New `--test-movement` headless flag prints a non-zero distance and the
  white default color.
- **Status:** Resolved.

## 13. Characters were chameleons with pre-assigned colors

- **Symptom:** Avatars had a tail and started in one of four random colors.
- **Fix:** Rewrote `Player.gd` as a low-poly human figure (head, arms, legs, shoes) and added
  `GameState.WHITE` as paint index 4. `MatchDirector` now spawns every player white.
- **Status:** Resolved.

## 14. Paint swatches were only decorative

- **Symptom:** The four color boxes in the HUD were `Panel` nodes and could not be clicked.
- **Fix:** Replaced them with real `Button` nodes that emit `paint_selected`, connected to
  `Main._on_paint_selected()`. Added a white swatch to wipe the paint off.
- **Status:** Resolved.

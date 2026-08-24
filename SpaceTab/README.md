# SpaceTab

A Cmd-Tab replacement: vertical window lists, one column per space.
Also a Cmd-Space launcher: type to open apps and windows.

- **Cmd-Tab** opens the switcher (and steps to the next window); hold Cmd.
- **Tab / Down / Up** move within the current column (wrapping).
- **Left / Right** move between spaces.
- **W** closes the selected window (hops to its space and back if needed).
- **Release Cmd** (or Return) to switch to the selected window.
- **Escape** cancels.

### Launcher (Cmd-Space)

- Type to match applications (by name) and open windows (by title or app
  name). Ranked by match quality, then recency of use.
- **Enter** on an app opens a new window on the current space (via a Cmd-N
  probe posted to the app; apps that ignore it are remembered in
  `defaults read com.drmaciver.spacetab appsWithoutNewWindowSupport` and get
  switch-to-existing-window behaviour immediately). Not-running apps are
  launched. **Enter** on a window switches to it, changing space if needed.
- **Up/Down/Tab** navigate, **Escape** or **Cmd-Space** dismisses.

## Running

```sh
swift run SpaceTab          # takes over Cmd-Tab while running; Ctrl-C to stop
swift run SpaceTab --list   # debug: dump spaces and windows
swift run ModelTests        # run navigation model tests
```

Requires Accessibility permission for the terminal you launch it from
(System Settings > Privacy & Security > Accessibility). Window titles use
the Accessibility API, so no Screen Recording permission is needed.

## How it works

- Spaces and per-space window IDs come from private SkyLight calls
  (`SLSCopyManagedDisplaySpaces`, `SLSCopyWindowsWithOptionsAndTags`) — the
  same ones yabai and AltTab use. Private APIs can break in OS updates.
- Window metadata comes from `CGWindowListCopyWindowInfo(.optionAll)`
  (`CGWindowListCreateDescriptionFromArray` returns nothing on macOS 26),
  filtered to layer-0 windows at least 50×50.
- A `CGEventTap` swallows Cmd-Tab before the system switcher sees it and
  owns the keyboard while the panel is up.
- Switching raises the target via AX (`AXRaise` + app activation), which
  makes macOS jump to its space.

## Installing at login

```sh
./install.sh   # builds release, installs ~/.local/bin/spacetab, loads LaunchAgent
```

Re-run after code changes. The binary is unsigned, so macOS may require
re-granting Accessibility after a rebuild. Logs: ~/Library/Logs/spacetab.log.
To uninstall: `launchctl bootout gui/$UID/com.drmaciver.spacetab` and delete
~/Library/LaunchAgents/com.drmaciver.spacetab.plist.

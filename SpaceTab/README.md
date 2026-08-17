# SpaceTab

A Cmd-Tab replacement: vertical window lists, one column per space.

- **Cmd-Tab** opens the switcher (and steps to the next window); hold Cmd.
- **Tab / Down / Up** move within the current column (wrapping).
- **Left / Right** move between spaces.
- **W** closes the selected window (hops to its space and back if needed).
- **Release Cmd** (or Return) to switch to the selected window.
- **Escape** cancels.

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

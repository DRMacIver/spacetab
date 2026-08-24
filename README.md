# SpaceTab

A keyboard-driven window switcher and app launcher for macOS, built around
Spaces (virtual desktops). It replaces two system behaviours:

- **Cmd-Tab**: instead of the flat application strip, you get one column per
  space, each listing that space's windows vertically, most recently used
  first. Navigate windows with Tab/arrows, hop between spaces with Left/Right.
- **Cmd-Space**: instead of Spotlight, a launcher that only does one thing —
  open applications and windows. Type to match apps by name and open windows
  by title; Enter opens a new window of the top-matching app on the *current*
  space, or switches to the matched window.

## Switcher (Cmd-Tab)

- **Cmd-Tab** opens the switcher preselecting your previous window; a quick
  tap toggles between your two most recent windows without showing any UI.
- **Tab / Down / Up** move within the current space's column (wrapping);
  **Shift-Tab** moves backwards.
- **Left / Right** move between spaces.
- **W** closes the selected window (windows blocked by an "unsaved changes"
  style sheet are marked with a warning badge).
- **Release Cmd** (or Return) switches to the selected window, changing
  space if needed. **Escape** cancels.

## Launcher (Cmd-Space)

- Matches applications (running, and installed in /Applications,
  ~/Applications, and the system application folders) and open windows.
  Ranking is by match quality (prefix > word prefix > substring > fuzzy),
  then recency of use; open windows and running apps rank above apps that
  aren't running.
- **Enter** on an app opens a new window on the current space. Apps that
  can't do that (Steam, Spotify, ...) are detected, remembered, and get
  switch-to-their-existing-window behaviour instead. Apps that aren't
  running are launched.
- **Enter** on a window switches to it, changing space if needed.
- **Up/Down/Tab** navigate; **Escape** or **Cmd-Space** dismisses.

## Install

Requires macOS 13+ and a Swift toolchain (Command Line Tools are enough).

```sh
./install.sh
```

This builds a release binary, installs it to `~/.local/bin/spacetab`, and
loads a login LaunchAgent so it starts automatically. Then grant
**Accessibility** permission to `~/.local/bin/spacetab` in System Settings >
Privacy & Security > Accessibility (the app waits for the grant and starts
working as soon as it appears — no relaunch needed).

Optional: **Screen Recording** permission gives the switcher and launcher
always-fresh window titles on every space. Without it, titles come from the
Accessibility API plus a cache, which only goes stale for windows renamed
while on another space.

### Code signing (recommended)

macOS ties permission grants to the binary's code signature. Unsigned
(ad-hoc) builds get a new identity every rebuild, which silently invalidates
the Accessibility grant. Create a self-signed certificate once and
`install.sh` will use it automatically if it's named `SpaceTab Dev`:

```sh
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 \
  -nodes -subj "/CN=SpaceTab Dev" \
  -addext "extendedKeyUsage=codeSigning" -addext "keyUsage=digitalSignature" \
  -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -legacy -out st.p12 -inkey key.pem -in cert.pem -passout pass:spacetab
security import st.p12 -k ~/Library/Keychains/login.keychain-db -P spacetab -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
rm key.pem cert.pem st.p12
```

If a rebuild ever invalidates the grant anyway: remove the entry in the
Accessibility list, re-add the binary, and
`launchctl kickstart -k gui/$UID/com.drmaciver.spacetab`.

### Uninstall

```sh
launchctl bootout gui/$UID/com.drmaciver.spacetab
rm ~/Library/LaunchAgents/com.drmaciver.spacetab.plist ~/.local/bin/spacetab
```

## Development

```sh
swift run SpaceTab          # run in the foreground; Ctrl-C to stop
swift run SpaceTab --list   # debug: dump spaces and windows
swift run ModelTests        # navigation/ranking model tests
```

Logs from the LaunchAgent go to `~/Library/Logs/spacetab.log`.

## How it works (and caveats)

- Spaces and per-space window lists come from private SkyLight framework
  calls (`SLSCopyManagedDisplaySpaces`, `SLSCopyWindowsWithOptionsAndTags`,
  `SLSManagedDisplaySetCurrentSpace`) — the same ones tools like yabai and
  AltTab rely on. **Private APIs can break in macOS updates.**
- A `CGEventTap` swallows Cmd-Tab and Cmd-Space before the system sees them,
  and owns the keyboard while a panel is up. If macOS shows Spotlight
  anyway, disable its shortcut in System Settings > Keyboard Shortcuts.
- Focusing a window on another space uses the SkyLight process-serial-number
  event trick plus an explicit space switch, because the Accessibility API
  cannot see windows on non-current spaces.
- "New window on the current space" posts Cmd-N directly to the app's
  process *without* activating it first (activation would let macOS drag you
  to the app's space). Apps that ignore Cmd-N are remembered in
  `defaults read com.drmaciver.spacetab appsWithoutNewWindowSupport`; delete
  that key to make SpaceTab re-probe them.
- Most-recently-used ordering is tracked live via per-app Accessibility
  observers, so it starts coarse on launch and sharpens as you use windows.
- Single-display use is what's tested; multi-display setups will mostly
  work but layout and space handling there have had little attention.

## License

MIT — see [LICENSE](LICENSE).

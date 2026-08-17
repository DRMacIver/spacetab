#!/bin/zsh
# Build SpaceTab and install it as a login LaunchAgent.
set -euo pipefail

cd "$(dirname "$0")"
swift build -c release

BIN_DIR="$HOME/.local/bin"
PLIST="$HOME/Library/LaunchAgents/com.drmaciver.spacetab.plist"
LABEL="com.drmaciver.spacetab"
LOG="$HOME/Library/Logs/spacetab.log"

mkdir -p "$BIN_DIR"

# Stop a running instance before overwriting the binary.
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true

cp .build/release/SpaceTab "$BIN_DIR/spacetab"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$BIN_DIR/spacetab</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$LOG</string>
    <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$UID" "$PLIST"
echo "Installed. Logs: $LOG"
echo "If Cmd-Tab does not respond, grant Accessibility to $BIN_DIR/spacetab in"
echo "System Settings > Privacy & Security > Accessibility, then run:"
echo "  launchctl kickstart -k gui/$UID/$LABEL"

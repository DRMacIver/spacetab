#!/bin/zsh
exec /usr/bin/log stream --style ndjson --predicate '(process == "Dock" OR process == "WindowServer") AND (composedMessage CONTAINS[c] "space" OR composedMessage CONTAINS[c] "workspace")' >> /Users/drmaciver/Projects/windows-debugging/system_space.log 2>&1

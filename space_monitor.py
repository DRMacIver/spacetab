"""Monitor macOS space (virtual desktop) switches and app activity.

Logs every active-space change together with the frontmost app, recent app
activations/launches, and the space ID (via the private SkyLight API), so we
can identify which space is "sticky" and what app activity coincides with
being yanked back to it.

Output: newline-delimited JSON in space_monitor.log
"""

import ctypes
import ctypes.util
import datetime
import json
import os
import sys

from AppKit import NSWorkspace
from Foundation import NSObject, NSRunLoop, NSDate
import objc

LOG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "space_monitor.log")

# Private SkyLight API for current space id
_skylight = ctypes.CDLL(
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
)
_skylight.SLSMainConnectionID.restype = ctypes.c_int
_skylight.SLSGetActiveSpace.restype = ctypes.c_uint64
_skylight.SLSGetActiveSpace.argtypes = [ctypes.c_int]
_conn = _skylight.SLSMainConnectionID()


def active_space_id():
    try:
        return _skylight.SLSGetActiveSpace(_conn)
    except Exception:
        return None


def frontmost_app():
    app = NSWorkspace.sharedWorkspace().frontmostApplication()
    if app is None:
        return None
    return {"name": str(app.localizedName()), "pid": int(app.processIdentifier()),
            "bundle": str(app.bundleIdentifier() or "")}


def log_event(event, **extra):
    record = {
        "ts": datetime.datetime.now().isoformat(timespec="milliseconds"),
        "event": event,
        "space": active_space_id(),
        "frontmost": frontmost_app(),
    }
    record.update(extra)
    line = json.dumps(record)
    with open(LOG_PATH, "a") as f:
        f.write(line + "\n")
    print(line, flush=True)


def app_info_from_note(note):
    app = note.userInfo().get("NSWorkspaceApplicationKey")
    if app is None:
        return None
    return {"name": str(app.localizedName()), "pid": int(app.processIdentifier()),
            "bundle": str(app.bundleIdentifier() or "")}


class Observer(NSObject):
    def spaceChanged_(self, note):
        log_event("space_changed")

    def appActivated_(self, note):
        log_event("app_activated", app=app_info_from_note(note))

    def appDeactivated_(self, note):
        log_event("app_deactivated", app=app_info_from_note(note))

    def appLaunched_(self, note):
        log_event("app_launched", app=app_info_from_note(note))

    def appHidden_(self, note):
        log_event("app_hidden", app=app_info_from_note(note))

    def appUnhidden_(self, note):
        log_event("app_unhidden", app=app_info_from_note(note))


def main():
    observer = Observer.alloc().init()
    nc = NSWorkspace.sharedWorkspace().notificationCenter()
    for selector, name in [
        ("spaceChanged:", "NSWorkspaceActiveSpaceDidChangeNotification"),
        ("appActivated:", "NSWorkspaceDidActivateApplicationNotification"),
        ("appDeactivated:", "NSWorkspaceDidDeactivateApplicationNotification"),
        ("appLaunched:", "NSWorkspaceDidLaunchApplicationNotification"),
        ("appHidden:", "NSWorkspaceDidHideApplicationNotification"),
        ("appUnhidden:", "NSWorkspaceDidUnhideApplicationNotification"),
    ]:
        nc.addObserver_selector_name_object_(observer, selector, name, None)

    log_event("monitor_started", pid=os.getpid())
    runloop = NSRunLoop.currentRunLoop()
    # NSWorkspaceActiveSpaceDidChangeNotification is not delivered to
    # processes without a window-server connection, so poll as well.
    last_space = active_space_id()
    while True:
        runloop.runMode_beforeDate_(
            "kCFRunLoopDefaultMode", NSDate.dateWithTimeIntervalSinceNow_(0.3)
        )
        space = active_space_id()
        if space != last_space:
            log_event("space_changed", previous=last_space)
            last_space = space


if __name__ == "__main__":
    main()

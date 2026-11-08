#!/bin/bash
# Prints the UDID of the iPhone simulator CI runs on: a Pro (not Max) on the newest iOS,
# or any iPhone if there's none. Used by build.yml and screenshots.yml.
set -euo pipefail
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
ios = sorted((k for k in devices if "iOS" in k), key=lambda k: [int(x) for x in k.split("iOS-")[1].split("-")])
for runtime in reversed(ios):
    for d in devices[runtime]:
        if d["name"].startswith("iPhone") and "Pro" in d["name"] and "Max" not in d["name"]:
            print(d["udid"]); sys.exit()
for runtime in reversed(ios):
    for d in devices[runtime]:
        if d["name"].startswith("iPhone"):
            print(d["udid"]); sys.exit()
')
xcrun simctl list devices | grep "$udid" >&2
echo "$udid"

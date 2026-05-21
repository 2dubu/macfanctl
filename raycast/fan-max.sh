#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Set fans max
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 🌀
# @raycast.packageName Fan

# Documentation:
# @raycast.author Geonwoo Lee
# @raycast.authorURL https://github.com/2dubu

exec sudo "$(command -v macfanctl)" max

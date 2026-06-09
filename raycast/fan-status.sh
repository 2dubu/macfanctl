#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Fans status
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 📊
# @raycast.packageName Fan

# Documentation:
# @raycast.author Geonwoo Lee
# @raycast.authorURL https://github.com/2dubu

"$(command -v macfanctl)" list

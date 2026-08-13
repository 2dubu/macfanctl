import Foundation

struct RaycastScript {
    let filename: String
    let contents: String
}

enum RaycastScripts {
    static let all: [RaycastScript] = [
        RaycastScript(
            filename: "fan-status.sh",
            contents: """
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

            "$(command -v macfanctl)" list\n
            """
        ),
        RaycastScript(
            filename: "fan-rpm.sh",
            contents: """
            #!/bin/bash

            # Required parameters:
            # @raycast.schemaVersion 1
            # @raycast.title Set fans rpm
            # @raycast.mode compact
            # @raycast.argument1 { "type": "text", "placeholder": "RPM" }

            # Optional parameters:
            # @raycast.icon 💨
            # @raycast.packageName Fan

            # Documentation:
            # @raycast.author Geonwoo Lee
            # @raycast.authorURL https://github.com/2dubu

            exec sudo "$(command -v macfanctl)" set "$1"\n
            """
        ),
        RaycastScript(
            filename: "fan-max.sh",
            contents: """
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

            exec sudo "$(command -v macfanctl)" max\n
            """
        ),
        RaycastScript(
            filename: "fan-auto.sh",
            contents: """
            #!/bin/bash

            # Required parameters:
            # @raycast.schemaVersion 1
            # @raycast.title Set fans auto
            # @raycast.mode compact

            # Optional parameters:
            # @raycast.icon 🤖
            # @raycast.packageName Fan

            # Documentation:
            # @raycast.author Geonwoo Lee
            # @raycast.authorURL https://github.com/2dubu

            exec sudo "$(command -v macfanctl)" auto\n
            """
        ),
    ]
}

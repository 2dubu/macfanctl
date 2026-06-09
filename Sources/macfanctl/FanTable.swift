import Foundation
import SMCKit

/// Renders the fan state as a fixed-width text table shared by `list` and `watch`,
/// so both commands present identical output. Returns a diagnostic line when no
/// fans are detected rather than an empty table.
func renderFanTable(_ fans: [FanInfo]) -> String {
    guard !fans.isEmpty else {
        return "No fans detected (FNum returned 0)."
    }

    var lines = [
        "Fan   Actual   Min    Max    Target",
        "---   ------   ----   ----   ------",
    ]
    for fan in fans {
        lines.append(String(
            format: "%-5d %-8d %-6d %-6d %-6d",
            fan.index, fan.actualRPM, fan.minRPM, fan.maxRPM, fan.targetRPM
        ))
    }
    return lines.joined(separator: "\n")
}

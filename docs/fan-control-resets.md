# Diagnosing fan settings that reset

`macfanctl set` and `max` write a manual mode and target, then exit. A successful command confirms the writes completed; it does not establish exclusive ownership of the fans. A later write by another controller, or a system transition, can change that state.

## Confirmed Macs Fan Control conflict

On a MacBook Pro with an M4 Pro, macOS 26.5.1, macfanctl 0.3.0, and Macs Fan Control 1.5.20, starting Macs Fan Control while both fans were manually set to 4000 RPM restored Auto.

The app's own diagnostic log recorded this sequence on 2026-09-09, in local time:

| Time | Event |
| --- | --- |
| 10:48:49.519 | Startup detected both fans' modes as set by another program and applied a profile. |
| 10:48:49.520 | Successful writes of `00` to both `F0Md` and `F1Md`. |
| 10:48:49.521 | Successful write of `00` to `Ftst`. |
| 10:48:50.055 | Independent SMC sampling first observed both modes change from `1` to `0`, with targets still at 4000. |
| 10:48:51.075 | Targets changed to the system's 1350 and 1458 RPM. |

This identifies the writer for the startup experiment. The falling RPM followed a mode reset; it was not evidence that the fan motor stopped or that Raycast terminated a persistent controller.

`set` and `max` now refuse while the Macs Fan Control application is running. Detection uses native process enumeration, the bundle identifier, and its main executable, so it does not depend on an app's display name or the invoking user's GUI session. The separately running privileged helper is excluded. If process inspection fails, manual commands fail before opening the SMC. `auto` is not guarded, so releasing manual control remains available.

Quit Macs Fan Control normally before setting a manual RPM. Keep it closed while using macfanctl; the preflight cannot prevent an app from starting afterward. This does not claim detection of every other fan utility.

## What the investigation did not establish

- Exiting the one-shot CLI did **not** immediately reset the fans in these tests. Manual 4000 RPM persisted for several minutes, including an interval with no diagnostic SMC reads.
- An earlier reset occurred about six seconds after changing AC energy mode from High Power to Automatic. Repeating the transition in both directions with Macs Fan Control closed preserved manual mode. A further repeat with the app open also preserved it, and its diagnostic log recorded no new fan writes. Energy-mode changes alone are therefore not a confirmed cause.
- The original intermittent resets happened before a writer-specific diagnostic log was available. The confirmed startup conflict does not identify every earlier reset. Sleep/wake behavior was not reproduced in this investigation.

No persistent daemon or periodic RPM rewriting is added. Such a process would not establish the cause and could compete with the other controller.

## Capture the next transition

1. Close other fan-control apps and run `macfanctl list --debug` to record supported keys.
2. Run `macfanctl watch --json > fan-state.jsonl` in a terminal.
3. Use the normal `set` command or Raycast action. Record the time of any power connection, energy-mode change, sleep/wake, or fan-app launch/quit.
4. Stop the recording with Ctrl+C after the event. Use `sudo macfanctl auto` when manual control is no longer needed.

The JSON stream records timestamps, fan speeds, mode keys, `Ftst`, and read failures. It contains one object per line without terminal escape sequences. Unavailable values must be interpreted through the recorded errors, not as zero RPM. Sampling is read-only and does not keep a target active or attribute a write to a process.

Check the raw mode as well as the RPM: in the reproduced reset, the mode changed first and the old target persisted until the next sample. RPM alone cannot distinguish a setting reset from a read failure or normal spin-down.

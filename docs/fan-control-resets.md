# Diagnosing fan settings that reset

`macfanctl set` and `max` write a manual mode and target, then exit. A successful command confirms the writes completed; it does not establish exclusive ownership of the fans. A later write by another controller, or a system transition, can change that state.

## Manual unlock omitted after an accepted mode write

Version 0.3.0 enabled `Ftst` only after a manual-mode write failed with `0x82`. A directly accepted mode write therefore left the unlock at zero. On 2026-09-10, with Macs Fan Control removed, `max` entered manual mode at 13:03:44 with `Ftst=0`. Changing AC energy mode from High Power to Automatic at 13:06:06 was followed at 13:06:43 by both modes changing to 3 and both targets changing to 0. Actual RPM fell afterward. The CLI had already exited, and no further manual target writes were issued during observation.

Reapplying `max` from that state took the existing `0x82` fallback and enabled `Ftst=1`. Both fans then held their 5777 RPM targets for over five minutes through Automatic, High Power, Low Power, and High Power transitions, without repeated target writes. This supports enabling the unlock before entering manual mode; it does not identify the writer in every earlier unrecorded reset.

Manual commands now establish a supported, validated `Ftst` flag first. Only a missing-key result skips this step. Existing unlocks are not rewritten, failures are reported, and a failed transaction restores a newly entered manual mode without replacing an existing manual session.

The same investigation reproduced a separate global-state bug: with both fans manual, `auto --fan 0` in 0.3.0 cleared `Ftst`, and the untouched fan 1 also lost its manual target about three seconds later. Auto now waits for the selected fan to leave manual mode and checks all fan modes before clearing the shared flag. It preserves another manual fan and refuses to treat failed reads as automatic state.

The installed `0.3.1-dev` build was then tested on the same M4 Pro with the same short-lived SMC reads. One Max command held both targets at 5777 RPM for six minutes through High Power → Automatic → Low Power → High Power. `auto --fan 0` preserved fan 1 at Max and `Ftst=1` for 30 seconds. Setting fan 0 to 4000 also preserved fan 1. Finally, full Auto exited successfully and settled with both fans out of manual mode and `Ftst=0`. No further manual target writes were used to maintain any observation phase.

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
- The 2026-09-09 energy-mode trials had inconsistent results. The later experiment above records the missing-unlock state and compares it with an enabled unlock; an energy-mode change alone is not a complete explanation for every reset.
- The original intermittent resets happened before a writer-specific diagnostic log was available. The confirmed startup conflict does not identify every earlier reset. Sleep/wake behavior was not reproduced in this investigation.

No persistent daemon or periodic RPM rewriting is added. Such a process would not establish the cause and could compete with the other controller.

## Capture the next transition

1. Close other fan-control apps and run `macfanctl list --debug` to record supported keys.
2. Run `macfanctl watch --json > fan-state.jsonl` in a terminal.
3. Use the normal `set` command or Raycast action. Record the time of any power connection, energy-mode change, sleep/wake, or fan-app launch/quit.
4. Stop the recording with Ctrl+C after the event. Use `sudo macfanctl auto` when manual control is no longer needed.

The JSON stream records timestamps, fan speeds, mode keys, `Ftst`, and read failures. It contains one object per line without terminal escape sequences. Unavailable values must be interpreted through the recorded errors, not as zero RPM. Sampling is read-only and does not keep a target active or attribute a write to a process.

Check the raw mode as well as the RPM: in the reproduced reset, the mode changed first and the old target persisted until the next sample. RPM alone cannot distinguish a setting reset from a read failure or normal spin-down.

# macfanctl

[![CI](https://github.com/2dubu/macfanctl/actions/workflows/ci.yml/badge.svg)](https://github.com/2dubu/macfanctl/actions/workflows/ci.yml)

A macOS CLI for reading and controlling fan speeds via SMC.

## Status

Read and write operations have been verified on MacBook Pro M5 Max / macOS 26.4. The manual-unlock lifecycle has also been tested on M4 Pro / macOS 26.5.1; see the [reset investigation](docs/fan-control-resets.md). Other hardware remains unverified by this project.

## Requirements

- Build targets macOS 13+. Tested on macOS 26.4 and 26.5.1.
- MacBook Pro M5 Max and M4 Pro verified. Other Macs may work but are unverified.

## Install

Two steps: install the binary, then run `setup` to register a NOPASSWD sudoers rule so write commands run without a password prompt from your shell or any launcher.

### Homebrew (Recommended)

```bash
# Install macfanctl and allow launcher write commands
brew install 2dubu/tap/macfanctl
sudo macfanctl setup

# Optional: install Raycast Script Commands in ~/raycast-script
macfanctl raycast setup
```

### From source

```bash
git clone git@github.com:2dubu/macfanctl.git
cd macfanctl
make install     # builds release universal binary, ad-hoc signs, installs to /usr/local/bin
make setup       # same as `sudo macfanctl setup`
make raycast_setup
```

### Uninstall

```bash
sudo macfanctl setup --uninstall && brew uninstall macfanctl
```

If installed from source instead of brew, replace `brew uninstall macfanctl` with `sudo rm /usr/local/bin/macfanctl`.

## Usage

```bash
macfanctl list                       # show all fans (actual / min / max / target RPM)
macfanctl list --json                # machine-readable
macfanctl list --debug               # dump raw SMC fan key bytes (for diagnostics on new hardware)
macfanctl watch                      # live-refresh the fan table in place (like top); Ctrl+C to quit
macfanctl watch --interval 0.5       # refresh every 0.5s (default 1s)
macfanctl watch --json > fan-state.jsonl # timestamped, read-only diagnostic recording

sudo macfanctl set 3500              # set all fans to 3500 RPM
sudo macfanctl set 3500 --fan 0      # set fan 0 only
sudo macfanctl max                   # set all fans to their hardware maximum (per F%dMx)
sudo macfanctl max --fan 0           # set fan 0 only to max
sudo macfanctl auto                  # release all fans to system control
sudo macfanctl auto --fan 0          # release fan 0 only
```

`set` rejects RPM values above the fan's hardware max with a clear error rather than silently clamping. Use `max` if you want to push to the ceiling.

Quit **Macs Fan Control** before using `set` or `max`. These commands check for its running application and refuse before accessing the SMC, because the app can overwrite manual settings when it applies a profile. The background `smcwrite` helper alone does not block commands. `auto` remains available even when the app is running or the conflict check fails.

This check is a snapshot: starting Macs Fan Control after setting an RPM can still reset it. `set` and `max` apply once and exit; they do not reserve control or keep reapplying a target. See [diagnosing settings that reset](docs/fan-control-resets.md) for the reproduced conflict and how to record a transition.

On hardware that exposes the `Ftst` unlock, manual commands enable it before entering manual mode, even when a direct mode write would succeed. `auto --fan N` preserves that shared unlock while another fan is still manual. A full `auto` waits for the mode changes to become visible before releasing it, and reports any incomplete cleanup.

Without `macfanctl setup`, every write command will prompt for password. With it, the binary is allowed to run as root without prompting (scoped to `/usr/local/bin/macfanctl` only).

## Raycast scripts

Optional [Raycast](https://www.raycast.com/) Script Commands for one-keystroke fan control. Run `macfanctl raycast setup` (or `make raycast_setup` from a source checkout) to install them in `~/raycast-script`:

- `fan-auto.sh` — release all fans to system control (`macfanctl auto`)
- `fan-max.sh` — push all fans to hardware maximum (`macfanctl max`)
- `fan-rpm.sh` — set all fans to a specific RPM (prompts for an RPM argument)
- `fan-status.sh` — show current fan state (RPM, min, max, target) via `macfanctl list`

### Install

1. Run `macfanctl raycast setup` after installing `macfanctl` and completing `macfanctl setup`.
2. In Raycast, open **Settings → Extensions → Script Commands**.
3. Click **+ → Add Script Directory** and select `~/raycast-script`.

To use another directory, pass its full path with `--directory`. For example, `macfanctl raycast setup --directory "$HOME/Documents/raycast-script"` installs the scripts in `~/Documents/raycast-script`.

The scripts call `sudo macfanctl …` and rely on the NOPASSWD sudoers rule installed by `macfanctl setup` — without that step, Raycast has no way to provide a password and the write commands (`fan-max`, `fan-rpm`) will fail silently. `fan-auto` does not require root on every system but is invoked the same way for consistency.

Each script uses `command -v macfanctl` to locate the binary, so it works whether `macfanctl` was installed via Homebrew or built from source, as long as it's on `PATH`.

## How it works

`macfanctl` talks to the `AppleSMC` IOKit service. The non-obvious part on Apple Silicon:

1. Writes to the fan target key (`F%dTg`) succeed at the SMC interface (no error returned) but the written value does not stick — the system reasserts its own target almost immediately.
2. The fix, per [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan) research, is to first write `1` to the fan mode key, which switches that fan from system-managed mode to manual mode. After that, `F%dTg` writes stick.
3. The mode key casing varies by hardware: M5 uses `F%dmd` (lowercase, verified here). The research describes `F%dMd` (uppercase) for earlier generations. `macfanctl` probes both casings on the first write and caches the result.
4. A successful manual-mode write can leave `Ftst=0`. On the tested M4 Pro this allowed a later return to mode 3 and target 0. When `Ftst` exists, `macfanctl` now enables it before either mode or target writes. Missing-key responses preserve the direct path; other read or write errors are reported.

References:
- [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan) — Apple Silicon unlock mechanism research
- [ProducerGuy/ThermalForge](https://github.com/ProducerGuy/ThermalForge) — another open-source Apple Silicon fan control tool

## Architecture

- `SMCKit` — Swift library wrapping `AppleSMC` IOKit service. Handles `SMCParamStruct` layout, key encoding (4-char FourCC), and value codecs (`fpe2`, `flt`, `sp78`, `ui8`, etc.).
- `macfanctl` — `swift-argument-parser` based CLI on top of `SMCKit`.

Write operations require root. The current MVP relies on a NOPASSWD sudoers rule. A privileged helper daemon for persistence is on the roadmap.

## Limitations

- **Sleep/wake behavior not tested here.** The agoodkind research notes that firmware resets the manual-mode unlock on sleep transitions; this project hasn't verified the behavior on M5 Max.
- **Manual unlock is hardware-dependent.** `Ftst` is probed and enabled when supported. If firmware still returns `0x82` during the transition, the manual-mode write is retried for at most 10 seconds. Another controller or a firmware reset can still revoke control; sleep/wake persistence is not guaranteed.
- **`F%dMn` is read-only on M5.** SMC returns `0x86` (key-not-writable) when attempting to write the minimum RPM. Informational — `macfanctl` doesn't touch `Mn`; switching to manual mode is what makes the target stick.

## Reporting issues

If `macfanctl` doesn't work as expected on your Mac, please open a [Hardware report](https://github.com/2dubu/macfanctl/issues/new/choose). The output of `macfanctl list --debug` is the most useful single piece of data to include — it shows which SMC keys your hardware exposes.

For intermittent resets, run `macfanctl watch --json > fan-state.jsonl` before the event and stop it with Ctrl+C afterward. Include the affected timestamps and nearby power, sleep/wake, or fan-app actions. The recording reads state only and cannot identify which process wrote an SMC key by itself.

## License

MIT

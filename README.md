# macfanctl

A macOS CLI for reading and controlling fan speeds via SMC.

## Status

v0.1 — read + write both implemented and verified on MacBook Pro M5 Max / macOS 26.4. Other Apple Silicon generations are handled in code via the mode-key auto-probe but have not been hardware-tested by this project.

## Requirements

- Build targets macOS 13+. Tested on macOS 26.4.
- MacBook Pro M5 Max verified. Other Macs may work but are unverified.

## Install

From source:

```bash
git clone git@github.com:2dubu/macfanctl.git
cd macfanctl
make install     # builds release universal binary, ad-hoc signs, installs to /usr/local/bin
make sudoers     # optional: NOPASSWD rule for the binary so launchers can invoke it without a password prompt
```

Homebrew tap (not published yet):

```bash
brew tap 2dubu/tap
brew install macfanctl
```

## Usage

```bash
macfanctl list                       # show all fans (actual / min / max / target RPM)
macfanctl list --json                # machine-readable
macfanctl list --debug               # dump raw SMC fan key bytes (for diagnostics on new hardware)

sudo macfanctl set 3500              # set all fans to 3500 RPM
sudo macfanctl set 3500 --fan 0      # set fan 0 only
sudo macfanctl max                   # set all fans to their hardware maximum (per F%dMx)
sudo macfanctl max --fan 0           # set fan 0 only to max
sudo macfanctl auto                  # release all fans to system control
sudo macfanctl auto --fan 0          # release fan 0 only
```

`set` rejects RPM values above the fan's hardware max with a clear error rather than silently clamping. Use `max` if you want to push to the ceiling.

Without `make sudoers`, every write command will prompt for password. With it, the binary is allowed to run as root without prompting (scoped to `/usr/local/bin/macfanctl` only).

## How it works

`macfanctl` talks to the `AppleSMC` IOKit service. The non-obvious part on Apple Silicon:

1. Writes to the fan target key (`F%dTg`) succeed at the SMC interface (no error returned) but the written value does not stick — the system reasserts its own target almost immediately.
2. The fix, per [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan) research, is to first write `1` to the fan mode key, which switches that fan from system-managed mode to manual mode. After that, `F%dTg` writes stick.
3. The mode key casing varies by hardware: M5 uses `F%dmd` (lowercase, verified here). The research describes `F%dMd` (uppercase) for earlier generations. `macfanctl` probes both casings on the first write and caches the result.

References:
- [agoodkind/macos-smc-fan](https://github.com/agoodkind/macos-smc-fan) — Apple Silicon unlock mechanism research
- [ProducerGuy/ThermalForge](https://github.com/ProducerGuy/ThermalForge) — another open-source Apple Silicon fan control tool

## Architecture

- `SMCKit` — Swift library wrapping `AppleSMC` IOKit service. Handles `SMCParamStruct` layout, key encoding (4-char FourCC), and value codecs (`fpe2`, `flt`, `sp78`, `ui8`, etc.).
- `macfanctl` — `swift-argument-parser` based CLI on top of `SMCKit`.

Write operations require root. The current MVP relies on a NOPASSWD sudoers rule. A privileged helper daemon for persistence is on the roadmap.

## Limitations

- **Sleep/wake behavior not tested here.** The agoodkind research notes that firmware resets the manual-mode unlock on sleep transitions; this project hasn't verified the behavior on M5 Max.
- **No Ftst diagnostic path.** Per the research, some Apple Silicon generations require an `Ftst=1` unlock dance before mode writes succeed. `macfanctl` currently only does the direct mode-write path (verified on M5).
- **`F%dMn` is read-only on M5.** SMC returns `0x86` (key-not-writable) when attempting to write the minimum RPM. Informational — `macfanctl` doesn't touch `Mn`; switching to manual mode is what makes the target stick.

## License

MIT

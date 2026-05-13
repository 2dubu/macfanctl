# macfanctl

A macOS CLI for reading and controlling fan speeds via SMC.

> Status: pre-alpha (v0.1). Read-only operations (`list`) implemented. Write operations (`set`, `auto`, `preset`) not yet implemented.

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac (developed on M5 Max / macOS 26)

## Install

Once the Homebrew tap is published:

```bash
brew tap 2dubu/tap
brew install macfanctl
```

From source:

```bash
git clone git@github.com:2dubu/macfanctl.git
cd macfanctl
make install            # builds, signs ad-hoc, installs to /usr/local/bin
make sudoers            # optional: passwordless invocation for Raycast etc.
```

## Usage

```bash
macfanctl list             # show fans and their current state
macfanctl list --json      # machine-readable output
```

## Architecture

- `SMCKit` — Swift library wrapping `AppleSMC` IOKit service
- `macfanctl` — `swift-argument-parser` based CLI built on top of `SMCKit`

Write operations (planned) will require root. The current plan is a NOPASSWD sudoers rule for the binary; a privileged helper (XPC) is on the roadmap.

## Related projects

This project is unrelated to the following GUI tools (which inspired the architecture):

- [Macs Fan Control](https://crystalidea.com/macs-fan-control) by crystalidea — GUI app, closed source
- [smcFanControl](https://github.com/hholtmann/smcFanControl) by Hendrik Holtmann — GUI app, open source

## License

MIT

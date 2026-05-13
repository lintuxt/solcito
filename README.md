# solcito

[![CI](https://github.com/lintuxt/solcito/actions/workflows/ci.yml/badge.svg)](https://github.com/lintuxt/solcito/actions/workflows/ci.yml)

A macOS-native manager for Logitech wireless receivers (Unifying, Bolt, Lightspeed, Nano) — pair, unpair, and inspect connected devices.

Inspired by [Solaar](https://github.com/pwr-Solaar/Solaar), reimplemented in Swift on top of IOKit HID. No Python runtime, no hidapi, no Homebrew dependency.

> **Status:** very early. Slice 1 (HID transport + receiver discovery) only.

## Requirements

- macOS 14+
- Swift 6.0+ (ships with Xcode 16)

## Build & run

```sh
swift build -c release
./.build/release/solcito help
```

Common commands:

```sh
solcito                  # show your receiver and paired devices
solcito pair             # add a new device
solcito unpair <slot>    # remove a device
```

Diagnostic env vars (for development): `SOLCITO_HID_TRACE=1` dumps raw
HID wire bytes; `SOLCITO_HIDPP_TRACE=1` dumps protocol-level events.
Both go to stderr.

## Project layout

```
Sources/
├── HIDTransport/   IOKit HID wrapper (enumeration, device I/O)
├── HIDPP/          HID++ protocol + receiver identification
└── SolcitoCLI/     command-line front end

Tests/
├── HIDTransportTests/
└── HIDPPTests/
```

The CLI is the current entry point; a GUI shell will come back later once
the protocol layer is rock-solid.

## Support the project

solcito is free and open source. If it's useful to you, consider supporting development:

- 💛 [GitHub Sponsors](https://github.com/sponsors/) <!-- TODO: replace with your sponsors URL -->
- ☕ [Buy Me a Coffee](https://buymeacoffee.com/) <!-- TODO: replace with your link -->

Donations are entirely voluntary and grant no special license terms — the project remains GPL-2.0 for everyone.

## License

GPL-2.0-only. See [`LICENSE`](./LICENSE). Portions of the HID++ protocol implementation are transliterated from [Solaar](https://github.com/pwr-Solaar/Solaar) (GPL-2.0).

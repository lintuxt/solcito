# solcito

[![CI](https://github.com/lintuxt/solcito/actions/workflows/ci.yml/badge.svg)](https://github.com/lintuxt/solcito/actions/workflows/ci.yml)

A macOS-native manager for Logitech wireless receivers (Unifying, Bolt, Lightspeed, Nano) — pair, unpair, and inspect connected devices.

Inspired by [Solaar](https://github.com/pwr-Solaar/Solaar), reimplemented in Swift on top of IOKit HID. No Python runtime, no hidapi, no Homebrew dependency.

## Install

Requires macOS 14+ on Apple Silicon.

```sh
curl -fsSL https://raw.githubusercontent.com/lintuxt/solcito/main/install.sh | sh
```

Then:

```sh
solcito                  # show your receiver and paired devices
solcito pair             # add a new device
solcito unpair <slot>    # remove a device
solcito help             # full help
```

### Uninstall

```sh
rm "$(which solcito)"
```

### Build from source

<details>
<summary>Requires Xcode 16+ (Swift 6).</summary>

```sh
git clone https://github.com/lintuxt/solcito.git
cd solcito
swift build -c release
./.build/release/solcito help
```

</details>

### Diagnostic env vars (development)

`SOLCITO_HID_TRACE=1` dumps raw HID wire bytes; `SOLCITO_HIDPP_TRACE=1`
dumps protocol-level events. Both go to stderr.

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

- 💛 [Sponsor on GitHub](https://github.com/sponsors/lintuxt)

Donations are entirely voluntary and grant no special license terms — the project remains GPL-2.0 for everyone.

## License

GPL-2.0-only. See [`LICENSE`](./LICENSE). Portions of the HID++ protocol implementation are transliterated from [Solaar](https://github.com/pwr-Solaar/Solaar) (GPL-2.0).

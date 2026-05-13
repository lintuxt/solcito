#!/bin/sh
# solcito installer — fetches the latest prebuilt arm64 binary from GitHub
# Releases, verifies its SHA-256 checksum, and drops it on your PATH.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/lintuxt/solcito/main/install.sh | sh
#
# Or manually:
#   curl -fsSL https://raw.githubusercontent.com/lintuxt/solcito/main/install.sh -o install-solcito.sh
#   sh install-solcito.sh
#
# No dependencies beyond standard macOS tooling (curl, tar, shasum, install).

set -eu

REPO="lintuxt/solcito"
BIN_NAME="solcito"

# Pretty output (only when stdout is a TTY).
if [ -t 1 ]; then
  c_cyan="$(printf '\033[36m')"
  c_green="$(printf '\033[32m')"
  c_yellow="$(printf '\033[33m')"
  c_red="$(printf '\033[31m')"
  c_dim="$(printf '\033[2m')"
  c_reset="$(printf '\033[0m')"
else
  c_cyan="" c_green="" c_yellow="" c_red="" c_dim="" c_reset=""
fi

info() { printf '%s▸%s %s\n' "$c_cyan" "$c_reset" "$1"; }
ok()   { printf '%s✓%s %s\n' "$c_green" "$c_reset" "$1"; }
warn() { printf '%s!%s %s\n' "$c_yellow" "$c_reset" "$1" >&2; }
err()  { printf '%s✗%s %s\n' "$c_red" "$c_reset" "$1" >&2; exit 1; }

# --- Platform check --------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || err "solcito requires macOS."
ARCH="$(uname -m)"
[ "$ARCH" = "arm64" ] || err "This release ships an Apple Silicon (arm64) binary only. Detected: $ARCH"

# --- Find latest tag -------------------------------------------------------
info "Fetching latest release tag from github.com/${REPO}…"
TAG="$(
  curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"tag_name"' \
    | head -1 \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/'
)"
[ -n "$TAG" ] || err "Couldn't determine latest release tag (network issue, or no releases yet)."
ok "Latest release: ${c_dim}${TAG}${c_reset}"

PKG="solcito-${TAG}-macos-arm64"
ASSET_URL="https://github.com/${REPO}/releases/download/${TAG}/${PKG}.tar.gz"
SHA_URL="${ASSET_URL}.sha256"

# --- Download + verify -----------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

info "Downloading ${PKG}.tar.gz…"
curl -fsSL -o "${PKG}.tar.gz" "$ASSET_URL"
curl -fsSL -o "${PKG}.tar.gz.sha256" "$SHA_URL"

info "Verifying SHA-256 checksum…"
if shasum -a 256 -c "${PKG}.tar.gz.sha256" >/dev/null 2>&1; then
  ok "Checksum verified."
else
  err "Checksum verification failed. Bailing out without installing anything."
fi

info "Extracting…"
tar -xzf "${PKG}.tar.gz"

# --- Pick install destination ---------------------------------------------
LOCAL_BIN="$HOME/.local/bin"
SYS_BIN="/usr/local/bin"

case ":$PATH:" in
  *":${LOCAL_BIN}:"*) HAS_LOCAL_BIN_IN_PATH=1 ;;
  *)                  HAS_LOCAL_BIN_IN_PATH=0 ;;
esac

NEED_SUDO=""
if [ "$HAS_LOCAL_BIN_IN_PATH" = "1" ] && { [ -d "$LOCAL_BIN" ] || mkdir -p "$LOCAL_BIN" 2>/dev/null; }; then
  DEST="$LOCAL_BIN"
elif [ -w "$SYS_BIN" ]; then
  DEST="$SYS_BIN"
else
  DEST="$SYS_BIN"
  NEED_SUDO="sudo"
  warn "Installing to ${DEST} (will prompt for sudo)."
fi

info "Installing → ${DEST}/${BIN_NAME}"
$NEED_SUDO install -m 0755 "${PKG}/${BIN_NAME}" "${DEST}/${BIN_NAME}"
# Strip the quarantine xattr defensively. macOS doesn't normally apply it
# to curl-downloaded files, but this is a no-op when absent and harmless
# when present.
$NEED_SUDO xattr -d com.apple.quarantine "${DEST}/${BIN_NAME}" 2>/dev/null || true

ok "solcito ${TAG} installed."

# Friendly hint if ~/.local/bin was chosen but not yet on PATH.
if [ "$DEST" = "$LOCAL_BIN" ] && [ "$HAS_LOCAL_BIN_IN_PATH" = "0" ]; then
  warn "${LOCAL_BIN} is not on your PATH yet. Add this to your shell rc:"
  printf '    export PATH="%s:$PATH"\n' "$LOCAL_BIN"
fi

echo
printf '%sTry it:%s\n' "$c_dim" "$c_reset"
echo "  solcito"
echo "  solcito pair"
echo "  solcito help"

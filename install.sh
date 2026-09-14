#!/bin/sh
# Install the gmx CLI from its GitHub releases; no package manager needed.
#
#   curl -fsSL https://raw.githubusercontent.com/opera-gaming/gmx-releases/latest/install.sh | sh
#
#   GMX_VERSION      a release to install instead of the latest (e.g. 0.4.2)
#   GMX_INSTALL_DIR  where to put the binary (default ~/.local/bin)
#
# Re-running it updates to the newest release. Published to gmx-releases and
# the tap repo by the release workflow; the source of truth is
# tools/release/install.sh in gmx.
set -eu
REPO=opera-gaming/homebrew-gmx
# Mirror of the newest release, reachable where api.github.com and release
# assets are blocked (sandbox egress proxies allow raw.githubusercontent.com).
LATEST_RAW=https://raw.githubusercontent.com/opera-gaming/gmx-releases/latest

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ASSET=x86_64-linux ;;
  Darwin-arm64) ASSET=arm64-macos ;;
  Darwin-x86_64) ASSET=x86_64-macos ;;
  *) echo "no prebuilt gmx for $(uname -s) $(uname -m); see https://github.com/opera-gaming/gmx" >&2; exit 1 ;;
esac

if [ -n "${GMX_VERSION:-}" ]; then
  VERSION=${GMX_VERSION#v}
else
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)
  [ -n "$VERSION" ] || VERSION=$(curl -fsSL "$LATEST_RAW/LATEST" 2>/dev/null | tr -d ' \n')
  [ -n "$VERSION" ] || { echo "could not determine the latest gmx release; set GMX_VERSION=<x.y.z> and re-run" >&2; exit 1; }
fi

PKG="gmx-$VERSION.$ASSET.tar.gz"
URL="https://github.com/$REPO/releases/download/v$VERSION/$PKG"
DIR=${GMX_INSTALL_DIR:-$HOME/.local/bin}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "downloading gmx $VERSION ($ASSET)"
if ! curl -fsSL "$URL" -o "$TMP/$PKG" 2>/dev/null; then
  # The latest branch carries only the newest release, so this rescues
  # blocked release-asset downloads but not older pinned GMX_VERSIONs.
  curl -fsSL "$LATEST_RAW/$PKG" -o "$TMP/$PKG" \
    || { echo "could not download $URL" >&2; exit 1; }
  URL="$LATEST_RAW/$PKG"
fi
if curl -fsSL "$URL.sha256" -o "$TMP/$PKG.sha256" 2>/dev/null; then
  WANT=$(tr -d ' \n' < "$TMP/$PKG.sha256")
  if command -v sha256sum >/dev/null; then GOT=$(sha256sum "$TMP/$PKG" | cut -d' ' -f1)
  else GOT=$(shasum -a 256 "$TMP/$PKG" | cut -d' ' -f1); fi
  [ "$WANT" = "$GOT" ] || { echo "checksum mismatch for $PKG" >&2; exit 1; }
else
  echo "no checksum published for $PKG; skipping verification" >&2
fi

tar -xzf "$TMP/$PKG" -C "$TMP"
mkdir -p "$DIR"
install -m 755 "$TMP/gmx" "$DIR/gmx"
echo "installed $("$DIR/gmx" --version) to $DIR/gmx"
case ":$PATH:" in
  *":$DIR:"*) ;;
  *) echo "add it to PATH:  export PATH=\"$DIR:\$PATH\"" ;;
esac

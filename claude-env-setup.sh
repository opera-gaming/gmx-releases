#!/usr/bin/env bash
# Provisioning for a Claude Code cloud environment running this repo.
#
# The environment's setup script field runs this file; the field itself,
# and the allowed-hosts list, live in the environment config and cannot be
# version-controlled. Allowed hosts this script needs:
#   archive.ubuntu.com, security.ubuntu.com
#
# gmx is private, so the field cannot fetch this path from raw
# .githubusercontent.com. Each release publishes a copy to the public
# gmx-releases repo (see .github/workflows/release.yml), which any
# environment can fetch regardless of the repo it has checked out:
#   curl -fsSL https://raw.githubusercontent.com/opera-gaming/gmx-releases/latest/claude-env-setup.sh | bash
# Nothing here depends on a checkout, so it also runs pasted inline.
#
# The result is snapshotted and reused by later sessions, so everything
# here is a one-off cost per snapshot rebuild.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.local/bin:$PATH"

# gmx CLI (installs to ~/.local/bin).
curl -fsSL https://raw.githubusercontent.com/opera-gaming/gmx-releases/latest/install.sh | sh

# Native runner dependencies. The runner calls into EGL at window creation
# even under --headless, so a machine with no GPU also needs the Mesa
# software rasterizer; Xvfb is only for windowed runs, which gmx starts
# itself. mesa-dri, xvfb and libcurl3t64-gnutls ship in the current base
# image and no-op here; they are listed so a slimmer image still works.
# The agent proxy tunnels HTTPS only; the image's sources use http.
sed -i 's|URIs: http://|URIs: https://|' /etc/apt/sources.list.d/ubuntu.sources

# Restricted to the Ubuntu sources: the image also carries docker and PPA
# lists whose hosts are not allowed, and their failures would fail the run.
apt-get update -o Dir::Etc::sourceparts=- \
  -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/ubuntu.sources
apt-get install -y --no-install-recommends \
  libegl1 \
  libgles2 \
  libopenal1 \
  libpulse0 \
  libcurl3t64-gnutls \
  libgl1-mesa-dri \
  xvfb

# Runtimes into the snapshot, so sessions don't pay the download.
gmx runtime gms2 get --no-update-check
gmx runtime gms2 get --wasm --no-update-check

# `gmx run --wasm` searches /usr/local/bin/chromium; point it at the
# image's preinstalled Chromium.
chrome=$(ls -d /opt/pw-browsers/chromium-[0-9]*/chrome-linux/chrome 2>/dev/null | head -1 || true)
if [ -n "$chrome" ]; then
  ln -sf "$chrome" /usr/local/bin/chromium
else
  echo "no preinstalled Chromium found; 'gmx run --wasm' will need --browser" >&2
fi

# A snapshot whose runner cannot load is worse than a failed build.
for runner in "$HOME"/.cache/gmx-cli/runtimes-gms2/*/linux/x64/runner; do
  if missing=$(ldd "$runner" | grep "not found"); then
    echo "gmx runner is missing shared libraries:" >&2
    echo "$missing" >&2
    exit 1
  fi
done

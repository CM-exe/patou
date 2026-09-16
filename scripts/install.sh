#!/bin/sh
# Installs the patou CLI by downloading a prebuilt binary from the
# project's GitHub Releases. No Rust toolchain required.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/install.sh | sh
#
# Env vars:
#   PATOU_VERSION      release tag to install, e.g. v0.2.0 (default: latest)
#   PATOU_INSTALL_DIR  directory to install the binary into
#                      (default: $HOME/.local/bin)

set -eu

repo="CM-exe/patou"
version="${PATOU_VERSION:-latest}"
install_dir="${PATOU_INSTALL_DIR:-$HOME/.local/bin}"

os=$(uname -s)
arch=$(uname -m)

case "$os" in
  Linux) os_part="unknown-linux-musl" ;;
  Darwin) os_part="apple-darwin" ;;
  *)
    echo "error: unsupported OS '$os' - see https://github.com/$repo for manual install options" >&2
    exit 1
    ;;
esac

case "$arch" in
  x86_64 | amd64) arch_part="x86_64" ;;
  arm64 | aarch64) arch_part="aarch64" ;;
  *)
    echo "error: unsupported architecture '$arch'" >&2
    exit 1
    ;;
esac

target="${arch_part}-${os_part}"
asset="patou-${target}.tar.gz"

if [ "$version" = "latest" ]; then
  url="https://github.com/${repo}/releases/latest/download/${asset}"
else
  url="https://github.com/${repo}/releases/download/${version}/${asset}"
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

echo "Downloading $url"
if ! curl -fsSL "$url" -o "$tmp_dir/$asset"; then
  echo "error: no prebuilt binary for $target - see https://github.com/$repo for other install options" >&2
  exit 1
fi

tar -xzf "$tmp_dir/$asset" -C "$tmp_dir"

mkdir -p "$install_dir"
mv "$tmp_dir/patou" "$install_dir/patou"
chmod +x "$install_dir/patou"

echo "Installed patou to $install_dir/patou"

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    echo "note: $install_dir is not on your PATH. Add it, e.g.:"
    echo "  export PATH=\"$install_dir:\$PATH\""
    ;;
esac

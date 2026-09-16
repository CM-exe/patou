#!/bin/sh
# Uninstalls the patou CLI previously installed with scripts/install.sh.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/CM-exe/patou/main/scripts/uninstall.sh | sh
#
# Env vars:
#   PATOU_INSTALL_DIR  directory patou was installed into
#                      (default: $HOME/.local/bin)

set -eu

install_dir="${PATOU_INSTALL_DIR:-$HOME/.local/bin}"
bin_path="$install_dir/patou"

if [ ! -e "$bin_path" ]; then
  echo "patou not found at $bin_path - nothing to uninstall" >&2
  echo "(installed with cargo instead? run 'cargo uninstall patou')" >&2
  exit 1
fi

rm -f "$bin_path"
echo "Removed $bin_path"

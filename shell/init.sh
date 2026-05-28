# shell/init.sh — defines the `noclickops` shell function for bash/zsh.
#
# Source from your shell rc (`~/.zshrc` or `~/.bashrc`):
#
#   [ -f "$HOME/.noclickops/shell/init.sh" ] && . "$HOME/.noclickops/shell/init.sh"
#
# This is the v1.0.x backward-compatibility mechanism. From v1.1.0 onwards,
# the preferred install path puts $HOME/.noclickops/bin on PATH instead, and
# this function isn't needed. install.sh writes the PATH line for new
# installs; this file remains so existing rc-sourced installs keep working.
#
# From v1.2.1: this function is a THIN WRAPPER that forwards everything to
# bin/noclickops.sh. The script does all the real dispatch — lister mode,
# --help, subcommand exec, friendly error on unknown subcommand. Earlier
# versions duplicated dispatch logic here and drifted out of sync with
# the script (e.g. v1.1.0's --help support didn't reach the function),
# which broke `noclickops --help`. Single source of truth fixes that.

noclickops() {
  local install_dir="${NOCLICKOPS_DIR:-$HOME/.noclickops}"
  if [ ! -d "$install_dir/bin" ]; then
    echo "noclickops: install dir $install_dir not found (set NOCLICKOPS_DIR or re-run install.sh)" >&2
    return 1
  fi
  "$install_dir/bin/noclickops.sh" "$@"
}

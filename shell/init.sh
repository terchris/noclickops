# shell/init.sh — defines the `noclickops` shell function for bash/zsh.
#
# Source from your shell rc (`~/.zshrc` or `~/.bashrc`):
#
#   [ -f "$HOME/.noclickops/shell/init.sh" ] && . "$HOME/.noclickops/shell/init.sh"
#
# After sourcing, `noclickops` and `noclickops <subcommand> [args...]` are typeable
# from anywhere. The function evolves via `git pull` (i.e. `noclickops update`)
# without needing to re-edit your rc file.

noclickops() {
  local install_dir="${NOCLICKOPS_DIR:-$HOME/.noclickops}"
  if [ ! -d "$install_dir/bin" ]; then
    echo "noclickops: install dir $install_dir not found (set NOCLICKOPS_DIR or re-run install.sh)" >&2
    return 1
  fi
  if [ $# -eq 0 ]; then
    "$install_dir/bin/noclickops.sh"
    return $?
  fi
  local cmd="$1"; shift
  local script="$install_dir/bin/$cmd.sh"
  if [ ! -x "$script" ]; then
    echo "noclickops: no such command '$cmd' (try: noclickops)" >&2
    return 1
  fi
  "$script" "$@"
}

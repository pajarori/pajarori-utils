#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$HOME"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# ✅ VSCode User dir differs on macOS
if [[ "$(uname -s)" == "Darwin" ]]; then
  VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
else
  VSCODE_USER_DIR="$XDG_CONFIG_HOME/Code/User"
fi

log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[x]\033[0m $*"; exit 1; }

# ✅ portable sha256
sha_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "no sha256 tool found (need sha256sum or shasum)"
  fi
}

copy_if_diff() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"

  if [[ ! -f "$dst" ]]; then
    cp -f "$src" "$dst"
    log "copied (new): $dst"
    return
  fi

  local s1 s2
  s1="$(sha_file "$src")"
  s2="$(sha_file "$dst")"

  if [[ "$s1" != "$s2" ]]; then
    warn "different file, backup: $dst -> $dst.bak"
    cp -f "$dst" "$dst.bak"
    cp -f "$src" "$dst"
    log "replaced: $dst"
  else
    log "same file (skip): $dst"
  fi
}

symlink_bin() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  ln -sf "$src" "$dst"
  chmod +x "$src"
  log "linked bin: $dst"
}

is_arch() { [[ -f /etc/arch-release ]]; }

install_arch_packages() {
  local f="$REPO_DIR/packages/arch.txt"
  [[ -f "$f" ]] || { warn "no packages/arch.txt (skip)"; return; }
  command -v pacman >/dev/null 2>&1 || { warn "pacman not found (skip)"; return; }
  log "installing pacman packages..."
  sudo pacman -Syu --needed - < "$f"
}

install_pip_packages() {
  local f="$REPO_DIR/packages/pip.txt"
  [[ -f "$f" ]] || { warn "no packages/pip.txt (skip)"; return; }
  log "installing pip packages..."
  pip install -r "$f"
}

install_python_lib() {
  local py_dir="$REPO_DIR/python/pajarori"
  [[ -d "$py_dir" ]] || { warn "python lib not found: $py_dir (skip)"; return; }
  log "installing python lib editable: $py_dir"
  pip install -e "$py_dir"
}

sync_templates() {
  local target_tpl="$XDG_CONFIG_HOME/pajarori/template"
  local repo_tpl="$REPO_DIR/templates"

  mkdir -p "$target_tpl"
  log "template dir ready: $target_tpl"

  [[ -d "$repo_tpl" ]] || { warn "repo templates dir missing (skip)"; return; }

  shopt -s nullglob
  for f in "$repo_tpl"/*; do
    [[ -f "$f" ]] || continue
    copy_if_diff "$f" "$target_tpl/$(basename "$f")"
  done
  shopt -u nullglob
}

sync_vscode_configs() {
  local repo_vs="$REPO_DIR/configs/vscode"
  [[ -d "$repo_vs" ]] || { warn "repo vscode dir missing (skip)"; return; }

  mkdir -p "$VSCODE_USER_DIR"

  # core config files
  for fname in settings.json keybindings.json; do
    if [[ -f "$repo_vs/$fname" ]]; then
      copy_if_diff "$repo_vs/$fname" "$VSCODE_USER_DIR/$fname"
    else
      warn "missing in repo: $repo_vs/$fname"
    fi
  done

  # snippets (.code-snippets)
  if [[ -d "$repo_vs/snippets" ]]; then
    mkdir -p "$VSCODE_USER_DIR/snippets"
    shopt -s nullglob
    for s in "$repo_vs/snippets/"*.code-snippets; do
      [[ -f "$s" ]] || continue
      copy_if_diff "$s" "$VSCODE_USER_DIR/snippets/$(basename "$s")"
    done
    shopt -u nullglob
  fi

  # extensions
  if command -v code >/dev/null 2>&1 && [[ -f "$repo_vs/extensions.txt" ]]; then
    log "installing vscode extensions..."
    while read -r ext; do
      [[ -n "$ext" ]] && code --install-extension "$ext" --force >/dev/null 2>&1 || true
    done < "$repo_vs/extensions.txt"
  fi
}

sync_bin_tools() {
  local repo_bin="$REPO_DIR/bin"
  [[ -d "$repo_bin" ]] || { warn "bin dir missing (skip)"; return; }

  mkdir -p "$HOME_DIR/.local/bin"

  shopt -s nullglob
  for f in "$repo_bin"/*; do
    [[ -f "$f" ]] || continue
    symlink_bin "$f" "$HOME_DIR/.local/bin/$(basename "$f")"
  done
  shopt -u nullglob

  log "ensure ~/.local/bin in PATH (add to shell if needed)"
}

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Options:
  --all           do everything (default)
  --packages      install system + pip packages
  --templates     sync ~/.config/pajarori/template
  --vscode        sync vscode settings/snippets/extensions
  --python        install python/pajarori editable
  --bin           link repo bin/ -> ~/.local/bin
  -h, --help      show help
EOF
}

main() {
  local do_all=1 do_packages=0 do_templates=0 do_vscode=0 do_python=0 do_bin=0

  if [[ $# -gt 0 ]]; then
    do_all=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --all) do_all=1 ;;
        --packages) do_packages=1 ;;
        --templates) do_templates=1 ;;
        --vscode) do_vscode=1 ;;
        --python) do_python=1 ;;
        --bin) do_bin=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown arg: $1" ;;
      esac
      shift
    done
  fi

  if [[ $do_all -eq 1 ]]; then
    do_packages=1; do_templates=1; do_vscode=1; do_python=1; do_bin=1
  fi

  if [[ $do_packages -eq 1 ]]; then
    is_arch && install_arch_packages || warn "non-arch OS: skip pacman packages"
    install_pip_packages
  fi

  [[ $do_templates -eq 1 ]] && sync_templates
  [[ $do_vscode -eq 1 ]] && sync_vscode_configs
  [[ $do_python -eq 1 ]] && install_python_lib
  [[ $do_bin -eq 1 ]] && sync_bin_tools

  log "done."
}

main "$@"

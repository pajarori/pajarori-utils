# pajarori/pwn.py
from pwn import *
from pwnlib.elf.elf import ELF as _ELF

import os, shutil

def get_terminal(split: str = "horizontal", force: bool = False):
    if context.terminal and not force:
        return context.terminal

    split_flag = "-h" if split == "horizontal" else "-v"

    def has(bin_name):
        return shutil.which(bin_name) is not None

    TERMINALS = [
        ("tmux", ["tmux", "splitw", split_flag], lambda: os.environ.get("TMUX") and has("tmux")),
        ("kitty", ["kitty", "-e"], lambda: has("kitty")),
        ("wezterm", ["wezterm", "start", "--"], lambda: has("wezterm")),
        ("alacritty", ["alacritty", "-e"], lambda: has("alacritty")),
        ("konsole", ["konsole", "-e"], lambda: has("konsole")),
        ("gnome-terminal", ["gnome-terminal", "--"], lambda: has("gnome-terminal")),
        ("xfce4-terminal", ["xfce4-terminal", "-e"], lambda: has("xfce4-terminal")),
        ("terminator", ["terminator", "-x"], lambda: has("terminator")),
        ("xterm", ["xterm", "-e"], lambda: has("xterm")),
    ]

    for _, cmd, condition in TERMINALS:
        if condition():
            return cmd

    return ["bash", "-lc"]

context.terminal = get_terminal()

def ELF(path, *args, **kwargs):
    elf = _ELF(path, *args, **kwargs)
    context.binary = elf
    return elf

def start(elf: str, **kwargs):
    if args.GDB and kwargs.get("gdbscript"):
        return gdb.debug(elf.path, gdbscript=kwargs.get("gdbscript"))
    elif args.REMOTE:
        return remote(sys.argv[1], sys.argv[2])
    else:
        return process(elf.path)

__all__ = [name for name in globals() if not name.startswith("_")]

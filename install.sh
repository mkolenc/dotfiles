#!/bin/sh
# Symlink dotfiles into $HOME

DOTFILES="$HOME/dotfiles"

link() {
    src="$DOTFILES/$1"
    dest="$HOME/$2"

    mkdir -p "$(dirname "$dest")"
    ln -sfn "$src" "$dest"
    echo "Linked $dest → $src"
}

# We will eventually auto-set up the symlinks here:
# e.g. link ".config/bash/.bashrc" ".bashrc"


# Remove greeting
set -g fish_greeting

# Fix lang
set -gx LANG en_US.UTF-8

if status is-interactive
    # Commands to run in interactive sessions can go here
end

# Starship
starship init fish | source

# Local bins
fish_add_path ~/.local/bin

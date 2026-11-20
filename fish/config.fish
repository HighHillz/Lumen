# User bin dirs on PATH, resolved per user (fish_add_path skips missing dirs).
fish_add_path -g ~/.local/bin ~/.config/fish/scripts

if status is-interactive # Commands to run in interactive sessions can go here
    # No greeting
    set fish_greeting
    # Use starship
    starship init fish | source
    # Aliases
    alias ls 'eza --icons=auto'
end

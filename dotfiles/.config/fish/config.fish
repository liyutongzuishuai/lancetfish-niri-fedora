if status is-interactive
    # Commands to run in interactive sessions can go here
end
set fish_greeting ""
set -p PATH ~/.local/bin
zoxide init fish --cmd cd | source

function y
	set tmp (mktemp -t "yazi-cwd.XXXXXX")
	yazi $argv --cwd-file="$tmp"
	if read -z cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
		builtin cd -- "$cwd"
	end
	rm -f -- "$tmp"
end

function ls
	command eza --icons $argv
end
function tree
	command eza --icons --tree $argv
end

# ft运行fastfetch
abbr ft fastfetch
abbr reboot 'systemctl reboot'
abbr c clear
abbr cpu pkexec env WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR /opt/auto-cpufreq/venv/bin/auto-cpufreq-gtk
# opencode
fish_add_path /home/lancetfish/.opencode/bin
set -gx EDITOR vim
set -gx VISUAL vim
set -x OLLAMA_MODELS_MIRROR https://registry.npmmirror.com

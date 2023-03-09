[ -e /proc ] && \
if grep -qEi '(microsoft|wsl)' /proc/version
	pgrep dbus-daemon > /dev/null
	if test $status -eq 1
		dbus-launch --sh-syntax | read --line bus_address ignored bus_pid bus_windowid

		set -Ux DBUS_SESSION_BUS_ADDRESS (string match -r "'(.*)'" $bus_address)[2]
		set -Ux DBUS_SESSION_BUS_ID (string match -r "=(.*);" $bus_pid)[2]
		set -Ux DBUS_SESSION_BUS_WINDOWID (string match -r "=(.*);" $bus_windowid)[2]
	end

	pgrep gnome-keyring-d > /dev/null
	if test $status -eq 1
		gnome-keyring-daemon | read --line gnome_keyring_control ssh_auth_sock

		set -Ux GNOME_KEYRING_CONTROL (string split -m 1 = $gnome_keyring_control)[2]
		set -Ux SSH_AUTH_SOCK (string split -m 1 = $ssh_auth_sock)[2]
	end
else
	setxkbmap -layout us -option ctrl:swapcaps # swap caps and ctrl key
end

# = Environment Vars
set -x ASDF_PYTHON_DEFAULT_PACKAGES_FILE "$HOME/.config/asdf/default-python-packages"

source ~/.config/fish/functions/fish_prompt.fish
source ~/.config/fish/functions/fish_user_aliases.fish

# Customise theme
set -g theme_display_group no

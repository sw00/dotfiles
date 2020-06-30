if grep -qEi '(microsoft|wsl)' /proc/version
	set -x DISPLAY (cat /etc/resolv.conf | grep nameserver | awk '{print $2}'):0
	set -x LIBGL_ALWAYS_INDIRECT 1
	set -x VAGRANT_WSL_ENABLE_WINDOWS_ACCESS 1

	fenv "eval `dbus-launch`" > /dev/null
	fenv "eval `gnome-keyring-daemon -r -d -c secrets,ssh,pkcs11`" > /dev/null
end

source ~/.config/fish/functions/fish_user_aliases.fish


if grep -qEi '(microsoft|wsl)' /proc/version
	fenv "eval `dbus-launch`" > /dev/null
	fenv "eval `gnome-keyring-daemon -r -d -c secrets,ssh,pkcs11`" > /dev/null
end

source ~/.config/fish/functions/fish_user_aliases.fish


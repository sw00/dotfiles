if grep -qEi '(microsoft|wsl)' /proc/version
	pgrep dbus-daemon > /dev/null
	if test $status -eq 1
		fenv "eval `dbus-launch`" > /dev/null
	end

	pgrep gnome-keyring-d > /dev/null
	if test $status -eq 1
		fenv "eval `gnome-keyring-daemon -r -d -c secrets,ssh,pkcs11`" > /dev/null
	end
end

source ~/.config/fish/functions/fish_user_aliases.fish


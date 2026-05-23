@echo off
:: wsl-git.cmd — thin wrapper that delegates git to WSL's git binary.
::
:: Installed by os/wsl/up.sh to %LOCALAPPDATA%\bin\git.cmd and referenced
:: by VSCodium's "git.path" setting.  This means VSCodium always uses the
:: Linux git (with proper hooks, credential helpers, and line-ending rules)
:: even when running as a native Windows process.
::
:: For WSL-remote workspaces (jeanp413.open-remote-wsl extension) the
:: VSCodium server runs inside WSL, so the real git is used directly and
:: this wrapper is not invoked at all.
wsl.exe git %*

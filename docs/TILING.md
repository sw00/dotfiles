# Tiling Window Managers — AeroSpace & Komorebi

Keybinding parity and layout policy. Reference material — load when modifying WM config.

## Workspace scheme

10 workspaces per monitor (not 7). Matches the number row on a full keyboard and gives each monitor a contiguous block (1-5 → primary, 6-10 → secondary) for muscle memory across dual-monitor setups.

## Keybinding parity

AeroSpace (macOS) and whkdrc (Komorebi, Windows) share the same key grammar.

| Action | AeroSpace | whkdrc (Komorebi) |
|---|---|---|
| Focus | `alt-h/j/k/l` | `alt+h/j/k/l` |
| Move window | `alt-shift-h/j/k/l` | `alt+shift+h/j/k/l` |
| Workspace | `alt-1...0` | `alt+1...0` (0 → workspace 9) |
| Move to workspace | `alt-shift-1...0` | `alt+shift+1...0` |
| Resize ±50 | `alt-minus/equal` | `alt+-/= ` |
| Resize ±200 | `alt-shift-minus/equal` | `alt+shift+-/=` |
| Close window | `alt-q` | `alt+q` |
| Toggle float | `alt-f` | `alt+f` |
| Cycle layout | `alt-x` | `alt+x` |
| Back-and-forth | `alt-tab` | `alt+tab` |
| Focus monitor | `alt-ctrl-h/l` | `alt+ctrl+h/l` (h=prev, l=next) |
| Move to monitor | `alt-shift-ctrl-h/l` | `alt+shift+ctrl+h/l` (h=0, l=1) |

**Known asymmetry:** Komorebi lacks directional monitor navigation (only cycle-monitor next/prev), so `alt+ctrl+h`=previous, `alt+ctrl+l`=next (not true left/right). `alt+ctrl+j/k` were removed — they silently duplicated h/l on a horizontal setup.

**alt-m differs:** AeroSpace = native macOS fullscreen (window leaves tiling); Komorebi = toggle-monocle (maximised within tiling).

## Layout policy

All workspaces start as **BSP** (binary space partition). Custom per-workspace layouts were removed for consistency — use `alt-x` (cycle-layout) as the escape hatch for temporary changes. Float rules are kept minimal: system dialogs, Bitwarden, Mullvad VPN, Windows Terminal, Flameshot, and (on Windows only) Brave + Obsidian.

## Config paths

- macOS: `hosts/mbpm3/aerospace/.config/aerospace/aerospace.toml`
- Windows: `os/wsl/windows/komorebi/` (not stowed; deployed by `os/wsl/up.sh` to `%USERPROFILE%\.config\`)

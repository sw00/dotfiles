#!/usr/bin/env bash

FILES_DIR=./files
files_list=$(ls -p $FILES_DIR | grep -v /)

for file in ${files_list[@]}; do
    if [[ '#\n' = `head -n 1 -c 1 "$FILES_DIR/$file"` ]]; then
        echo ++++++++++++++++++
        dest=$(cat $FILES_DIR/$file | head -n 1 | awk '/#/ {print $NF}')
        echo "+++ Copying $FILES_DIR/$file to $dest"
        if [[ $dest = /etc/* ]]; then
            echo sudo cp -f "$FILES_DIR/$file" "$dest"
        else
            echo cp -f "$FILES_DIR/$file" "$dest"
        fi
    fi
done

WIN_CONFIG=$(wslpath $(wslvar APPDATA))
WIN_HOME=$(wslpath $(wslvar USERPROFILE))

# alacritty
mkdir -p $WIN_CONFIG/Alacritty
cp -f $FILES_DIR/alacritty.toml $WIN_CONFIG/Alacritty/

# komorebi
KOMOREBI_HOME=$WIN_HOME/.config/komorebi
WIN_STARTUP="$(wslpath $(wslvar APPDATA))/Microsoft/Windows/Start Menu/Programs/Startup"

cp $FILES_DIR/bootstrap-komorebi.ps1 "$WIN_HOME/"
cp $FILES_DIR/komorebi.ahk "$WIN_STARTUP/"

mkdir -p "$KOMOREBI_HOME"
cp $FILES_DIR/komorebi.json "$KOMOREBI_HOME/"
cp $FILES_DIR/komorebic.lib.ahk "$KOMOREBI_HOME/"

pwsh.exe -File "C:\Users\settw\bootstrap-komorebi.ps1"


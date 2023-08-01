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

# komorebi
WIN_HOME=$(wslpath $(wslvar USERPROFILE))
WIN_STARTUP="$(wslpath $(wslvar APPDATA))/Microsoft/Windows/Start Menu/Programs/Startup"
cp -f "$FILES_DIR/komorebi.json" "$WIN_HOME/"
cp -f "$FILES_DIR/komorebi.ps1" "$WIN_STARTUP"

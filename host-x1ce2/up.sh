#!/usr/bin/env bash

FILES_DIR=./files
files_list=$(ls -p $FILES_DIR | grep -v /)

for file in ${files_list[@]}; do
    dest=$(cat $FILES_DIR/$file | head -n 1 | awk '/#/ {print $NF}')
    echo "+++ Copying $FILES_DIR/$file to $dest"
    cp -f "$FILES_DIR/$file" "$dest"
done

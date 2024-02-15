#!/bin/bash

DEFAULT_PROFILE=mobile

stdbuf -oL libinput debug-events | \
    grep -E --line-buffered '^[[:space:]-]+event[0-9]+[[:space:]]+SWITCH_TOGGLE[[:space:]]' | \
    while read line; do
    autorandr --change --default $DEFAULT_PROFILE
done

#!/bin/bash

GLOBAL_IP=$(ip addr | grep -E 'inet(.*)global' | awk '{ print $2 }' | cut -d/ -f1)

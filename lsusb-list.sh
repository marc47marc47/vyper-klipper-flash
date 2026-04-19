#!/bin/sh
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL 2>&1; echo "---"; ls /media/ /mnt/ 2>&1; echo "---"; dmesg 2>&1 | tail -n 15

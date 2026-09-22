#!/usr/bin/env bash

LOG_FILE="/var/log/syslog"

if [[ ! -f "$LOG_FILE" ]]; then
	echo "File not found"
	exit 1
fi

grep -aiE "error|fail" "$LOG_FILE" > report.txt

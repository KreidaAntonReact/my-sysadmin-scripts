#!/usr/bin/env bash

LOG_FILE="/var/log/auth.log"

grep -aiE "error|fail" "$LOG_FILE" > report.txt

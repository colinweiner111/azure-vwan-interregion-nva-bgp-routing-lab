#!/usr/bin/env bash
set -euo pipefail

pid_file=/var/tmp/vwan-validation-2222.pid
listener_file=/var/tmp/vwan-validation-2222.py
log_file=/var/tmp/vwan-validation-2222.log

if [[ -f "$pid_file" ]]; then
  listener_pid=$(cat "$pid_file")
  if [[ "$listener_pid" =~ ^[0-9]+$ ]] && kill -0 "$listener_pid" 2>/dev/null; then
    kill "$listener_pid"
  fi
fi

rm -f "$pid_file" "$listener_file" "$log_file"
echo "LISTENER host=$(hostname) port=2222 STOPPED"

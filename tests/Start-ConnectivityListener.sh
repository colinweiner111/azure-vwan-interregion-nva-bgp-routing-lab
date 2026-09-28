#!/usr/bin/env bash
set -euo pipefail

pid_file=/var/tmp/vwan-validation-2222.pid
listener_file=/var/tmp/vwan-validation-2222.py
log_file=/var/tmp/vwan-validation-2222.log

if [[ -f "$pid_file" ]]; then
  old_pid=$(cat "$pid_file")
  if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid"
  fi
fi

cat > "$listener_file" <<'PY'
import socket
import time

deadline = time.monotonic() + 900
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("0.0.0.0", 2222))
    listener.listen()
    listener.settimeout(5)
    while time.monotonic() < deadline:
        try:
            connection, _ = listener.accept()
        except TimeoutError:
            continue
        with connection:
            pass
PY

nohup python3 "$listener_file" > "$log_file" 2>&1 &
listener_pid=$!
echo "$listener_pid" > "$pid_file"

for _ in {1..10}; do
  if kill -0 "$listener_pid" 2>/dev/null && timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/2222'; then
    echo "LISTENER host=$(hostname) port=2222 pid=$listener_pid PASS"
    exit 0
  fi
  sleep 1
done

cat "$log_file" >&2
exit 1

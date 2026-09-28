#!/usr/bin/env bash
set -u

source_vm=$(hostname)
echo "SOURCE=$source_vm UTC=$(date -u +%FT%TZ)"

for target in branch1-vm=10.100.0.4 hub1-spoke1-vm=172.16.1.4 hub1-spoke2-vm=172.16.2.4 hub2-spoke1-vm=172.16.3.4 hub2-spoke2-vm=172.16.4.4; do
  name=${target%=*}
  ip=${target#*=}
  [[ "$name" == "$source_vm" ]] && continue

  for attempt in 1 2 3; do
    if timeout 5 bash -c "exec 3<>/dev/tcp/$ip/2222"; then
      echo "TCP2222 source=$source_vm target=$name ip=$ip attempt=$attempt PASS"
    else
      result=$?
      echo "TCP2222 source=$source_vm target=$name ip=$ip attempt=$attempt FAIL exit=$result"
    fi
  done

  if timeout 3 bash -c "exec 3<>/dev/tcp/$ip/22"; then
    echo "SSH22BLOCK source=$source_vm target=$name ip=$ip FAIL"
  else
    echo "SSH22BLOCK source=$source_vm target=$name ip=$ip PASS"
  fi
done

case "$source_vm" in
  hub*-spoke*-vm)
    if curl -4 --noproxy '*' --fail --silent --show-error --retry 2 --retry-all-errors --retry-delay 2 --connect-timeout 8 --max-time 30 -o /dev/null https://www.microsoft.com; then
      echo "HTTPS source=$source_vm target=www.microsoft.com PASS"
    else
      result=$?
      echo "HTTPS source=$source_vm target=www.microsoft.com FAIL exit=$result"
    fi
    ;;
esac

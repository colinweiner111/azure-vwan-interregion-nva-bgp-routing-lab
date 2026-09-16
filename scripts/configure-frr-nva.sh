#!/usr/bin/env bash
set -euo pipefail

hub_peers_csv="$1"
advertised_prefix="$2"
local_asn="${3:-65020}"
load_balancer_ip="$4"

export DEBIAN_FRONTEND=noninteractive
for attempt in 1 2 3 4 5; do
  apt-get -o Acquire::Retries=3 update
  if apt-get install -y frr frr-pythontools iptables-persistent netcat-openbsd traceroute; then
    break
  fi
  if [ "$attempt" -eq 5 ]; then
    exit 1
  fi
  sleep $((attempt * 10))
done

sed -i 's/^bgpd=no/bgpd=yes/' /etc/frr/daemons
cat >/etc/sysctl.d/99-nva.conf <<'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
EOF
sysctl --system

ip address show dev lo | grep -q "${load_balancer_ip}/32" || ip address add "${load_balancer_ip}/32" dev lo
iptables -P FORWARD ACCEPT
for private_prefix in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
  iptables -t nat -C POSTROUTING -d "${private_prefix}" -j RETURN 2>/dev/null || iptables -t nat -I POSTROUTING 1 -d "${private_prefix}" -j RETURN
done
iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
netfilter-persistent save

router_id=$(hostname -I | awk '{print $1}')
cat >/etc/frr/frr.conf <<EOF
frr defaults traditional
hostname $(hostname)
service integrated-vtysh-config
ip nht resolve-via-default
!
router bgp ${local_asn}
 bgp router-id ${router_id}
 no bgp ebgp-requires-policy
 no bgp network import-check
 network ${advertised_prefix}
EOF

IFS=',' read -ra hub_peers <<<"${hub_peers_csv}"
for peer in "${hub_peers[@]}"; do
  cat >>/etc/frr/frr.conf <<EOF
 neighbor ${peer} remote-as 65515
 neighbor ${peer} ebgp-multihop 255
 neighbor ${peer} timers 10 30
EOF
done

cat >>/etc/frr/frr.conf <<'EOF'
!
line vty
EOF

systemctl enable frr
systemctl restart frr
cat >/etc/systemd/system/azure-lb-probe.service <<'EOF'
[Unit]
Description=Azure Load Balancer health probe listener
After=network-online.target

[Service]
ExecStart=/usr/bin/nc -lk -p 8080
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now azure-lb-probe.service
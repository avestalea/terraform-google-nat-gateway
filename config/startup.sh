#!/bin/bash -xe

# Enable ip forwarding and nat
sysctl -w net.ipv4.ip_forward=1

# Make forwarding persistent.
sed -i= 's/^[# ]*net.ipv4.ip_forward=[[:digit:]]/net.ipv4.ip_forward=1/g' /etc/sysctl.conf

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

apt-get update

# Install nginx for instance http health check
apt-get install -y \
  nginx \
  prometheus-node-exporter \
  unzip

# Grab a copy of CloudProber, and configure it
curl -L -o /tmp/cloudprober.zip https://github.com/google/cloudprober/releases/download/0.9.3/cloudprober-0.9.3-linux-x86_64.zip
mkdir -p /opt/cloudprober
unzip /tmp/cloudprober.zip
mv /tmp/cloudprober-0.9.3-linux-x86_64/cloudprober /opt/cloudprober/cloudprober
chmod +x /opt/cloudprober/cloudprober

# Add the cloudprober configuration
cat > /opt/cloudprober/cloudprober.conf <<EOL
probe {
  name: "nat_google_homepage"
  type: HTTP
  targets {
    host_names: "www.google.com"
  }
  interval_msec: 5000  # 5s
  timeout_msec: 1000   # 1s
}

surfacer {
  type: STACKDRIVER
}

surfacer {
  type: PROMETHEUS
}
EOL

# Create the systemd unit file
cat > /etc/systemd/system/cloudprober.service <<EOL
[Unit]
Description=cloudprober
After=network.target

[Service]
Type=simple
ExecStart=/opt/cloudprober/cloudprober --config_file /opt/cloudprober/cloudprober.conf
ExecStop=pkill cloudprober
ExecReload=pkill cloudprober && /opt/cloudprober/cloudprober --config_file /opt/cloudprober/cloudprober.conf
Restart=on-abort
WorkingDirectory=/opt/cloudprober
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=cloudprober

[Install]
WantedBy=multi-user.target
EOL

systemctl enable cloudprober
systemctl start cloudprober

ENABLE_SQUID="${squid_enabled}"

if [[ "$$ENABLE_SQUID" == "true" ]]; then
  apt-get install -y squid3

  cat - > /etc/squid/squid.conf <<'EOM'
${file("${squid_config == "" ? "${format("%s/config/squid.conf", module_path)}" : squid_config}")}
EOM

  systemctl reload squid
fi

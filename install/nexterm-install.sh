#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Mathias Wagner (gnmyt)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://nexterm.dev/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  libssl3 \
  libssh2-1 \
  libcurl4 \
  libcairo2 \
  libpng16-16 \
  libpango-1.0-0 \
  libpangocairo-1.0-0 \
  libwebp7 \
  libossp-uuid16 \
  libpulse0 \
  libvorbisenc2 \
  libvorbis0a \
  libogg0 \
  libvncclient1 \
  libfreerdp2-2 \
  libfreerdp-client2-2
msg_ok "Installed Dependencies"

case "$(dpkg --print-architecture)" in
  amd64) NX_ARCH="x64" ;;
  arm64) NX_ARCH="arm64" ;;
  *)
    msg_error "Unsupported architecture: $(dpkg --print-architecture)"
    exit 1
    ;;
esac

fetch_and_deploy_gh_release "nexterm-engine" "gnmyt/Nexterm" "prebuild" "latest" "/opt/nexterm/engine" "nexterm-engine-linux-${NX_ARCH}.tar.gz"
fetch_and_deploy_gh_release "nexterm-server" "gnmyt/Nexterm" "singlefile" "latest" "/opt/nexterm/server" "nexterm-server-linux-${NX_ARCH}"

msg_info "Configuring Nexterm"
LOCAL_ENGINE_TOKEN=$(tr -d '-' </proc/sys/kernel/random/uuid)$(tr -d '-' </proc/sys/kernel/random/uuid)
ENCRYPTION_KEY=$(tr -d '-' </proc/sys/kernel/random/uuid)$(tr -d '-' </proc/sys/kernel/random/uuid)

mkdir -p /etc/nexterm-engine /etc/nexterm-server /opt/nexterm/data
cat <<EOF >/etc/nexterm-engine/config.yaml
server_host: "127.0.0.1"
server_port: 7800
registration_token: "${LOCAL_ENGINE_TOKEN}"
tls: false
EOF

cat <<EOF >/etc/nexterm-server/server.env
NODE_ENV=production
SERVER_PORT=6989
LOCAL_ENGINE_TOKEN=${LOCAL_ENGINE_TOKEN}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
EOF
chmod 0640 /etc/nexterm-server/server.env
msg_ok "Configured Nexterm"

msg_info "Creating Engine Service"
cat <<EOF >/etc/systemd/system/nexterm-engine.service
[Unit]
Description=Nexterm Engine
Documentation=https://docs.nexterm.dev/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/nexterm-engine
Environment=FREERDP_EXTENSION_PATH=/opt/nexterm/engine/lib/freerdp2
Environment=LD_LIBRARY_PATH=/opt/nexterm/engine/lib
ExecStart=/opt/nexterm/engine/nexterm-engine
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now nexterm-engine
msg_ok "Created Engine Service"

msg_info "Creating Server Service"
cat <<EOF >/etc/systemd/system/nexterm-server.service
[Unit]
Description=Nexterm Server
Documentation=https://docs.nexterm.dev/
After=network-online.target nexterm-engine.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/nexterm/data
EnvironmentFile=/etc/nexterm-server/server.env
ExecStart=/opt/nexterm/server/nexterm-server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now nexterm-server
msg_ok "Created Server Service"

motd_ssh
customize
cleanup_lxc

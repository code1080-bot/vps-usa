#!/bin/bash
set -e
echo "Starting VPN setup on Codespace..."
sudo apt-get update -y > /dev/null 2>&1
sudo apt-get install -y curl jq unzip > /dev/null 2>&1

mkdir -p /tmp/xray-vpn && cd /tmp/xray-vpn

# Download Xray
if [ ! -f "xray" ]; then
    curl -sL https://github.com/XTLS/Xray-core/releases/download/v24.11.30/Xray-linux-64.zip -o xray.zip
    unzip -o xray.zip > /dev/null
    chmod +x xray
fi

# Download cloudflared
if [ ! -f "cloudflared" ]; then
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
    chmod +x cloudflared
fi

UUID=$(cat /proc/sys/kernel/random/uuid)
cat <<EOF > config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 8080,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "$UUID" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vless" }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

pkill -f "./xray" || true
nohup ./xray run -c config.json > xray.log 2>&1 &

pkill -f "./cloudflared" || true
nohup ./cloudflared tunnel --url http://127.0.0.1:8080 --no-autoupdate > tunnel.log 2>&1 &

sleep 6
DOMAIN=""
for i in {1..30}; do
    DOMAIN=$(grep -o 'https://[-a-zA-Z0-9.]*\.trycloudflare\.com' tunnel.log | head -n 1 | sed 's|https://||' || true)
    if [ -n "$DOMAIN" ]; then
        break
    fi
    sleep 2
done

VLESS_KEY="vless://${UUID}@${DOMAIN}:443?type=ws&security=tls&sni=${DOMAIN}&path=%2Fvless#My-USA-Server"
echo "$VLESS_KEY"

# Save and push to repo
REPO_DIR="/workspaces/vps-usa"
if [ -d "$REPO_DIR" ]; then
    cd "$REPO_DIR"
    echo "$VLESS_KEY" > VLESS_KEY.txt
    git config user.name "codespace"
    git config user.email "codespace@github.com"
    git add VLESS_KEY.txt
    git commit -m "Automated VLESS key update" || true
    git push origin main || true
fi

echo "SUCCESS"
#!/bin/bash
set -e

echo "=== [1/4] Установка Xray и Cloudflared на сервер Codespace ==="
sudo apt-get update -y > /dev/null 2>&1
sudo apt-get install -y curl jq unzip qrencode > /dev/null 2>&1

# 1. Скачиваем Xray
mkdir -p ~/xray-vpn && cd ~/xray-vpn
if [ ! -f "xray" ]; then
    echo "Скачивание Xray-core..."
    curl -sL https://github.com/XTLS/Xray-core/releases/download/v24.11.30/Xray-linux-64.zip -o xray.zip
    unzip -o xray.zip > /dev/null
    chmod +x xray
fi

# 2. Скачиваем cloudflared
if [ ! -f "cloudflared" ]; then
    echo "Скачивание Cloudflared..."
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
    chmod +x cloudflared
fi

# 3. Генерируем UUID и конфиг
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

# 4. Запускаем Xray
pkill -f "./xray" || true
nohup ./xray run -c config.json > xray.log 2>&1 &
sleep 1

# 5. Запускаем Cloudflare Tunnel
pkill -f "./cloudflared" || true
rm -f tunnel.log
nohup ./cloudflared tunnel --url http://127.0.0.1:8080 --no-autoupdate > tunnel.log 2>&1 &

echo "Поднятие туннеля (ждем 5-10 секунд)..."
DOMAIN=""
for i in {1..30}; do
    DOMAIN=$(grep -o 'https://[-a-zA-Z0-9.]*\.trycloudflare\.com' tunnel.log | head -n 1 | sed 's|https://||' || true)
    if [ -n "$DOMAIN" ]; then
        break
    fi
    sleep 1
done

if [ -z "$DOMAIN" ]; then
    echo "Ошибка получения домена Cloudflare. Проверьте tunnel.log:"
    cat tunnel.log
    exit 1
fi

VLESS_KEY="vless://${UUID}@${DOMAIN}:443?type=ws&security=tls&sni=${DOMAIN}&path=%2Fvless#My-USA-Server"

echo ""
echo "==================================================================="
echo "ГОТОВО! ВАШ ЛИЧНЫЙ СЕРВЕР В США РАБОТАЕТ!"
echo "==================================================================="
echo ""
echo "ВАШ ГОТОВЫЙ КЛЮЧ ДЛЯ HAPP:"
echo ""
echo "$VLESS_KEY"
echo ""
echo "==================================================================="
echo "QR-КОД ДЛЯ СКАНИРОВАНИЯ В HAPP (КАМЕРОЙ ИЛИ ЧЕРЕЗ ПЛЮСИК):"
echo ""
qrencode -t ANSIUTF8 "$VLESS_KEY"
echo "==================================================================="

# Сохраняем в файл
echo "$VLESS_KEY" > ~/vless_key.txt
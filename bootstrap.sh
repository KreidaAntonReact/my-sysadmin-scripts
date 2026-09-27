#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

echo "== 1. RAID/LVM на loop-устройствах =="
if grep -q "^md0" /proc/mdstat; then
    echo "RAID уже собран — шаг пропущен."
else
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mdadm lvm2
    sudo mkdir -p /mnt/raid-lab
    cd /mnt/raid-lab
    sudo dd if=/dev/zero of=disk1.img bs=1M count=512 status=none
    sudo dd if=/dev/zero of=disk2.img bs=1M count=512 status=none
    sudo dd if=/dev/zero of=disk3.img bs=1M count=512 status=none
    LOOP1=$(sudo losetup -fP --show disk1.img)
    LOOP2=$(sudo losetup -fP --show disk2.img)
    LOOP3=$(sudo losetup -fP --show disk3.img)
    yes | sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 "$LOOP1" "$LOOP2"
    sudo mkfs.ext4 -F /dev/md0
    sudo mkdir -p /mnt/raid && sudo mount /dev/md0 /mnt/raid
    yes | sudo pvcreate "$LOOP3"
    sudo vgcreate vg_data "$LOOP3"
    yes | sudo lvcreate -L 200M -n lv_logs vg_data
    sudo mkfs.ext4 -F /dev/vg_data/lv_logs
    sudo mkdir -p /mnt/logs && sudo mount /dev/vg_data/lv_logs /mnt/logs
    cd "$REPO_DIR"
fi

echo "== 2. Nginx и TLS =="
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx openssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/my-app.key \
    -out /etc/ssl/certs/my-app.crt \
    -subj "/CN=my-app.local"
sudo cp "$REPO_DIR/nginx/my-app.conf" /etc/nginx/sites-available/my-app
sudo ln -sf /etc/nginx/sites-available/my-app /etc/nginx/sites-enabled/my-app
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx

echo "== 3. systemd-служба =="
sudo cp "$REPO_DIR/my-app.service" /etc/systemd/system/my-app.service
sudo systemctl daemon-reload
sudo systemctl enable my-app
sudo systemctl restart my-app
sleep 3

echo "== 4. Самопроверка =="
printf "Ожидание готовности сервиса"

READY=no

for i in $(seq 1 60); do
    if curl -ksf -o /dev/null https://127.0.0.1/; then
        READY=yes
        break
    fi
    printf "."
    sleep 2
done
echo

if [ "$READY" = yes ]; then
    curl -ksI https://127.0.0.1/ | head -1
else
    echo "ВНИМАНИЕ: сервис не ответил"
    echo "Смотрите: sudo systemctl status my-app и docker compose logs"
fi

cat /proc/mdstat
df -h | grep -E "raid|logs" || echo "ВНИМАНИЕ: тома RAID/LVM не смонтированы"
sudo systemctl status my-app --no-pager
echo "bootstrap.sh: готово"

#!/bin/bash
# Script instalasi Nginx di Ubuntu 22.04.5 LTS
# Mengikuti panduan resmi: https://nginx.org/en/linux_packages.html#Ubuntu
# Keluar jika terjadi error
set -e

echo "##########################"
echo "Verifikasi root privileges"
echo "##########################"
if [[ $EUID -ne 0 ]]; then
   echo "Script ini harus dijalankan sebagai root" 
   exit 1
fi
echo ""

echo "####################"
echo "Update package index"
echo "####################"
apt update
echo ""

echo "####################"
echo "Install dependencies"
echo "####################"
apt install -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring
echo ""

echo "#################################"
echo "Import official nginx signing key"
echo "#################################"
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
echo ""

echo "##########################"
echo "Verifikasi fingerprint key"
echo "##########################"
echo "Fingerprint: $(gpg --no-default-keyring --keyring /usr/share/keyrings/nginx-archive-keyring.gpg --list-keys | grep -E '^uid' | awk '{print $NF}')"
echo "#################################################################################"
echo "Silakan verifikasi fingerprint di https://nginx.org/en/linux_packages.html#stable"
echo "#################################################################################"
echo ""

echo "#################################"
echo "Tambahkan repository stabil Nginx"
echo "#################################"
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" \
    | tee /etc/apt/sources.list.d/nginx.list
echo ""

echo "####################################"
echo "Update repository setelah penambahan"
echo "####################################"
apt update
echo ""

echo "#############"
echo "Install Nginx"
echo "#############"
apt install -y nginx
echo ""

echo "################"
echo "Aktifkan service"
echo "################"
systemctl enable --now nginx
echo ""

echo "########################"
echo "Verifikasi Status Nginx:"
echo "########################"
systemctl status nginx --no-pager
echo ""

echo "#############################################"
echo "Firewall configuration (jika menggunakan UFW)"
echo "#############################################"
if command -v ufw &> /dev/null; then
    ufw allow 'Nginx HTTP'
    ufw allow 'Nginx HTTPS'
    ufw reload
fi
echo ""

echo "################"
echo "Test konfigurasi"
echo "################"
nginx -t
echo ""

echo "######################"
echo "Tampilkan pesan sukses"
echo "######################"
echo -e "\n\033[1;32mNginx berhasil diinstall!\033[0m"
echo "Versi: $(nginx -v 2>&1 | cut -d '/' -f 2)"
echo "Dokumentasi: https://nginx.org/en/docs/"
echo "File Konfigurasi: /etc/nginx/nginx.conf"
echo "Direktori Situs: /usr/share/nginx/html"
echo "Perintah Kontrol:"
echo "Start: systemctl start nginx"
echo "Stop: systemctl stop nginx"
echo "Restart: systemctl restart nginx"
echo ""

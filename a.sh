#!/bin/bash
# ===============================================
# Script to Add Reverse Proxy and Automatic SSL
# Renewal for WordPress Website Running on Apache
# ===============================================

set -e

# -------------------
# USER CONFIGURATION
# -------------------
DOMAIN="sahmcore.com.sa"         # The domain of your WordPress site
ADMIN_EMAIL="a.saeed@$DOMAIN"    # Admin email for SSL certs
WEB_PATH="/var/www/html"          # The WordPress path
APACHE_CONF_PATH="/etc/apache2/sites-available/000-default.conf" # Apache configuration file

# SSL Configuration (Let's Encrypt)
SSL_CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
SSL_CERT_FULLCHAIN="$SSL_CERT_PATH/fullchain.pem"
SSL_CERT_PRIVKEY="$SSL_CERT_PATH/privkey.pem"

# Internal VM IPs and Ports
ERP_IP="192.168.116.13"
ERP_PORT="8069"
DOCS_IP="192.168.116.1"
DOCS_PORT="9443"
MAIL_IP="192.168.116.1"
MAIL_PORT="444"
NOMOGROW_IP="192.168.116.48"
NOMOGROW_PORT="8082"
VENTURA_IP="192.168.116.10"
VENTURA_PORT="8080"
WEBADMIN_IP="192.168.116.1"
WEBADMIN_PORT="9443"
WEBMAIL_IP="192.168.116.1"
WEBMAIL_PORT="444"

# -------------------
# SYSTEM UPDATE & INSTALL DEPENDENCIES
# -------------------
echo "[INFO] Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget unzip lsb-release software-properties-common net-tools ufw dnsutils git certbot python3-certbot-apache

# -------------------
# STOP NGINX AND CADDY IF RUNNING
# -------------------
echo "[INFO] Stopping Nginx or Caddy if running..."
sudo systemctl stop nginx || true
sudo systemctl disable nginx || true
sudo systemctl mask nginx || true
sudo systemctl stop caddy || true
sudo systemctl disable caddy || true
sudo systemctl mask caddy || true

# -------------------
# ENABLE APACHE MODULES
# -------------------
echo "[INFO] Enabling required Apache modules..."
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod ssl
sudo a2enmod rewrite
sudo systemctl restart apache2

# -------------------
# CREATE A REVERSE PROXY CONFIGURATION
# -------------------
echo "[INFO] Creating reverse proxy configuration for WordPress site..."
sudo tee /etc/apache2/sites-available/$DOMAIN.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerAdmin $ADMIN_EMAIL
    ServerName $DOMAIN
    DocumentRoot $WEB_PATH

    # Reverse Proxy settings for Apache
    ProxyPass / http://127.0.0.1:80/
    ProxyPassReverse / http://127.0.0.1:80/

    # Enable SSL (for Let's Encrypt SSL setup)
    Redirect permanent / https://$DOMAIN/
</VirtualHost>

<VirtualHost *:443>
    ServerAdmin $ADMIN_EMAIL
    ServerName $DOMAIN
    DocumentRoot $WEB_PATH

    SSLEngine on
    SSLCertificateFile $SSL_CERT_FULLCHAIN
    SSLCertificateKeyFile $SSL_CERT_PRIVKEY

    # Reverse Proxy settings for Apache
    ProxyPass / http://127.0.0.1:80/
    ProxyPassReverse / http://127.0.0.1:80/

    # Other recommended security headers
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
</VirtualHost>

# ERP Reverse Proxy
<VirtualHost *:80>
    ServerName erp.$DOMAIN
    ProxyPass / http://$ERP_IP:$ERP_PORT/
    ProxyPassReverse / http://$ERP_IP:$ERP_PORT/
</VirtualHost>

# Documentation Reverse Proxy
<VirtualHost *:80>
    ServerName docs.$DOMAIN
    ProxyPass / https://$DOCS_IP:$DOCS_PORT/
    ProxyPassReverse / https://$DOCS_IP:$DOCS_PORT/
</VirtualHost>

# Mail Reverse Proxy
<VirtualHost *:80>
    ServerName mail.$DOMAIN
    ProxyPass / https://$MAIL_IP:$MAIL_PORT/
    ProxyPassReverse / https://$MAIL_IP:$MAIL_PORT/
</VirtualHost>

# Nomogrow Reverse Proxy
<VirtualHost *:80>
    ServerName nomogrow.$DOMAIN
    ProxyPass / http://$NOMOGROW_IP:$NOMOGROW_PORT/
    ProxyPassReverse / http://$NOMOGROW_IP:$NOMOGROW_PORT/
</VirtualHost>

# Ventura-Tech Reverse Proxy
<VirtualHost *:80>
    ServerName ventura-tech.$DOMAIN
    ProxyPass / http://$VENTURA_IP:$VENTURA_PORT/
    ProxyPassReverse / http://$VENTURA_IP:$VENTURA_PORT/
</VirtualHost>

# Webadmin Reverse Proxy
<VirtualHost *:80>
    ServerName webadmin.$DOMAIN
    ProxyPass / https://$WEBADMIN_IP:$WEBADMIN_PORT/
    ProxyPassReverse / https://$WEBADMIN_IP:$WEBADMIN_PORT/
</VirtualHost>

# Webmail Reverse Proxy
<VirtualHost *:80>
    ServerName webmail.$DOMAIN
    ProxyPass / https://$WEBMAIL_IP:$WEBMAIL_PORT/
    ProxyPassReverse / https://$WEBMAIL_IP:$WEBMAIL_PORT/
</VirtualHost>
EOF

# Enable the new site configuration
echo "[INFO] Enabling the new Apache site configuration..."
sudo a2ensite $DOMAIN.conf
sudo systemctl reload apache2

# -------------------
# OBTAIN SSL CERTIFICATE FROM LET'S ENCRYPT
# -------------------
echo "[INFO] Obtaining SSL certificate from Let's Encrypt..."
sudo certbot --apache -d $DOMAIN -d erp.$DOMAIN -d docs.$DOMAIN -d mail.$DOMAIN -d nomogrow.$DOMAIN -d ventura-tech.$DOMAIN -d webadmin.$DOMAIN -d webmail.$DOMAIN --email $ADMIN_EMAIL --agree-tos --non-interactive

# -------------------
# AUTOMATE CERTIFICATE RENEWAL
# -------------------
echo "[INFO] Setting up automatic SSL certificate renewal..."
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# -------------------
# FIREWALL CONFIGURATION
# -------------------
echo "[INFO] Configuring the firewall..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp  # Allow SSH for remote access
sudo ufw allow 80/tcp  # Allow HTTP (for Let's Encrypt HTTP-01 challenge)
sudo ufw allow 443/tcp # Allow HTTPS
sudo ufw enable

# -------------------
# FINAL CHECKS
# -------------------
echo "[INFO] Final checks..."

# Check Apache status
echo "[INFO] Checking Apache status..."
sudo systemctl status apache2

# Check Apache config
echo "[INFO] Checking Apache config for syntax errors..."
sudo apache2ctl configtest

# Check SSL Certificate Paths
echo "[INFO] Checking SSL certificate paths..."
if [ ! -f "$SSL_CERT_FULLCHAIN" ] || [ ! -f "$SSL_CERT_PRIVKEY" ]; then
    echo "[ERROR] SSL certificate files not found!"
    exit 1
else
    echo "[INFO] SSL certificates found!"
fi

# Test Apache reverse proxy with SSL
echo "[INFO] Testing reverse proxy with SSL..."
curl -I https://$DOMAIN | head -n 10

# -------------------
# COMPLETION
# -------------------
echo "[INFO] Script completed. The website $DOMAIN should now be accessible via HTTPS with SSL certificates automatically renewed by Let's Encrypt."

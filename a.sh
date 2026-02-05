#!/bin/bash
# ===============================================
# Reverse Caddy to Apache, Set Up SSL, Reverse Proxy & Restore WordPress
# ===============================================

set -e

# -------------------
# USER CONFIGURATION
# -------------------
DOMAIN="sahmcore.com.sa"
ADMIN_EMAIL="a.saeed@$DOMAIN"
WP_PATH="/var/www/html"          # The original WordPress path
PHP_VERSION="8.3"
PHP_SOCKET="/run/php/php${PHP_VERSION}-fpm.sock"
WP_CONFIG="$WP_PATH/wp-config.php"

# Internal VM IPs for reverse proxy
THIS_VM_IP="192.168.116.37"
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

# MySQL Credentials
DB_NAME="sahmcore_wp"
DB_USER="sahmcore_user"
DB_PASS="SahmCore@2025"

# -------------------
# SYSTEM UPDATE & DEPENDENCIES
# -------------------
echo "[INFO] Updating system and installing dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget unzip lsb-release software-properties-common net-tools ufw dnsutils git mariadb-client mariadb-server apache2 certbot python3-certbot-apache

# -------------------
# STOP CADDY AND REMOVE CONFIGURATION
# -------------------
echo "[INFO] Stopping and disabling Caddy..."
sudo systemctl stop caddy
sudo systemctl disable caddy
sudo systemctl mask caddy

echo "[INFO] Removing Caddy configuration..."
sudo rm -f /etc/caddy/Caddyfile

# -------------------
# VERIFY AND RESTORE WORDPRESS FILES
# -------------------
echo "[INFO] Verifying WordPress installation at $WP_PATH..."

# Ensure that the WordPress path exists
if [ ! -d "$WP_PATH" ]; then
    echo "[ERROR] WordPress path $WP_PATH does not exist!"
    exit 1
fi

# Ensure correct permissions for the WordPress files
sudo chown -R www-data:www-data $WP_PATH
sudo find $WP_PATH -type d -exec chmod 755 {} \;
sudo find $WP_PATH -type f -exec chmod 644 {} \;

# -------------------
# RESTORE DATABASE
# -------------------
echo "[INFO] Restoring database..."

# Ensure the database exists
echo "[INFO] Creating the database $DB_NAME if it doesn't exist..."
sudo mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"

# Import the existing database dump (if applicable)
# You should place the backup file in the specified location
echo "[INFO] Importing the database dump..."
sudo mysql -u root -p $DB_NAME < /home/sahm/3478617_wpress0f72a664.sql

# -------------------
# VERIFY wp-config.php
# -------------------
echo "[INFO] Verifying wp-config.php..."
if [ ! -f "$WP_CONFIG" ]; then
    echo "[ERROR] wp-config.php is missing!"
    exit 1
fi

# Ensure wp-config.php points to the correct database
sudo sed -i "s/database_name_here/$DB_NAME/" $WP_CONFIG
sudo sed -i "s/username_here/$DB_USER/" $WP_CONFIG
sudo sed -i "s/password_here/$DB_PASS/" $WP_CONFIG

# Update site URL if necessary
sudo sed -i "s|define('WP_HOME', 'http://localhost');|define('WP_HOME', 'https://$DOMAIN');|" $WP_CONFIG
sudo sed -i "s|define('WP_SITEURL', 'http://localhost');|define('WP_SITEURL', 'https://$DOMAIN');|" $WP_CONFIG

# -------------------
# APACHE CONFIGURATION
# -------------------
echo "[INFO] Creating Apache configuration for WordPress..."

# Create Apache VirtualHost for WordPress
sudo tee /etc/apache2/sites-available/$DOMAIN.conf > /dev/null << EOF
<VirtualHost *:80>
    ServerAdmin $ADMIN_EMAIL
    ServerName $DOMAIN
    DocumentRoot $WP_PATH

    # Redirect HTTP to HTTPS
    Redirect permanent / https://$DOMAIN/

    # Logging
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

    # PHP Configuration
    <Directory $WP_PATH>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:443>
    ServerAdmin $ADMIN_EMAIL
    ServerName $DOMAIN
    DocumentRoot $WP_PATH

    # SSL Configuration
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem

    # Logging
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

    # PHP Configuration
    <Directory $WP_PATH>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

# Enable the site and SSL module
echo "[INFO] Enabling Apache site and SSL module..."
sudo a2ensite $DOMAIN.conf
sudo a2enmod ssl
sudo systemctl reload apache2

# -------------------
# SSL SETUP USING LET'S ENCRYPT
# -------------------
echo "[INFO] Setting up SSL using Let's Encrypt..."
sudo certbot --apache -d $DOMAIN -d www.$DOMAIN --agree-tos --email $ADMIN_EMAIL --non-interactive

# -------------------
# FIREWALL SETUP
# -------------------
echo "[INFO] Configuring firewall..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp    # Allow HTTP for debugging
sudo ufw allow 443/tcp   # Allow HTTPS for Let's Encrypt
sudo ufw enable

# -------------------
# REVERSE PROXY CONFIGURATION
# -------------------
echo "[INFO] Setting up reverse proxy for other services..."

# Edit Apache configuration to add reverse proxies
sudo tee -a /etc/apache2/sites-available/$DOMAIN.conf > /dev/null << EOF

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
EOF

# Enable Apache proxy modules and reload
echo "[INFO] Enabling Apache proxy modules..."
sudo a2enmod proxy proxy_http proxy_ftp proxy_balancer lbmethod_byrequests
sudo systemctl reload apache2

# -------------------
# ENABLE AUTOMATIC SSL RENEWAL
# -------------------
echo "[INFO] Enabling automatic SSL certificate renewal..."
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# -------------------
# FINAL DIAGNOSTICS
# -------------------
echo "[INFO] Running diagnostics..."

# Check if Apache is running
echo "[INFO] Checking if Apache is running..."
if systemctl is-active --quiet apache2; then
    echo "[INFO] Apache is running."
else
    echo "[ERROR] Apache is NOT running!"
    exit 1
fi

# Check if PHP-FPM is running
echo "[INFO] Checking if PHP-FPM is running..."
if systemctl is-active --quiet php${PHP_VERSION}-fpm; then
    echo "[INFO] PHP-FPM is running."
else
    echo "[ERROR] PHP-FPM is NOT running!"
    exit 1
fi

# Check if SSL certificates are active
echo "[INFO] Checking if SSL certificates are active..."
sudo certbot certificates

# -------------------
# FINISH
# -------------------
echo "[INFO] WordPress site and reverse proxy setup complete! You can access your site at https://$DOMAIN"

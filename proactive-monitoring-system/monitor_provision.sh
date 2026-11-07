#  Zabbix 7.0 server on Ubuntu/Debian (MariaDB + Apache). Safe to re-run.
set -e
DB_PASS="ChangeMe_Str0ngPass"        # <-- edit (letters, digits, _ only)

 
# 1. MariaDB: install, secure, tune, create database
sudo apt-get update
sudo apt-get install -y wget mariadb-server

sudo mysql -e "DROP DATABASE IF EXISTS test; DROP USER IF EXISTS ''@'localhost'; DROP USER IF EXISTS 'root'@'%';"
printf '[mysqld]\nlog_bin_trust_function_creators=1\ncharacter-set-server=utf8mb4\ncollation-server=utf8mb4_bin\nbind-address=127.0.0.1\n' \
  > /etc/mysql/mariadb.conf.d/99-zabbix.cnf

sudo systemctl enable mariadb

sudo systemctl restart mariadb
sudo mysql <<SQL
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '$DB_PASS';
ALTER USER 'zabbix'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators=1;
SQL

. /etc/os-release       # to get OS $ID and $VERSION_ID for the Zabbix repo URL
# 2. Zabbix 7.0 repository + packages
if ! sudo dpkg -s zabbix-release >/dev/null 2>&1; then
  DEB="zabbix-release_7.0-1+ubuntu22.04_all.deb"
  sudo wget -q "https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/$DEB" -O /tmp/$DEB
  sudo dpkg -i /tmp/$DEB
  sudo apt-get update
fi
sudo apt-get install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts
 
# 3. Import schema (only once)
if [ "$(sudo mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='zabbix' AND table_name='dbversion'")" = "0" ]; then
  zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | sudo mysql --default-character-set=utf8mb4 zabbix
fi
 
# 4. Give the server the DB password
sed -i "s/^#\? *DBPassword=.*/DBPassword=$DB_PASS/" /etc/zabbix/zabbix_server.conf

sudo tee /etc/zabbix/zabbix_server.conf > /dev/null <<EOF
LogFile=/var/log/zabbix/zabbix_server.log
LogFileSize=0
DBHost=localhost
DBName=zabbix
DBUser=zabbix
DBPassword=$DB_PASS
DBSocket=/var/run/mysqld/mysqld.sock
SNMPTrapperFile=/var/log/snmp/snmptrap.log
Timeout=4
AlertScriptsPath=/usr/lib/zabbix/alertscripts
ExternalScripts=/usr/lib/zabbix/externalscripts
LogSlowQueries=300
StatsAllowedIP=127.0.0.1
EOF
# 5. Frontend config = what the setup wizard would write (so no wizard is needed)
if [ ! -f /etc/zabbix/web/zabbix.conf.php ]; then
  sudo tee /etc/zabbix/web/zabbix.conf.php > /dev/null <<'EOF'
<?php
$DB['TYPE']            = 'MYSQL';
$DB['SERVER']          = 'localhost';
$DB['PORT']            = '0';
$DB['DATABASE']        = 'zabbix';
$DB['USER']            = 'zabbix';
$DB['PASSWORD']        = '__DBPASS__';
$DB['SCHEMA']          = '';
$DB['ENCRYPTION']      = false;
$DB['KEY_FILE']        = '';
$DB['CERT_FILE']       = '';
$DB['CA_FILE']         = '';
$DB['VERIFY_HOST']     = false;
$DB['CIPHER_LIST']     = '';
$DB['VAULT']           = '';
$DB['VAULT_URL']       = '';
$DB['VAULT_DB_PATH']   = '';
$DB['VAULT_TOKEN']     = '';
$DB['VAULT_CERT_FILE'] = '';
$DB['VAULT_KEY_FILE']  = '';
$DB['DOUBLE_IEEE754']  = true;
$ZBX_SERVER_NAME       = '';
$IMAGE_FORMAT_DEFAULT  = IMAGE_FORMAT_PNG;
EOF
  sudo sed -i "s/__DBPASS__/$DB_PASS/" /etc/zabbix/web/zabbix.conf.php
  sudo chown www-data:www-data /etc/zabbix/web/zabbix.conf.php
  sudo chmod 640 /etc/zabbix/web/zabbix.conf.php
fi

# Run the auto-Discovery python script to configure the action
# Zabbix server actively scans a network range (IP:1-254) trying to ping or connect to ports
#sudo cp /vagrant/create_descovery_action.py /tmp/create_descovery_action.py
#python3 /tmp/create_descovery_action.py
#rm -f /tmp/create_descovery_action.py

# Run the auto-Registration python script to configure the action
# Zabbix server actively scans a network range (IP:1-254) trying to ping or connect to ports
cp /vagrant/setup_autoregistration.py /tmp/setup_autoregistration.py
ZBX_PASS='zabbix' python3 /tmp/setup_autoregistration.py
rm -f /tmp/setup_autoregistration.py


# 6. Start everything
sudo systemctl enable zabbix-server apache2 mariadb
sudo systemctl restart zabbix-server apache2 mariadb
sudo systemctl restart 'php*-fpm' 2>/dev/null || true
command -v ufw >/dev/null && { ufw allow 80/tcp; ufw allow 10051/tcp; } || true


# Install the Zabbix agent package
sudo apt-get install -y zabbix-agent

# ServerActive=127.0.0.1: Tells the agent where to send active check data.
# HostMetadata=Linux: matches the auto-registration action, it automatically links the active agent template.
CONF=/etc/zabbix/zabbix_agentd.conf
sudo sed -i 's/^Server=.*/Server=127.0.0.1/' $CONF
sudo sed -i 's/^ServerActive=.*/ServerActive=127.0.0.1/' $CONF
sudo sed -i 's/^Hostname=.*/Hostname=Zabbix server/' $CONF
sudo systemctl restart zabbix-agent

sudo systemctl restart zabbix-agent
sudo systemctl enable zabbix-agent


sudo apt update && sudo apt install -y fping
FPING_PATH="/usr/bin/fping"
sudo chown root:zabbix "$FPING_PATH"
sudo chmod 4710 "$FPING_PATH"
SERVER_CONF="/etc/zabbix/zabbix_server.conf"
sudo sed -i -E "s|^[#[:space:]]*FpingLocation=.*|FpingLocation=$FPING_PATH|" "$SERVER_CONF"


sudo systemctl restart zabbix-server
# if you have issue with starting the zabbix-server, try to run the following commands to fix the PidFile issue:
#grep -q '^PidFile=' /etc/zabbix/zabbix_server.conf \
#  || echo 'PidFile=/run/zabbix/zabbix_server.pid' | sudo tee -a /etc/zabbix/zabbix_server.conf
#sudo sed -i 's|^PidFile=.*|PidFile=/run/zabbix/zabbix_server.pid|' /etc/zabbix/zabbix_server.conf
#sudo mkdir -p /run/zabbix && sudo chown zabbix:zabbix /run/zabbix
#sudo systemctl daemon-reload
#time sudo systemctl start zabbix-server
#systemctl is-active zabbix-server



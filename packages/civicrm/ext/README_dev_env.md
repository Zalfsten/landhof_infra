# Required packaged (on debian)

```bash
sudo apt update && sudo apt install \
    composer \
    mariadb-server \
    php \
    php-bcmath \
    php-curl \
    php-gd \
    php-intl \
    php-mbstring \
    php-mysql \
    php-xml \
    php-zip
wget -qO /tmp/civicrm-standalone.zip https://github.com/civicrm/civicrm-standalone/archive/refs/heads/master.zip
sudo unzip /tmp/civicrm-standalone.zip -d /workspaces
sudo chown -R vscode:vscode /workspaces/civicrm-standalone-master
cd /workspaces/civicrm-standalone-master
composer install
mkdir -p bin
curl -L -o bin/cv https://github.com/civicrm/cv/releases/download/v0.3.67/cv-0.3.67.phar
curl -L -o bin/civix https://github.com/totten/civix/releases/download/v25.10.2/civix-25.10.2.phar
chmod +x bin/cv bin/civix
sudo mkdir -p /run/mysqld
sudo chown mysql:mysql /run/mysqld
sudo mysqld_safe --skip-grant-tables=0 --bind-address=127.0.0.1 &
sudo mysql <<SQL
CREATE DATABASE civicrm_standalone;
CREATE USER 'civiuser'@'127.0.0.1' IDENTIFIED BY 'secret';
GRANT ALL PRIVILEGES ON civicrm_standalone.* TO 'civiuser'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
ln -s /workspaces/landhof_infra/packages/civicrm/ext/de.feld-projekt.triggerbutton/ /workspaces/civicrm-standalone-master/ext/
php -S 0.0.0.0:8000
```

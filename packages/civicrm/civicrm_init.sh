#!/bin/sh
set -e

umask 0007

log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*" >&2;
}

get_var_or_secret() {
  var="$1"
  def="$2"
  secret_file="/run/secrets/$var"

  # 1. Secret vorhanden?
  if [ -s "$secret_file" ]; then
    cat "$secret_file"
    return 0
  fi

  # 2. Variable gesetzt und nicht leer?
  val=$(printenv "$var")
  if [ -n "$val" ]; then
    echo "$val"
    return 0
  fi

  # 3. Default Wert: Wenn gesetzt (egal ob leer oder nicht)
  if [ "${def+x}" ]; then
    log "WARN: $var not set, using default: '$def'"
    echo "$def"
    return 0
  fi

  # 4. Fehler
  log "ERRO: $var is not set and no default provided!"
  return 1
}

# Prüfen ob bereits installiert
if [ -f "/var/www/civicrm/private/civicrm.settings.php" ]; then
  log "INFO: CiviCRM already installed, skipping initialization"
  exit 0
fi

db_user="$(get_var_or_secret CIVICRM_DB_USER civicrm)"
db_password="$(get_var_or_secret CIVICRM_DB_PASSWORD civicrm)"
db_host="$(get_var_or_secret CIVICRM_DB_HOST db)"
db_name="$(get_var_or_secret CIVICRM_DB_NAME civicrm)"
uf_baseurl="$(get_var_or_secret CIVICRM_UF_BASEURL http://localhost)"
lang="$(get_var_or_secret CIVICRM_LANG de_DE)"
admin_user="$(get_var_or_secret CIVICRM_ADMIN_USER admin)"
admin_password="$(get_var_or_secret CIVICRM_ADMIN_PASSWORD admin)"
admin_email="$(get_var_or_secret CIVICRM_ADMIN_EMAIL admin@example.com)"
site_key="$(get_var_or_secret CIVICRM_SITE_KEY '')"
cred_keys="$(get_var_or_secret CIVICRM_CRED_KEYS '')"
sign_keys="$(get_var_or_secret CIVICRM_SIGN_KEYS '')"

log "INFO: Initializing CiviCRM..."
tar -xf /usr/share/civicrm/civicrm.tar.gz -C /var/www/civicrm/ --strip-components=1

log "INFO: Running cv core:install..."
cv core:install -K -n \
  --url="${uf_baseurl}" \
  --db="mysql://${db_user}:${db_password}@${db_host}:3306/${db_name}" \
  --lang="${lang}" \
  -m extras.adminUser="${admin_user}" \
  -m extras.adminPass="${admin_password}" \
  -m extras.adminEmail="${admin_email}"

chmod 440 /var/www/civicrm/private/civicrm.settings.php

if [ -z "$site_key" ]; then
  log "INFO: Patching CIVICRM_SITE_KEY in civicrm.settings.php ..."
  sed -i "s/define('CIVICRM_SITE_KEY'.*/define('CIVICRM_SITE_KEY', '${site_key}');/" /var/www/civicrm/private/civicrm.settings.php
fi
if [ -z "$cred_keys" ]; then
  log "INFO: Patching CIVICRM_CRED_KEYS in civicrm.settings.php ..."
  sed -i "s/define('CIVICRM_CRED_KEYS'.*/define('CIVICRM_CRED_KEYS', '${cred_keys}');/" /var/www/civicrm/private/civicrm.settings.php
fi
if [ -z "$sign_keys" ]; then
  log "INFO: Patching CIVICRM_SIGN_KEYS in civicrm.settings.php ..."
  sed -i "s/define('CIVICRM_SIGN_KEYS'.*/define('CIVICRM_SIGN_KEYS', '${sign_keys}');/" /var/www/civicrm/private/civicrm.settings.php
fi

log "INFO: Installation completed, configuring additional settings..."
cv api4 Setting.set +v debug_enabled=0
cv api4 Setting.set +v backtrace=0
cv api4 Setting.set +v enableSSL=1
cv api4 Setting.set +v verifySSL=1
# cv api4 Setting.set +v communityMessagesUrl=''
# cv api4 Setting.set +v ext_repo_url=''

# Grant read permissions to user webserver
setfacl -R -m u:webserver:rx /var/www/civicrm
# Grant write permissions to user webserver
setfacl -R -m u:webserver:rwx /var/www/civicrm/public
setfacl -R -m u:webserver:rwx /var/www/civicrm/private
setfacl -R -m u:webserver:rwx /var/www/civicrm/ext
# Ensure all new file in the folder also gain write permissions for user webserver
setfacl -R -d -m u:webserver:rwx /var/www/civicrm/public
setfacl -R -d -m u:webserver:rwx /var/www/civicrm/private
setfacl -R -d -m u:webserver:rwx /var/www/civicrm/ext
# Set group permissions to rwx to mimic POSIX permissions
setfacl -R -m g::rwx /var/www/civicrm
log "INFO: CiviCRM installation completed successfully!"

if [ $# -ne 0 ]; then
  log "INFO: Executing command: $*"
  exec "$@"
fi
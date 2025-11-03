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

MODE="$1"
shift || true

if [ "$MODE" = "init" ]; then
  # Prüfen ob bereits installiert
  if [ -f "/var/www/html/private/civicrm.settings.php" ]; then
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
  rsync -a /usr/share/civicrm/ /var/www/html/

  log "INFO: Running cv core:install..."
  cv core:install -K -n \
    --url="${uf_baseurl}" \
    --db="mysql://${db_user}:${db_password}@${db_host}:3306/${db_name}" \
    --lang="${lang}" \
    -m extras.adminUser="${admin_user}" \
    -m extras.adminPass="${admin_password}" \
    -m extras.adminEmail="${admin_email}"

  chmod 440 /var/www/html/private/civicrm.settings.php

  if [ -z "$site_key" ]; then
    log "INFO: Patching CIVICRM_SITE_KEY in civicrm.settings.php ..."
    sed -i "s/define('CIVICRM_SITE_KEY'.*/define('CIVICRM_SITE_KEY', '${site_key}');/" /var/www/html/private/civicrm.settings.php
  fi
  if [ -z "$cred_keys" ]; then
    log "INFO: Patching CIVICRM_CRED_KEYS in civicrm.settings.php ..."
    sed -i "s/define('CIVICRM_CRED_KEYS'.*/define('CIVICRM_CRED_KEYS', '${cred_keys}');/" /var/www/html/private/civicrm.settings.php
  fi
  if [ -z "$sign_keys" ]; then
    log "INFO: Patching CIVICRM_SIGN_KEYS in civicrm.settings.php ..."
    sed -i "s/define('CIVICRM_SIGN_KEYS'.*/define('CIVICRM_SIGN_KEYS', '${sign_keys}');/" /var/www/html/private/civicrm.settings.php
  fi

  log "INFO: Installation completed, configuring additional settings..."
  cv api4 Setting.set +v debug_enabled=0
  cv api4 Setting.set +v backtrace=0
  cv api4 Setting.set +v enableSSL=1
  cv api4 Setting.set +v verifySSL=1
  cv api4 Setting.set +v communityMessagesUrl=''
  cv api4 Setting.set +v ext_repo_url=''

  echo 'CiviCRM installation completed successfully!'
elif [ "$MODE" = "fpm" ]; then
  log "INFO: Generating PHP-FPM health check script..."
  
  # Read FPM config values
  config=/etc/php/php-fpm.d/zzz-civicrm.conf
  listen=$(grep -E "^\s*listen\s*=" $config | sed 's/.*=\s*//' | tr -d ' ')
  listen=${listen:-"[::]:9000"}
  ping_path=$(grep -E "^\s*ping\.path\s*=" $config | sed 's/.*=\s*//' | tr -d ' ')
  pong=$(grep -E "^\s*ping\.response\s*=" $config | sed 's/.*=\s*//' | tr -d ' ')
  pong=${pong:-'pong'}

  if [ -z "$ping_path" ]; then
    log "ERRO: ping.path not configured in PHP-FPM config $config"
    exit 1
  fi
  
  if echo "$listen" | grep -q '^/'; then
    socket_type="unix"
  else
    socket_type="tcp"
  fi

cat > /tmp/php-fpm-healthcheck.php << HEALTHCHECK_EOF
<?php
\$socketType = '$socket_type';
\$listen = '$listen';
\$pingPath = '$ping_path';
\$pong = '$pong';

\$fcgi = @stream_socket_client(\$socketType . "://" . \$listen, \$errno, \$errstr, 1);
if (!\$fcgi) {
    fwrite(STDERR, "ERROR: Cannot connect to PHP-FPM socket: \$errstr (\$errno)\n");
    exit(1);
}

/**
 * FastCGI protocol constants
 */
define('FCGI_VERSION_1', 1);
define('FCGI_BEGIN_REQUEST', 1);
define('FCGI_PARAMS', 4);
define('FCGI_STDIN', 5);

function fcgi_record(\$type, \$content, \$requestId = 1) {
    \$len = strlen(\$content);
    \$pad = (\$len % 8) ? 8 - (\$len % 8) : 0;
    return pack('CCnnCC', FCGI_VERSION_1, \$type, \$requestId, \$len, \$pad, 0)
        . \$content
        . str_repeat("\x00", \$pad);
}

// BEGIN_REQUEST
\$begin = pack('nC6', 1, 0, 0, 0, 0, 0, 0);
\$packet = fcgi_record(FCGI_BEGIN_REQUEST, \$begin);

// Minimal environment
\$params = [
    'SCRIPT_FILENAME' => '/var/www/html/index.php',
    'SCRIPT_NAME'     => \$pingPath,
    'REQUEST_METHOD'  => 'GET',
    'SERVER_PROTOCOL' => 'HTTP/1.1',
];
foreach (\$params as \$k => \$v) {
    \$packet .= fcgi_record(FCGI_PARAMS, chr(strlen(\$k)) . chr(strlen(\$v)) . \$k . \$v);
}
// End of PARAMS and STDIN
\$packet .= fcgi_record(FCGI_PARAMS, '');
\$packet .= fcgi_record(FCGI_STDIN, '');

// Send and read response
fwrite(\$fcgi, \$packet);
\$response = stream_get_contents(\$fcgi, 8192);
fclose(\$fcgi);

// Check for FastCGI response
if (\$response === false || strlen(\$response) === 0) {
    fwrite(STDERR, "PHP-FPM did not respond\n");
    exit(1);
}

// Check for correct response
if (strpos(\$response, \$pong) !== false) {
    exit(0);
}

fwrite(STDERR, "Invalid PHP-FPM response\n");
exit(1);
HEALTHCHECK_EOF

  chmod +x /tmp/php-fpm-healthcheck.php
  
  log "INFO: Starting php-fpm..."
  exec /usr/sbin/php-fpm "$@"
elif [ "$MODE" = "supercronic" ]; then
  log "INFO: Generating supercronic crontab..."
  
  # Create crontab for supercronic
  cat > /tmp/crontab << 'CRONTAB_EOF'
*/5 * * * * cv core:cron
CRONTAB_EOF
  
  log "INFO: Starting supercronic..."
  exec /usr/local/bin/supercronic /tmp/crontab
else
  log "INFO: Executing custom command: $MODE $@"
  exec "$MODE" "$@"
fi

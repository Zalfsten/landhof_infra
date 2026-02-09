#!/bin/sh
set -e

log() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*" >&2;
}

log "INFO: Gathering PHP-FPM health check parameters..."

# Read FPM config values
config=/etc/php/php-fpm.d/zzz-civicrm.conf
listen=$(grep -E "^\s*listen\s*=" $config | sed 's/.*=\s*//' | tr -d ' ')
# Listen-Adresse ggf. anpassen
if echo "$listen" | grep -q '^\[::\]:'; then
  listen="localhost:${listen#\[::\]:}"
fi
listen=${listen:-"localhost:9000"}

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

echo "$socket_type $listen $ping_path $pong" > /tmp/healthcheck.args

if [ $# -ne 0 ]; then
  log "INFO: Executing command: $*"
  exec "$@"
fi

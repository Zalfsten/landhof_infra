FROM civicrm/civicrm:6.7.1

# Create civicrm system user to own source files, so they are not writable by www-data
RUN adduser --system --shell /bin/bash civicrm && \
    chown -R civicrm:nogroup /var/www/html/core /var/www/html/civicrm.standalone.php /var/www/html/index.php /var/www/html/.htaccess && \
    curl -fsSL -o /usr/local/bin/supercronic https://github.com/aptible/supercronic/releases/download/v0.2.29/supercronic-linux-amd64 && \
    chmod +x /usr/local/bin/supercronic && \
    echo '*/5 * * * * echo "$(date) running cv core:cron" && cv core:cron 2>&1' > /tmp/crontab

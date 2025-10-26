FROM civicrm/civicrm:6.7.1

ENV CRONTAB='*/5 * * * * cv core:cron'

# Create civicrm system user to own source files, so they are not writable by www-data
RUN adduser --system --shell /bin/bash civicrm && \
    chown -R civicrm:nogroup /var/www/html/core /var/www/html/civicrm.standalone.php /var/www/html/index.php /var/www/html/.htaccess && \
    curl -fsSL -o /usr/local/bin/supercronic https://github.com/aptible/supercronic/releases/download/v0.2.29/supercronic-linux-amd64 && \
    chmod +x /usr/local/bin/supercronic

# Create entrypoint script for cron service, using CRONTAB env variable
RUN echo '#!/bin/sh' > /run-cron.sh && \
    echo 'echo "$CRONTAB" > /tmp/crontab' >> /run-cron.sh && \
    echo 'exec /usr/local/bin/supercronic -passthrough-logs /tmp/crontab' >> /run-cron.sh && \
    chmod +x /run-cron.sh

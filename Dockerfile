FROM civicrm/civicrm:6.7.1

# Create non-root user for running supercronic
RUN mkdir -p /usr/local/bin && \
    curl -fsSL -o /usr/local/bin/supercronic https://github.com/aptible/supercronic/releases/download/v0.2.29/supercronic-linux-amd64 && \
    chmod +x /usr/local/bin/supercronic && \
    echo "*/5 * * * * cv core:cron" > /tmp/crontab

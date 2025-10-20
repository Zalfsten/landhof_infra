FROM cgr.dev/chainguard/wolfi-base:latest

# Install required packages
RUN apk update && apk add --no-cache \
    busybox \
    ca-certificates \
    curl

# Install supercronic (cron alternative that works as non-root)
RUN mkdir -p /usr/local/bin && \
    curl -fsSL -o /usr/local/bin/supercronic https://github.com/aptible/supercronic/releases/download/v0.2.29/supercronic-linux-amd64 && \
    chmod +x /usr/local/bin/supercronic

# Create entrypoint script that handles everything at runtime
RUN echo '#!/bin/sh' > /entrypoint.sh && \
    echo 'if [ -n "$CRONTAB" ]; then' >> /entrypoint.sh && \
    echo '  echo "$CRONTAB" > /tmp/crontab' >> /entrypoint.sh && \
    echo 'else' >> /entrypoint.sh && \
    echo '  echo "# Empty crontab" > /tmp/crontab' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo 'exec supercronic /tmp/crontab' >> /entrypoint.sh >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Switch to cron user
USER cron

# Add healthcheck to verify supercronic is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep supercronic > /dev/null || exit 1

ENTRYPOINT ["/entrypoint.sh"]
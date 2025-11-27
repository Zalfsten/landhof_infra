#!/bin/bash
set -e

TRIGGER_FILE="/run/aqbanking/trigger"
LOCK_FILE="/tmp/fetch.lock"

# Ensure trigger directory exists (it should be a volume, but good to check)
mkdir -p "$(dirname "$TRIGGER_FILE")"
touch "$TRIGGER_FILE"

echo "Starting transaction fetcher service..."
echo "Watching $TRIGGER_FILE for changes..."

while true; do
    # Wait for the trigger file to be written to
    inotifywait -e close_write "$TRIGGER_FILE"
    
    if [ -f "$LOCK_FILE" ]; then
        echo "Fetch already in progress. Skipping."
        continue
    fi
    
    touch "$LOCK_FILE"
    echo "Trigger received. Starting transaction fetch..."
    
    # Fetch transactions with aqbanking
    # Assuming configuration is mounted in $HOME/.aqbanking
    echo "Running aqbanking-cli request..."
    # aqbanking-cli request --account=... # User needs to configure this
    # For now, we'll just log it.
    
    # Import to CiviCRM
    echo "Importing to CiviCRM..."
    # cv api4 BankingTransaction.import ...
    
    echo "Transaction fetch completed."
    rm -f "$LOCK_FILE"
done

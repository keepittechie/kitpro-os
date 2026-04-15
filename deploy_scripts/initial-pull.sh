#!/bin/bash
set -euo pipefail

REMOTE_USER="josh"
REMOTE_HOST="10.10.0.12"
REMOTE_PATH="/opt/publisher/app"
LOCAL_PATH="$HOME/Documents/GitHub/publisher-app"

echo "==> Creating local directory..."
mkdir -p "$LOCAL_PATH"

echo "==> Pulling initial site copy from $REMOTE_HOST..."
rsync -avzh \
  --exclude node_modules \
  --exclude .next \
  --exclude .env \
  "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/" \
  "$LOCAL_PATH/"

echo "Initial sync complete"
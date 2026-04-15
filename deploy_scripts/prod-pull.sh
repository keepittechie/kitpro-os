#!/bin/bash
set -euo pipefail

REMOTE_USER="josh"
REMOTE_HOST="10.10.0.12"
REMOTE_PATH="/opt/publisher/app"
LOCAL_PATH="$HOME/Documents/GitHub/publisher-app"

mkdir -p "$LOCAL_PATH"

echo "==> Pulling site from $REMOTE_HOST..."
rsync -avzh \
  --exclude node_modules \
  --exclude .next \
  --exclude .env \
  "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/" \
  "$LOCAL_PATH/"

echo "Pull complete: $REMOTE_HOST -> $LOCAL_PATH"
#!/bin/bash
set -euo pipefail

REMOTE_USER="josh"
REMOTE_HOST="10.10.0.15"
REMOTE_PATH="/home/josh/kitpro-os"
LOCAL_PATH="$HOME/Documents/GitHub/kitpro-os"

echo "==> Syncing files to remote..."
rsync -avzh --no-group --no-perms --omit-dir-times --no-times \
  --exclude deploy_scripts \
  --exclude iso \
  --exclude .gitignore \
  "$LOCAL_PATH/" \
  "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/"

echo "Deploy complete"
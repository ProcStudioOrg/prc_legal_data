#!/usr/bin/env bash
# =============================================================================
# Deploy Script — Run from your LOCAL machine to deploy to the VPS
# Usage: ./infra/deploy.sh
# =============================================================================
set -euo pipefail

VPS_HOST="${DEPLOY_HOST:-brpl@168.231.90.14}"
APP_NAME="legal_data_api"
APP_DIR="/home/brpl/${APP_NAME}"
BRANCH="${DEPLOY_BRANCH:-main}"

echo "=== Deploying ${BRANCH} to ${VPS_HOST} ==="

ssh "${VPS_HOST}" bash <<REMOTE
  set -euo pipefail
  export PATH="\$HOME/.rbenv/bin:\$HOME/.rbenv/shims:\$PATH"
  cd ${APP_DIR}

  echo "--- Pulling latest code ---"
  git fetch origin
  git reset --hard origin/${BRANCH}

  echo "--- Installing dependencies ---"
  bundle install --deployment --without development test

  echo "--- Running migrations ---"
  RAILS_ENV=production bin/rails db:migrate

  echo "--- Restarting app ---"
  sudo systemctl restart ${APP_NAME}

  echo "--- Verifying ---"
  sleep 2
  if sudo systemctl is-active --quiet ${APP_NAME}; then
    echo "Deploy successful — ${APP_NAME} is running"
  else
    echo "ERROR: ${APP_NAME} failed to start"
    sudo journalctl -u ${APP_NAME} --no-pager -n 20
    exit 1
  fi
REMOTE

echo "=== Deploy complete ==="

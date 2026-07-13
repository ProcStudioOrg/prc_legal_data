#!/usr/bin/env bash
# =============================================================================
# Deploy Script — Run from your LOCAL machine to deploy to the VPS
# Usage: ./infra/deploy.sh
# =============================================================================
set -euo pipefail

VPS_HOST="${DEPLOY_HOST:-brpl@168.231.90.14}"
APP_NAME="legal_data_api"
APP_DIR="/home/brpl/code/prc_legal_data"
BRANCH="${DEPLOY_BRANCH:-main}"

echo "=== Deploying ${BRANCH} to ${VPS_HOST} ==="

ssh "${VPS_HOST}" bash <<REMOTE
  set -euo pipefail
  export PATH="\$HOME/.rbenv/bin:\$HOME/.rbenv/shims:\$PATH"
  cd ${APP_DIR}

  echo "--- Pulling latest code ---"
  git fetch origin
  git reset --hard origin/${BRANCH}

  echo "--- Stamping REVISION ---"
  printf '{"commit":"%s","branch":"%s","deployed_at":"%s"}\n' \
    "\$(git rev-parse --short HEAD)" \
    "${BRANCH}" \
    "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" > REVISION
  cat REVISION

  echo "--- Installing dependencies ---"
  bundle install --deployment --without development test

  echo "--- Running migrations ---"
  RAILS_ENV=production bin/rails db:migrate

  echo "--- Restarting app ---"
  sudo systemctl restart ${APP_NAME}

  echo "--- Verifying ---"
  sleep 2
  if ! sudo systemctl is-active --quiet ${APP_NAME}; then
    echo "ERROR: ${APP_NAME} failed to start"
    sudo journalctl -u ${APP_NAME} --no-pager -n 20
    exit 1
  fi

  # A versão servida tem que bater com o commit que acabamos de gravar.
  expected=\$(git rev-parse --short HEAD)
  live=\$(curl -sf --retry 5 --retry-delay 2 --retry-all-errors \
    http://127.0.0.1:3000/api/v1/version | grep -o '"commit":"[^"]*"' | cut -d'"' -f4)

  if [ "\$live" != "\$expected" ]; then
    echo "ERROR: versão servida (\$live) != commit implantado (\$expected)"
    sudo journalctl -u ${APP_NAME} --no-pager -n 20
    exit 1
  fi

  echo "Deploy successful — ${APP_NAME} rodando no commit \$live"
REMOTE

echo "=== Deploy complete ==="

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

  # Solid Queue roda dentro do Puma (plugin gateado por SOLID_QUEUE_IN_PUMA).
  grep -q '^SOLID_QUEUE_IN_PUMA=' .env || echo 'SOLID_QUEUE_IN_PUMA=1' >> .env

  # db:migrate não carrega db/queue_schema.rb, e o banco "queue" é o mesmo
  # banco físico do primário — carga manual, só no primeiro deploy.
  if ! RAILS_ENV=production bin/rails runner 'ActiveRecord::Base.connection.table_exists?(:solid_queue_jobs) or exit 1' >/dev/null 2>&1; then
    echo "--- Loading Solid Queue schema (first deploy) ---"
    # O check de ambiente protegido barra schema:load em produção; o
    # queue_schema.rb só cria tabelas solid_queue_*, é seguro.
    DISABLE_DATABASE_ENVIRONMENT_CHECK=1 RAILS_ENV=production bin/rails db:schema:load:queue
  fi

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

  # Sem worker do Solid Queue nada do DJEN roda — avisa, mas não derruba o deploy.
  sleep 3
  if ! RAILS_ENV=production bin/rails runner 'SolidQueue::Process.where("last_heartbeat_at > ?", 2.minutes.ago).exists? or exit 1' >/dev/null 2>&1; then
    echo "AVISO: nenhum processo Solid Queue com heartbeat recente — jobs DJEN não vão rodar (verifique SOLID_QUEUE_IN_PUMA no .env)"
  fi

  echo "Deploy successful — ${APP_NAME} rodando no commit \$live"
REMOTE

echo "=== Deploy complete ==="

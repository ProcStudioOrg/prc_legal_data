#!/usr/bin/env bash
# =============================================================================
# Server Setup Script — Run ONCE on a fresh Hostinger VPS (Ubuntu 22.04/24.04)
# Usage: ssh brpl@YOUR_VPS_IP 'bash -s' < infra/setup_server.sh
# =============================================================================
set -euo pipefail

APP_NAME="legal_data_api"
APP_DIR="/home/brpl/code/prc_legal_data"
RUBY_VERSION="3.4.7"
DB_NAME="${APP_NAME}_development"
DB_USER="${APP_NAME}"

echo "=== 1. System packages ==="
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
  build-essential git curl wget libssl-dev libreadline-dev zlib1g-dev \
  libpq-dev libffi-dev libyaml-dev libgmp-dev \
  postgresql postgresql-contrib \
  nginx certbot python3-certbot-nginx \
  logrotate

echo "=== 2. Install rbenv + ruby-build ==="
if [ ! -d "$HOME/.rbenv" ]; then
  git clone https://github.com/rbenv/rbenv.git ~/.rbenv
  git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

  echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
  echo 'eval "$(rbenv init -)"' >> ~/.bashrc
fi

export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

echo "=== 3. Install Ruby ${RUBY_VERSION} ==="
if ! rbenv versions | grep -q "${RUBY_VERSION}"; then
  rbenv install "${RUBY_VERSION}"
fi
rbenv global "${RUBY_VERSION}"
gem install bundler --no-document

echo "=== 4. Setup PostgreSQL ==="
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 || \
  sudo -u postgres createuser -s "${DB_USER}"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 || \
  sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"

# Set password from environment or prompt
if [ -n "${DB_PASSWORD:-}" ]; then
  sudo -u postgres psql -c "ALTER USER ${DB_USER} PASSWORD '${DB_PASSWORD}';"
  echo "Database password set from environment variable."
else
  echo "WARNING: Set the database password manually:"
  echo "  sudo -u postgres psql -c \"ALTER USER ${DB_USER} PASSWORD 'your_password';\""
fi

echo "=== 5. Clone repository ==="
if [ ! -d "${APP_DIR}" ]; then
  mkdir -p /home/brpl/code
  git clone git@github.com:brpl20/prc_legal_data.git "${APP_DIR}"
else
  echo "Repository already exists at ${APP_DIR}"
fi

echo "=== 6. Create .env file template ==="
ENV_FILE="${APP_DIR}/.env"
if [ ! -f "${ENV_FILE}" ]; then
  cat > "${ENV_FILE}" <<'ENVEOF'
RAILS_ENV=production
RAILS_LOG_LEVEL=info
LEGAL_DATA_API_DATABASE_PASSWORD=CHANGE_ME
SECRET_KEY_BASE=GENERATE_WITH_bin_rails_secret
PORT=3000
WEB_CONCURRENCY=2
RAILS_MAX_THREADS=5
ENVEOF
  chmod 600 "${ENV_FILE}"
  echo "Created ${ENV_FILE} — edit it with real values before deploying."
else
  echo ".env already exists"
fi

echo "=== 7. Install dependencies ==="
cd "${APP_DIR}"
bundle config set --local deployment true
bundle config set --local without 'development test'
bundle install

echo "=== 8. Install systemd service ==="
sudo cp "${APP_DIR}/infra/legal_data_api.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable "${APP_NAME}"

echo "=== 9. Install NGINX config ==="
sudo cp "${APP_DIR}/infra/nginx/legal_data_api.conf" /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/legal_data_api.conf /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

echo "=== 10. Setup log rotation ==="
sudo tee /etc/logrotate.d/${APP_NAME} > /dev/null <<LOGEOF
${APP_DIR}/log/*.log {
  daily
  missingok
  rotate 14
  compress
  delaycompress
  notifempty
  copytruncate
}
LOGEOF

echo ""
echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Edit ${ENV_FILE} with real values"
echo "     - Set LEGAL_DATA_API_DATABASE_PASSWORD"
echo "     - Run: cd ${APP_DIR} && bin/rails secret"
echo "       and set SECRET_KEY_BASE"
echo "  2. Restore the database dump:"
echo "     gunzip -c legal_data_api_dump.sql.gz | psql ${DB_NAME}"
echo "  3. Run migrations: bin/rails db:migrate"
echo "  4. Start the app: sudo systemctl start ${APP_NAME}"
echo "  5. (Optional) Setup SSL:"
echo "     sudo certbot --nginx -d yourdomain.com"
echo ""

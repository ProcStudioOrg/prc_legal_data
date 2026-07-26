#!/usr/bin/env bash
#
# last_oab_por_estado.sh — varre a última OAB registrada em cada UF.
# Mostra, de uma só vez, onde a coleta parou em cada estado.
#
# Uso:
#   API_KEY=xxxxx ./infra/last_oab_por_estado.sh
#   ./infra/last_oab_por_estado.sh --base http://localhost:3000/api/v1
#
# Env:
#   API_KEY   (obrigatório) key ativa — X-API-KEY. `read` basta (rota é GET).
#   BASE_URL  (opcional)    default https://procstudio.api.br/api/v1
#
set -euo pipefail

BASE_URL="${BASE_URL:-https://procstudio.api.br/api/v1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE_URL="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "arg desconhecido: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${API_KEY:-}" ]]; then
  echo "erro: defina API_KEY (X-API-KEY). Ex: API_KEY=xxxx $0" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "erro: jq não instalado (brew install jq)" >&2; exit 1; }

STATES=(AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO)

printf '%-3s | %-12s | %-10s | %-9s | %s\n' "UF" "ÚLTIMA OAB" "Nº OAB" "TOTAL" "ATUALIZADO"
printf -- '----+--------------+------------+-----------+---------------------\n'

for uf in "${STATES[@]}"; do
  resp="$(curl -sS -H "X-API-KEY: ${API_KEY}" "${BASE_URL}/lawyer/state/${uf}/last" || echo '{}')"

  # erro de auth/servidor → sinaliza e segue
  if echo "$resp" | jq -e 'has("error")' >/dev/null 2>&1; then
    printf '%-3s | %s\n' "$uf" "ERRO: $(echo "$resp" | jq -r '.error')"
    continue
  fi

  read -r last num total upd < <(echo "$resp" | jq -r '
    [ (.last_oab      // "-"),
      (.oab_number    // "-"),
      (.total_lawyers // 0),
      (.updated_at    // "-") ] | @tsv')

  printf '%-3s | %-12s | %-10s | %-9s | %s\n' "$uf" "$last" "$num" "$total" "$upd"
done

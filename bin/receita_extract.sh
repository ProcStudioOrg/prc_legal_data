#!/bin/bash
# bin/receita_extract.sh <data.zip> <saida.ndjson> [cnae=6911701]
# Filtra do dump do OpenCNPJ só os estabelecimentos do CNAE pedido, shard a
# shard, sem materializar os ~124 GB descompactados. Mesma receita do
# extract_advocacia.sh usado no Mac em 2026-10 (987 shards, ~20 min).
# Sem set -e: grep sem match devolve 1 em shard sem advocacia.
set -uo pipefail
ZIP="$1"; OUT="$2"; CNAE="${3:-6911701}"

unzip -Z1 "$ZIP" > /dev/null || { echo "ERRO: zip ausente ou corrompido: $ZIP" >&2; exit 1; }
total=$(unzip -Z1 "$ZIP" | wc -l | tr -d ' ')
[ "$total" -gt 0 ] || { echo "ERRO: zip sem shards: $ZIP" >&2; exit 1; }

TMP="$OUT.tmp"
: > "$TMP"
n=0
while IFS= read -r member; do
  unzip -p "$ZIP" "$member" | grep -F -- "\"cnae_principal\":\"$CNAE\"" >> "$TMP"
  st=("${PIPESTATUS[@]}")
  if [ "${st[0]}" -ne 0 ]; then echo "ERRO unzip $member (status ${st[0]})" >&2; rm -f "$TMP"; exit 1; fi
  n=$((n+1))
  if [ $((n % 100)) -eq 0 ]; then echo "$(date +%H:%M:%S) shards=$n linhas=$(wc -l < "$TMP")"; fi
done < <(unzip -Z1 "$ZIP")
mv "$TMP" "$OUT"
echo "FIM shards=$total linhas=$(wc -l < "$OUT" | tr -d ' ')"

#!/bin/bash
# bin/receita_extract.sh <data.zip> <saida.ndjson> [cnae=6911701]
# Filtra do dump do OpenCNPJ só os estabelecimentos do CNAE pedido, shard a
# shard, sem materializar os ~124 GB descompactados. Mesma receita do
# extract_advocacia.sh usado no Mac em 2026-10 (987 shards, ~20 min).
set -uo pipefail
ZIP="$1"; OUT="$2"; CNAE="${3:-6911701}"
: > "$OUT"
n=0
unzip -Z1 "$ZIP" | while read -r member; do
  unzip -p "$ZIP" "$member" | grep "\"cnae_principal\":\"$CNAE\"" >> "$OUT"
  n=$((n+1))
  if [ $((n % 100)) -eq 0 ]; then echo "$(date +%H:%M:%S) shards=$n linhas=$(wc -l < "$OUT")"; fi
done
echo "FIM shards=$(unzip -Z1 "$ZIP" | wc -l | tr -d ' ') linhas=$(wc -l < "$OUT" | tr -d ' ')"

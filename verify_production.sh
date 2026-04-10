#!/bin/bash
# Verify face match links via production API
# Usage: ./verify_production.sh

API="https://procstudio.api.br/api/v1/lawyer"
KEY="36428adec80fcd239f3433f0b5fbfdbd6c5c69bd50eeda3e"
PASS=0
FAIL=0

check() {
  local oab=$1
  local expect_field=$2
  local expect_value=$3
  local desc=$4

  local resp=$(curl -s "$API/$oab" -H "X-API-KEY: $KEY")
  local actual=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print($expect_field)" 2>/dev/null)

  if [ "$actual" = "$expect_value" ]; then
    echo "  ✓ $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected: $expect_value, got: $actual)"
    FAIL=$((FAIL+1))
  fi
}

check_supps_count() {
  local oab=$1
  local min_count=$2
  local desc=$3

  local resp=$(curl -s "$API/$oab?include_supplementaries=true" -H "X-API-KEY: $KEY")
  local count=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('supplementaries', [])))" 2>/dev/null)

  if [ "$count" -ge "$min_count" ] 2>/dev/null; then
    echo "  ✓ $desc ($count supplementaries)"
    PASS=$((PASS+1))
  else
    echo "  ✗ $desc (expected >= $min_count, got: $count)"
    FAIL=$((FAIL+1))
  fi
}

check_not_linked_to() {
  local oab=$1
  local not_principal_oab=$2
  local desc=$3

  local resp=$(curl -s "$API/$oab" -H "X-API-KEY: $KEY")
  local principal=$(echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); p=d.get('principal',d); print(p.get('oab_id',''))" 2>/dev/null)

  if [ "$principal" != "$not_principal_oab" ]; then
    echo "  ✓ $desc"
    PASS=$((PASS+1))
  else
    echo "  ✗ $desc (is incorrectly linked to $not_principal_oab)"
    FAIL=$((FAIL+1))
  fi
}

echo "=== SINGLES: Known linked groups ==="

echo ""
echo "DAVID SOMBRA PEIXOTO (CE_16477 -> 19 supps)"
check_supps_count "CE_16477" 19 "CE_16477 has >= 19 supplementaries"

echo ""
echo "GUSTAVO DAL BOSCO"
check_supps_count "RS_54023" 10 "RS_54023 has >= 10 supplementaries"

echo ""
echo "CAROLINA LOUZADA PETRARCA"
check_supps_count "DF_16535" 10 "DF_16535 has >= 10 supplementaries"

echo ""
echo "ADAHILTON DE OLIVEIRA PINHO (batch 21-50)"
check_supps_count "SP_152305" 15 "SP_152305 has >= 15 supplementaries"

echo ""
echo "FRANCISCO ANTONIO FRAGATA JUNIOR"
check_supps_count "SP_39768" 10 "SP_39768 has >= 10 supplementaries"

echo ""
echo "=== EDGE CASES: Multi-person groups ==="

echo ""
echo "PAULO ROBERTO DOS SANTOS (2 people)"
check_supps_count "DF_11837" 1 "Pessoa 1: DF_11837 has supplementaries"
check_supps_count "MG_171899" 3 "Pessoa 2: MG_171899 has >= 3 supplementaries"
check_not_linked_to "PR_33243" "DF_11837" "PR_33243 NOT linked to DF_11837 (wrong person)"

echo ""
echo "CARLOS ALBERTO FERNANDES (3 people)"
check_supps_count "MG_762" 1 "Pessoa 2: MG_762 has supplementaries"
check_supps_count "MS_7248" 1 "Pessoa 3: MS_7248 has supplementaries"
check_not_linked_to "SP_57203" "DF_42173" "SP_57203 NOT linked to DF_42173 (wrong person)"

echo ""
echo "ADRIANO SANTOS DE ALMEIDA (2 people)"
check_supps_count "AC_6640" 10 "Pessoa 2: AC_6640 has >= 10 supplementaries"

echo ""
echo "=========================================="
echo "  PASSED: $PASS"
echo "  FAILED: $FAIL"
echo "=========================================="

if [ $FAIL -eq 0 ]; then
  echo "  ALL GOOD!"
else
  echo "  SOME CHECKS FAILED"
  exit 1
fi

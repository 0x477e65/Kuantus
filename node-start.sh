#!/usr/bin/env bash
# ==============================================================
# Quantus Node Autorestart (tmux session: quantus-node)
# Używa Twojej oryginalnej, działającej komendy startowej
# ==============================================================

unset TMUX
set -euo pipefail

# ---------------- CONFIG ----------------
NODENAME="Kurwa"
CHAIN="schrodinger"
BASE_PATH="/var/lib/quantus"
CHAIN_DIR="/root/chain"
NODE_KEY_FILE="$CHAIN_DIR/node-key"
LOG_FILE="$BASE_PATH/node.log"
SEED_FILE="/root/seed.txt"
# -----------------------------------------

mkdir -p "$BASE_PATH"
touch "$LOG_FILE"

# ===== Pobranie rewards-address =====
if [[ ! -s "$SEED_FILE" ]]; then
  echo "❌ Brak pliku $SEED_FILE" >&2
  exit 1
fi

REWARDS_ADDR=$(grep -m1 -E "^ *SS58 Address" "$SEED_FILE" \
  | sed -E 's/^ *SS58 Address:[[:space:]]*//; s/[[:space:]]//g')

if [[ -z "$REWARDS_ADDR" ]]; then
  echo "❌ Nie znaleziono SS58 Address w $SEED_FILE" >&2
  exit 1
fi

# Zabicie starej sesji (jeśli istnieje)
tmux kill-session -t quantus-node 2>/dev/null || true

# ===== Komenda startowa (Twoja oryginalna) =====
NODE_CMD=$(cat <<EOF
echo "[\$(date -Is)] ▶️ Start quantus-node (name: $NODENAME)" | tee -a $LOG_FILE
quantus-node \
  --validator \
  --chain $CHAIN \
  --base-path $BASE_PATH \
  --name "$NODENAME" \
  --rewards-address $REWARDS_ADDR \
  --node-key-file $NODE_KEY_FILE \
  --rpc-external \
  --rpc-methods unsafe \
  --rpc-cors all \
  --enable-peer-sharing \
  --out-peers 50 \
  --in-peers 100 \
  --allow-private-ip \
  --external-miner-url http://127.0.0.1:9833 \
  2>&1 | tee -a $LOG_FILE
code=\${PIPESTATUS[0]}
echo "[\$(date -Is)] ⛔ quantus-node exited (code=\$code) — restart za 5s..." | tee -a $LOG_FILE
sleep 5
EOF
)

# ===== Uruchomienie w tmux z autorestartem =====
tmux new-session -d -s quantus-node "bash -lc '
  while true; do
    $NODE_CMD
  done
'"

# ===== Informacje końcowe =====
echo "✅ quantus-node uruchomiony w tmux (session: quantus-node)"
echo "🏦 Rewards address: $REWARDS_ADDR"
echo "📄 Log: $LOG_FILE"
echo "ℹ️  Podgląd: tmux attach -t quantus-node  (Ctrl+B, D aby wyjść)"

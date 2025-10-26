#!/usr/bin/env bash
# Final: Quantus Node + Miner (Ubuntu 22.04 LTS), klucze Dilithium (konto + node), bez subkey

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# ======================= CONFIG =======================
NODENAME="PeeWuuTeGie"
CHAIN="schrodinger"
CHAIN_DIR="/root/chain"
BASE_PATH="/var/lib/quantus"
LOG_FILE="${BASE_PATH}/node.log"
# ======================================================

# ======== Kolory ========
BOLD="\e[1m"; RESET="\e[0m"; RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; CYAN="\e[36m"
ok(){ echo -e "✅ ${GREEN}$*${RESET}"; }
info(){ echo -e "ℹ️  ${CYAN}$*${RESET}"; }
step(){ echo -e "📦 ${BOLD}$*${RESET}"; }
warn(){ echo -e "⚠️  ${YELLOW}$*${RESET}"; }
err(){ echo -e "❌ ${RED}$*${RESET}"; }

# ======= Log globalny =======
mkdir -p "$(dirname /root/instalacja-logi.txt)"
exec > >(tee -a /root/instalacja-logi.txt) 2>&1

# Pre-check root
if [ "$(id -u)" -ne 0 ]; then err "Uruchom jako root."; exit 1; fi

# ================== Pakiety ==================
step "Instalacja zależności systemowych..."
apt-get install -y --no-install-recommends \
  build-essential cmake pkg-config libssl-dev \
  curl git tmux ufw jq clang ca-certificates xxd \
  protobuf-compiler libprotobuf-dev figlet toilet ruby python3-pip

# dodatki: lolcat, magic-wormhole
gem install lolcat
pip install magic-wormhole --break-system-packages || pip3 install magic-wormhole --break-system-packages || true

# === Banner ===
toilet -f big "PWTG      Kurwa" | lolcat

# ================== Rust =====================
step "Instalacja Rust + nightly..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup toolchain install nightly
rustup default nightly
ok "Rust: $(rustc --version) | Cargo: $(cargo --version)"

# ================== Źródła ===================
step "Klonowanie repozytoriów..."
[ -d "$CHAIN_DIR/.git" ] || git clone https://github.com/Quantus-Network/chain "$CHAIN_DIR"
[ -d "$CHAIN_DIR/quantus-miner/.git" ] || git clone https://github.com/Quantus-Network/quantus-miner "$CHAIN_DIR/quantus-miner"

# ================== Build =====================
export PROTOC=/usr/bin/protoc
step "Budowa Quantus Node..."
cd "$CHAIN_DIR"
cargo build --release
NODE_BIN="$CHAIN_DIR/target/release/quantus-node"
[ -x "$NODE_BIN" ] || { err "Brak $NODE_BIN"; exit 1; }

step "Budowa Quantus Miner..."
cd "$CHAIN_DIR/quantus-miner"
cargo build --release
MINER_BIN="$CHAIN_DIR/quantus-miner/target/release/quantus-miner"
[ -x "$MINER_BIN" ] || { err "Brak $MINER_BIN"; exit 1; }

# ========== Klucz konta (Dilithium) ==========
step "Generowanie klucza konta (Dilithium)..."
cd "$CHAIN_DIR"
KEY_CMD="./target/release/quantus-node key generate --scheme dilithium"
KEY_OUTPUT="$($KEY_CMD 2>&1 || true)"
printf "%s\n" "$KEY_OUTPUT" > /root/seed.txt
echo "" >> /root/seed.txt
echo "Key scheme: dilithium" >> /root/seed.txt

REWARDS_ADDR="$(echo "$KEY_OUTPUT" | sed -n 's/^.*SS58 Address:[[:space:]]*//p' | head -n1)"
[ -z "$REWARDS_ADDR" ] && REWARDS_ADDR="$(sed -n 's/^.*SS58 Address:[[:space:]]*//p' /root/seed.txt | head -n1)"
if ! echo "$REWARDS_ADDR" | grep -Eq '^[0-9A-Za-z]{32,64}$'; then
  err "Nieprawidłowy SS58 Address: '$REWARDS_ADDR'"
  exit 1
fi
ok "Rewards address: $REWARDS_ADDR"

# ========== Klucz węzła (P2P, libp2p) ==========
step "Generowanie klucza węzła (Dilithium)..."
NODE_KEY_FILE="$CHAIN_DIR/node-key"
NODEKEY_CMD="./target/release/quantus-node key generate-node-key --file $NODE_KEY_FILE"
NODEKEY_OUTPUT="$($NODEKEY_CMD 2>&1 || true)"
[ -n "$NODEKEY_OUTPUT" ] && printf "%s\n" "$NODEKEY_OUTPUT" >> /root/seed.txt

if [ ! -f "$NODE_KEY_FILE" ]; then err "Błąd generowania node-key"; exit 1; fi

pub_hex=$(xxd -p -c 64 "$NODE_KEY_FILE" | tail -c 64)
peer_id=$(printf "0020%s" "$pub_hex" | xxd -r -p | base64 | tr -d '=+/')

{
  echo ""
  echo "PeerID: $peer_id"
  echo "PeerID private key (base64): $(base64 -w0 "$NODE_KEY_FILE")"
  echo "PeerID private key (hex): $(xxd -p -c 256 "$NODE_KEY_FILE")"
} >> /root/seed.txt
ok "PeerID: $peer_id"

# ========== Firewall ==========
step "Konfiguracja UFW..."
ufw allow 22/tcp >/dev/null || true
ufw allow 30333/tcp >/dev/null || true
ufw allow 9933/tcp  >/dev/null || true
ufw allow 9833/tcp  >/dev/null || true
ufw --force enable  >/dev/null || true
ufw status verbose || true

# ========== Skróty ==========
step "Tworzenie skrótów..."
install -m 0755 "$NODE_BIN"  /usr/local/bin/quantus-node
install -m 0755 "$MINER_BIN" /usr/local/bin/quantus-miner

# ========== Uruchomienie ==========
step "Start minera (tmux)..."
tmux kill-session -t quantus-miner 2>/dev/null || true
tmux new-session -d -s quantus-miner "quantus-miner --workers \\$(nproc)"

for i in $(seq 1 60); do
  ss -ltn | grep -q ':9833' && break
  sleep 1

done
ok "Miner aktywny."

step "Start noda (tmux)..."
tmux kill-session -t quantus-node 2>/dev/null || true
tmux new-session -d -s quantus-node "quantus-node \
  --validator \
  --chain $CHAIN \
  --base-path $BASE_PATH \
  --name \"$NODENAME\" \
  --rewards-address $REWARDS_ADDR \
  --node-key-file $NODE_KEY_FILE \
  --rpc-external \
  --rpc-methods unsafe \
  --rpc-cors all \
  --enable-peer-sharing \
  --out-peers 50 \
  --in-peers 100 \
  --allow-private-ip \
  --external-miner-url http://127.0.0.1:9833 2>&1 | tee -a $LOG_FILE"

echo
ok "GOTOWE!"
info "📝 Klucze: /root/seed.txt"
info "📄 Log instalacji: /root/instalacja-logi.txt"
info "🏦 Rewards address: $REWARDS_ADDR"
info "🆔 PeerID: $peer_id"
info "🖥  Sesje tmux: quantus-miner, quantus-node"
info "👀 Log noda: tail -f $LOG_FILE"

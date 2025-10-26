#!/usr/bin/env bash
# Quantus Mining Dashboard v2.1
# Autor: GPT-5 + PeeWuuTeGie

LOGFILE="/var/lib/quantus/node.log"
ADDRESS="qzjgWhh2jhRFgD8fQnxp9HJXE34dx5XbPCXFUs6VnXFu8xHBj"

FILTER="Imported|Prepared|Successfully mined|Reward|Mined|Accepted|External|miner|Pow|QPoW|Seal|author|$ADDRESS|error"

clear
echo "🚀 Quantus Mining Dashboard for: $ADDRESS"
echo "------------------------------------------------------------"
echo "📘 Monitoring: $LOGFILE"
echo "------------------------------------------------------------"

# Tail logów — tylko kluczowe zdarzenia, bez szumu
tail -n 0 -f "$LOGFILE" \
  | grep -E --color=always "$FILTER" \
  | grep -vE "maintain txs|event=|duration=|tree_route|views=" &
TAIL_PID=$!

# Funkcja: statystyki systemowe
function system_stats() {
  CORES=$(nproc)
  if command -v mpstat &>/dev/null; then
    CPU_USAGE=$(mpstat 1 1 | awk '/Average:/ && $2 == "all" {printf("%.1f%%", 100 - $12)}')
  else
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8 "%"}')
  fi
  TEMP="N/A"
  if command -v sensors &>/dev/null; then
    TEMP=$(sensors 2>/dev/null | grep -m1 -E "Tctl|Package id 0|Tdie|temp1" | awk '{print $2}')
  fi
  echo "🧠 CPU Usage: $CPU_USAGE | 🔥 Temp: $TEMP | 🧩 Cores: $CORES"
}

# Funkcja: statystyki kopania
function mining_stats() {
  IMPORTED=$(grep -c "Imported" "$LOGFILE" 2>/dev/null)
  PREPARED=$(grep -c "Prepared block" "$LOGFILE" 2>/dev/null)
  MINED=$(grep -c "Successfully mined" "$LOGFILE" 2>/dev/null)
  REWARDS=$(grep -c "$ADDRESS" "$LOGFILE" 2>/dev/null)
  ERRORS=$(grep -ci "error" "$LOGFILE" 2>/dev/null)
  NOW=$(date +"%H:%M:%S")
  echo -e "🕒 $NOW | ⛏️ Imported: $IMPORTED | 🎁 Prepared: $PREPARED | 🥇 Mined: $MINED | 💰 Rewards: $REWARDS | ⚠️ Errors: $ERRORS"
}

while true; do
  echo "------------------------------------------------------------"
  system_stats
  mining_stats
  echo "------------------------------------------------------------"
  sleep 60
done

trap "kill $TAIL_PID 2>/dev/null" EXIT

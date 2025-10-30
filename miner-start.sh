#!/usr/bin/env bash
# ==============================================================
# Quantus Miner Autostart & Watchdog
# Uruchamia minera w tmux z automatycznym restartem i logowaniem.
# ==============================================================

# Zabicie wszystkich sesji tmux zawierających słowo "miner"
tmux ls 2>/dev/null | awk -F: '/miner/ {print $1}' | xargs -r -n1 tmux kill-session -t

# Start minera z autorestartem i logowaniem
tmux new-session -d -s quantus-miner "bash -lc '
  while true; do
    echo \"[\$(date -Is)] ▶️ Start quantus-miner (\$(nproc) workers)\" | tee -a ${BASE_PATH}/miner.log
    quantus-miner --workers \$(nproc) 2>&1 | tee -a ${BASE_PATH}/miner.log
    code=\${PIPESTATUS[0]}
    echo \"[\$(date -Is)] ⛔ quantus-miner exited (code=\$code) — restart za 5s...\" | tee -a ${BASE_PATH}/miner.log
    sleep 5
  done
'"

echo "✅ quantus-miner uruchomiony w tmux (session: quantus-miner)"
echo "📄 Log: ${BASE_PATH}/miner.log"
echo "ℹ️  Podgląd: tmux attach -t quantus-miner  (Ctrl+B, D aby wyjść)"

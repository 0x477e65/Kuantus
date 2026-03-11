#!/usr/bin/env bash
# ==============================================================
# Quantus Sync Watchdog - Automatyczny Resync przy zacięciu
# ==============================================================

LOG_FILE="/var/lib/quantus/node.log"
CHECK_INTERVAL=600  # Sprawdzaj co 10 minut
STUCK_LIMIT=6       # 1 godzina zacięcia
COUNTER=0
LAST_BLOCK=0

echo "[$(date -Is)] 🛡️ Sync Watchdog (ROOT MODE) uruchomiony..."

while true; do
  sleep $CHECK_INTERVAL
  
  # Pobranie ostatniej linii z informacją o Syncing
  SYNC_LINE=$(grep -a "Syncing" "$LOG_FILE" | tail -n 1)
  
  if [[ -z "$SYNC_LINE" ]]; then
    continue
  fi
  
  CURRENT_BLOCK=$(echo "$SYNC_LINE" | sed -n 's/.*best: #\([0-9]*\).*/\1/p')
  TARGET_BLOCK=$(echo "$SYNC_LINE" | sed -n 's/.*target=#\([0-9]*\).*/\1/p')
  
  if [[ ! "$CURRENT_BLOCK" =~ ^[0-9]+$ ]] || [[ ! "$TARGET_BLOCK" =~ ^[0-9]+$ ]]; then
    continue
  fi
  
  if [ "$CURRENT_BLOCK" -lt "$TARGET_BLOCK" ]; then
    if [ "$CURRENT_BLOCK" -eq "$LAST_BLOCK" ]; then
      ((COUNTER++))
      echo "[$(date -Is)] ⚠️ Sync stoi na bloku #$CURRENT_BLOCK ($COUNTER/$STUCK_LIMIT)"
    else
      COUNTER=0
      LAST_BLOCK=$CURRENT_BLOCK
    fi
  else
    COUNTER=0
    LAST_BLOCK=$CURRENT_BLOCK
  fi
  
  if [ "$COUNTER" -ge "$STUCK_LIMIT" ]; then
    echo "[$(date -Is)] 🚨 WYKRYTO ZACIĘCIE SYNCU! Wykonuję automatyczny PurGE Chain (sudo)..."
    
    # Procedura naprawcza z użyciem sudo
    sudo tmux kill-session -t quantus-node 2>/dev/null
    sudo tmux kill-session -t quantus-miner 2>/dev/null
    sudo rm -rf /var/lib/quantus/chains/dirac/db
    
    # Czyszczenie loga
    tail -n 100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    
    # Restart z użyciem sudo, aby skrypty miały dostęp do /root/
    sudo /home/juser2/dirak/node.sh
    sleep 10
    sudo /home/juser2/dirak/miner.sh
    
    echo "[$(date -Is)] ✅ Baza danych usunięta, procesy zrestartowane przez sudo."
    COUNTER=0
    LAST_BLOCK=0
  fi
done

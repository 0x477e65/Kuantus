#!/usr/bin/env bash
# ==============================================================================
# Quantus Node Backup Script (FINAL)
# - Backup danych node'a + keystore + node-key (bez kodu źródłowego)
# - Struktura: /root/quantus-backup/<YYYY-MM-DD>/Qantus_backup__<DD-MM-YY>__.tar.zst
# - Meta-log:  /root/quantus-backup/data/backup-<YYYY-MM-DD>.txt
# - Ubijanie wszystkich tmux session zawierających "node" lub "miner"
# ==============================================================================
set -euo pipefail

# --- Konfiguracja ścieżek ---
BACKUP_ROOT="/root/quantus-backup"
BACKUP_META_DIR="${BACKUP_ROOT}/data"
DATA_DIR="/var/lib/quantus"
NODE_KEY="/root/chain/node-key"

DATE_DAY="$(date +%F)"          # np. 2025-10-30
DATE_TAG="$(date +%d-%m-%y)"    # np. 30-10-25 -> nazwa pliku

BACKUP_DIR="${BACKUP_ROOT}/${DATE_DAY}"
BACKUP_FILE="${BACKUP_DIR}/Qantus_backup__${DATE_TAG}__.tar.zst"
LOG_FILE="${BACKUP_DIR}/Qantus_backup__${DATE_TAG}__.log"
SUMMARY_FILE="${BACKUP_META_DIR}/backup-${DATE_DAY}.txt"

# --- Kolory (opcjonalnie) ---
GREEN="$(tput setaf 2 || true)"
YELLOW="$(tput setaf 3 || true)"
RED="$(tput setaf 1 || true)"
RESET="$(tput sgr0 || true)"

# --- Przygotowanie katalogów ---
mkdir -p "${BACKUP_DIR}" "${BACKUP_META_DIR}"

echo -e "${YELLOW}=== Quantus Backup Start: ${DATE_DAY} ===${RESET}"
echo "Backup dir: ${BACKUP_DIR}"
echo "Backup file: ${BACKUP_FILE}"
echo "Log file:    ${LOG_FILE}"
echo "Meta log:    ${SUMMARY_FILE}"
echo

# --- Walidacja źródeł ---
if [[ ! -d "$DATA_DIR" ]]; then
  echo -e "${RED}❌ ERROR: brak katalogu danych: ${DATA_DIR}${RESET}"
  exit 1
fi
if [[ ! -f "$NODE_KEY" ]]; then
  echo "⚠️  Ostrzeżenie: nie znaleziono pliku node-key (${NODE_KEY})"
fi

echo "📦 Rozmiar danych przed kompresją:"
SIZE_BEFORE="$(du -sh "$DATA_DIR" | awk '{print $1}')"
echo "   ${DATA_DIR} -> ${SIZE_BEFORE}"

# --- Zatrzymanie sesji tmux zawierających 'node' lub 'miner' ---
KILLED_SESSIONS=""
if command -v tmux >/dev/null 2>&1; then
  if tmux ls 2>/dev/null | grep -Eiq 'node|min'; then
    echo "⏸️  Wykryto aktywne sesje tmux ('node'/'miner') — zatrzymuję..."
    while read -r session; do
      [[ -z "$session" ]] && continue
      echo "   🔹 Zabijam sesję: $session"
      tmux kill-session -t "$session" || true
      KILLED_SESSIONS+="$session "
    done < <(tmux ls 2>/dev/null | grep -E 'node|min' | cut -d: -f1)
  else
    echo "✅ Brak aktywnych sesji tmux node/miner – można bezpiecznie tworzyć backup."
  fi
else
  echo "ℹ️  tmux nie znaleziony – pomijam sekcję zatrzymywania sesji."
fi

# --- Wykrywanie katalogów keystore (również na przyszłość) ---
mapfile -t KEYSTORE_DIRS < <(
  {
    find "$DATA_DIR/chains" -maxdepth 3 -type d -name keystore 2>/dev/null;
    find /root/chain/chains -maxdepth 3 -type d -name keystore 2>/dev/null;
  } | sort -u
)
if [[ ${#KEYSTORE_DIRS[@]} -gt 0 ]]; then
  echo "🔑 Znalezione katalogi keystore:"
  for k in "${KEYSTORE_DIRS[@]}"; do echo "   - $k"; done
else
  echo "⚠️  Nie znaleziono katalogów keystore (sprawdzono $DATA_DIR/chains oraz /root/chain/chains)."
fi

# --- Tworzenie listy źródeł do tar ---
TAR_SOURCES=("$DATA_DIR")
[[ -f "$NODE_KEY" ]] && TAR_SOURCES+=("$NODE_KEY")
for k in "${KEYSTORE_DIRS[@]:-}"; do
  TAR_SOURCES+=("$k")
done

# --- Tworzenie backupu ---
echo
echo "🗜️  Tworzę archiwum (Zstd -19) ..."
sudo tar -I 'zstd -19' -cvf "$BACKUP_FILE" \
  "${TAR_SOURCES[@]}" \
  2>&1 | tee "$LOG_FILE"

# --- Sprawdzenie integralności archiwum ---
echo
echo "🔍 Weryfikacja integralności archiwum..."
sudo zstd -t "$BACKUP_FILE" && echo "✅ Test ZSTD: OK"

# --- Raport rozmiaru archiwum ---
ARCHIVE_SIZE="$(du -h "$BACKUP_FILE" | awk '{print $1}')"

# --- Test zawartości (keystore / brak kodu źródłowego) ---
echo
echo "🧩 Weryfikacja zawartości:"
HAS_KEYSTORE="NO"

# ⬇️ poprawka: listuj z dekoderem zstd i tylko nazwy wpisów
CONTENT_LIST="$(sudo tar -I zstd -tf "$BACKUP_FILE" || true)"

# szukaj 'keystore' (katalog lub jego zawartość) i dokładnej nazwy 'node-key'
MATCHED_KEYS="$(printf '%s\n' "$CONTENT_LIST" | grep -E '(^|/)(keystore)(/|$)|(^|/)node-key$' || true)"
if [[ -n "$MATCHED_KEYS" ]]; then
  HAS_KEYSTORE="YES"
  echo "✅ W archiwum znaleziono kluczowe wpisy:"
  # wypisz je ładnie w punktach
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "   • $line"
  done <<< "$MATCHED_KEYS"
else
  echo "⚠️  Brak wpisów keystore/node-key w archiwum!"
fi

# ⬇️ poprawka: testuj zawartość również z -I zstd i po samych nazwach
if printf '%s\n' "$CONTENT_LIST" | grep -q '^opt/quantus/'; then
  echo "⚠️  UWAGA: backup zawiera pliki źródłowe /opt/quantus (niezalecane!)"
  HAS_SOURCE="YES"
else
  echo "✅ Backup nie zawiera kodu źródłowego (/opt/quantus)."
  HAS_SOURCE="NO"
fi

# --- Detekcja ostrzeżeń „file changed as we read it” ---
WARN_CHANGED="NO"
if grep -Eq "file changed as we read it|File removed before we read it" "$LOG_FILE"; then
  WARN_CHANGED="YES"
  echo "⚠️  Wykryto ostrzeżenia o zmianie plików podczas odczytu (node mógł działać)."
fi

# --- Zapis meta-informacji do osobnego pliku (dla audytu) ---
{
  echo "=== Quantus Backup Meta ==="
  echo "Timestamp:       $(date -Is)"
  echo "Backup file:     $BACKUP_FILE"
  echo "Backup size:     $ARCHIVE_SIZE"
  echo "Source dir:      $DATA_DIR"
  echo "Source size:     $SIZE_BEFORE"
  echo "Node key path:   $NODE_KEY"
  if [[ ${#KEYSTORE_DIRS[@]} -gt 0 ]]; then
    echo "Keystore paths:"
    for k in "${KEYSTORE_DIRS[@]}"; do echo "  - $k"; done
  else
    echo "Keystore paths:  <none found>"
  fi
  echo "Keystore in tar: $HAS_KEYSTORE"
  echo "Source in tar:   $HAS_SOURCE"
  echo "Warnings (changed files): $WARN_CHANGED"
  echo "Killed tmux sessions: ${KILLED_SESSIONS:-none}"
  echo "Log file:        $LOG_FILE"
} > "$SUMMARY_FILE"

# --- Końcowe podsumowanie na ekranie ---
echo
echo "=== PODSUMOWANIE ==="
echo "📦 Backup zapisano: $BACKUP_FILE"
echo "📄 Log zapisano:    $LOG_FILE"
echo "📝 Meta-log:        $SUMMARY_FILE"
echo "📏 Rozmiar backupu: $ARCHIVE_SIZE"
echo "📦 Rozmiar źródeł:  $SIZE_BEFORE"
echo "🔑 Keystore w tar:  $HAS_KEYSTORE"
echo "🧱 Kod źr. w tar:   $HAS_SOURCE"
[[ "$WARN_CHANGED" == "YES" ]] && \
  echo "⚠️  Uwaga: wykryto zmiany plików podczas archiwizacji (node mógł działać)."

echo
echo -e "${GREEN}=== Backup zakończony pomyślnie ===${RESET}"

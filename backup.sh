#!/usr/bin/env bash
# ==============================================================================
# Quantus Node Backup Script (FINAL)
# - Snapshot danych node'a + keystore + node-key (bez kodu źródłowego)
# - Struktura: /root/quantus-backup/<YYYY-MM-DD>/Qantus_backup__<DD-MM-YY>__.tar.zst
# - Meta-log:  /root/quantus-backup/data/backup-<YYYY-MM-DD>.txt
# - Ubijanie sesji tmux zawierających "node" lub "miner"
# - Dodatkowo: katalog proof/ (logi tmux, wersje), suma SHA256, opcjonalny .rar
# ==============================================================================
set -euo pipefail
umask 077

# --- Konfiguracja ścieżek ---
BACKUP_ROOT="/root/quantus-backup"
BACKUP_META_DIR="${BACKUP_ROOT}/data"

DATA_DIR="/var/lib/quantus"                 # --base-path (potwierdzone)
CHAIN_NAME="schrodinger"                    # nazwa łańcucha
CHAIN_DIR="${DATA_DIR}/chains/${CHAIN_NAME}"

NODE_KEY="/root/chain/node-key"
CHAIN_SPEC="/root/chain/schro.raw.json"     # spec łańcucha, jeśli używana

DATE_DAY="$(date +%F)"          # np. 2025-10-30
DATE_TAG="$(date +%d-%m-%y)"    # np. 30-10-25 -> nazwa pliku

BACKUP_DIR="${BACKUP_ROOT}/${DATE_DAY}"
BACKUP_FILE="${BACKUP_DIR}/Qantus_backup__${DATE_TAG}__.tar.zst"
BACKUP_RAR="${BACKUP_DIR}/Qantus_backup__${DATE_TAG}__.rar"
SHA256_FILE="${BACKUP_DIR}/Qantus_backup__${DATE_TAG}__.sha256"
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
[[ -d "$CHAIN_DIR" ]] || echo "ℹ️  Uwaga: ${CHAIN_DIR} nie istnieje (inny łańcuch?)"
[[ -f "$NODE_KEY" ]] || echo "⚠️  Ostrzeżenie: brak pliku node-key (${NODE_KEY})"
[[ -f "$CHAIN_SPEC" ]] || echo "ℹ️  Uwaga: brak chain spec (${CHAIN_SPEC}) — pomijam"

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

# --- Katalog PROOF z artefaktami dowodowymi ---
PROOF_DIR="${BACKUP_DIR}/proof"
mkdir -p "${PROOF_DIR}"

# Zrzuty tmux (jeśli jakiekolwiek sesje są uruchomione)
if command -v tmux >/dev/null 2>&1; then
  tmux list-sessions 2>/dev/null | awk -F: '{print $1}' | while read -r s; do
    case "$s" in
      *node*|*miner*)
        tmux capture-pane -pt "$s" > "${PROOF_DIR}/${s}_$(date +%F_%H-%M-%S).log" || true
        ;;
    esac
  done
fi

# Metadane/wersje środowiska
{
  date -Is
  uname -a
  command -v quantus-node >/dev/null 2>&1 && quantus-node --version || echo "quantus-node: not in PATH"
  ps -ef | grep -i '[q]uantus-node' || true
} > "${PROOF_DIR}/environment.txt"

# Skrypty startowe (jeśli istnieją)
[[ -f /root/Kuantus/node-start.sh  ]] && cp -f /root/Kuantus/node-start.sh  "${PROOF_DIR}/"
[[ -f /root/Kuantus/miner-start.sh ]] && cp -f /root/Kuantus/miner-start.sh "${PROOF_DIR}/"

# --- Tworzenie listy źródeł do tar ---
TAR_SOURCES=("$DATA_DIR")
# jawnie dodajemy kluczowe podkatalogi łańcucha, jeśli istnieją
[[ -d "${CHAIN_DIR}/db"       ]] && TAR_SOURCES+=("${CHAIN_DIR}/db")
[[ -d "${CHAIN_DIR}/network"  ]] && TAR_SOURCES+=("${CHAIN_DIR}/network")
[[ -d "${CHAIN_DIR}/keystore" ]] && TAR_SOURCES+=("${CHAIN_DIR}/keystore")

# node-key i chain spec
[[ -f "$NODE_KEY"  ]] && TAR_SOURCES+=("$NODE_KEY")
[[ -f "$CHAIN_SPEC" ]] && TAR_SOURCES+=("$CHAIN_SPEC")

# keystore'y znalezione dynamicznie
for k in "${KEYSTORE_DIRS[@]:-}"; do TAR_SOURCES+=("$k"); done

# katalog dowodowy
TAR_SOURCES+=("$PROOF_DIR")

# --- Tworzenie backupu .tar.zst ---
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
CONTENT_LIST="$(sudo tar -I zstd -tf "$BACKUP_FILE" || true)"

MATCHED_KEYS="$(printf '%s\n' "$CONTENT_LIST" | grep -E '(^|/)(keystore)(/|$)|(^|/)node-key$' || true)"
if [[ -n "$MATCHED_KEYS" ]]; then
  HAS_KEYSTORE="YES"
  echo "✅ W archiwum znaleziono kluczowe wpisy:"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "   • $line"
  done <<< "$MATCHED_KEYS"
else
  echo "⚠️  Brak wpisów keystore/node-key w archiwum!"
fi

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

# --- Suma SHA256 (dla archiwum .tar.zst) ---
sha256sum "$BACKUP_FILE" > "$SHA256_FILE"

# --- (Opcjonalnie) dodatkowe archiwum .rar z rekordem naprawczym 5% ---
if command -v rar >/dev/null 2>&1; then
  echo
  echo "🗄️  Tworzę archiwum RAR (z rekordem naprawczym 5%)..."
  (
    cd "${BACKUP_DIR}"
    # do .rar wrzucamy .tar.zst + .sha256 + katalog proof/ (dowody)
    rar a -rr5 -m5 -ep1 "$(basename "$BACKUP_RAR")" \
      "$(basename "$BACKUP_FILE")" \
      "$(basename "$SHA256_FILE")" \
      "proof/" > /dev/null
  )
  echo "✅ Utworzono: ${BACKUP_RAR}"
  du -h "${BACKUP_RAR}" || true
else
  echo "ℹ️  rar nie jest zainstalowany (apt install rar) – pomijam .rar"
fi

# --- Zapis meta-informacji do osobnego pliku (dla audytu) ---
{
  echo "=== Quantus Backup Meta ==="
  echo "Timestamp:       $(date -Is)"
  echo "Backup file:     $BACKUP_FILE"
  echo "Backup size:     $ARCHIVE_SIZE"
  echo "SHA256 file:     $SHA256_FILE"
  [[ -f "$BACKUP_RAR" ]] && echo "Backup RAR:      $BACKUP_RAR"
  echo "Source dir:      $DATA_DIR"
  echo "Source size:     $SIZE_BEFORE"
  echo "Chain dir:       $CHAIN_DIR"
  echo "Node key path:   $NODE_KEY"
  echo "Chain spec:      $CHAIN_SPEC"
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
[[ -f "$BACKUP_RAR" ]] && echo "🗄️  Archiwum RAR:  $BACKUP_RAR"
echo "🧾 Suma SHA256:    $SHA256_FILE"
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

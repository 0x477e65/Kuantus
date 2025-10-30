#!/usr/bin/env bash
# ==============================================================================
# Quantus Build Update (chain + miner) — ALWAYS BUILD, SAFE NODE-KEY, BEFORE/AFTER, FINAL SUMMARY
# - Aktualizuje repozytoria (ff-only) i ZAWSZE buduje binarki (quantus-node, quantus-miner).
# - Bez stashowania nieśledzonych (chroni node-key w /root/chain/node-key).
# - Drukuje BEFORE/AFTER + wersje binarek po buildzie.
# - Akceptuje remotes z .git i bez .git.
# - Nie klonuje, nie zatrzymuje procesów. Tylko update + build.
# ==============================================================================

set -euo pipefail

# ----- Konfiguracja (Twoje ścieżki) -----
CHAIN_DIR="${CHAIN_DIR:-/root/chain}"
MINER_DIR="${MINER_DIR:-/root/chain/quantus-miner}"
BRANCH="${BRANCH:-main}"

UPSTREAM_ORG="https://github.com/Quantus-Network"
CHAIN_EXPECTED_REMOTE="${UPSTREAM_ORG}/chain.git"
MINER_EXPECTED_REMOTE="${UPSTREAM_ORG}/quantus-miner.git"

LOG_ROOT="/root/quantus-backup/data"
mkdir -p "$LOG_ROOT"
STAMP="$(date +%F_%H-%M)"
UPDATE_LOG="${LOG_ROOT}/update-${STAMP}.log"

# ----- Zmienne stanu do podsumowania -----
CHAIN_PRE_DESC="n/a";  CHAIN_PRE_LINE="n/a";  CHAIN_POST_DESC="n/a"; CHAIN_POST_LINE="n/a"
MINER_PRE_DESC="n/a";  MINER_PRE_LINE="n/a";  MINER_POST_DESC="n/a"; MINER_POST_LINE="n/a"
CHAIN_BIN_PATH="";     MINER_BIN_PATH=""
CHAIN_BIN_VER="";      MINER_BIN_VER=""
WARNINGS=();           ERRORS=()

# ----- Finalne podsumowanie niezależnie od błędów -----
final_summary() {
  echo
  echo "=== PODSUMOWANIE ==="

  if [[ -d "$CHAIN_DIR/.git" ]]; then
    echo "CHAIN:"
    echo "  BEFORE: ${CHAIN_PRE_DESC} | ${CHAIN_PRE_LINE}"
    echo "  AFTER : ${CHAIN_POST_DESC} | ${CHAIN_POST_LINE}"
    [[ -n "$CHAIN_BIN_PATH" ]] && echo "  BIN   : ${CHAIN_BIN_PATH}"
    [[ -n "$CHAIN_BIN_VER"  ]] && echo "  VER   : ${CHAIN_BIN_VER}"
  else
    echo "CHAIN: brak repo (${CHAIN_DIR})"
  fi

  echo

  if [[ -d "$MINER_DIR/.git" ]]; then
    echo "MINER:"
    echo "  BEFORE: ${MINER_PRE_DESC} | ${MINER_PRE_LINE}"
    echo "  AFTER : ${MINER_POST_DESC} | ${MINER_POST_LINE}"
    [[ -n "$MINER_BIN_PATH" ]] && echo "  BIN   : ${MINER_BIN_PATH}"
    [[ -n "$MINER_BIN_VER"  ]] && echo "  VER   : ${MINER_BIN_VER}"
  else
    echo "MINER: brak repo (${MINER_DIR})"
  fi

  echo
  [[ ${#WARNINGS[@]} -gt 0 ]] && { echo "WARNINGS:"; for w in "${WARNINGS[@]}"; do echo "  - $w"; done; echo; }
  [[ ${#ERRORS[@]}   -gt 0 ]] && { echo "ERRORS:";   for e in "${ERRORS[@]}";   do echo "  - $e"; done; echo; }

  echo "Log zaktualizowano: ${UPDATE_LOG}"
  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo "⚠️  Update zakończony z ostrzeżeniami/błędami (patrz wyżej i w logu)."
  else
    echo "✅ Update + BUILD zakończony."
  fi
}
trap final_summary EXIT

# ----- Log na ekran + do pliku -----
exec > >(tee -a "$UPDATE_LOG") 2>&1

echo "=== Quantus Build Update Start: ${STAMP} ==="
echo "Log file : ${UPDATE_LOG}"
echo "CHAIN_DIR: ${CHAIN_DIR}"
echo "MINER_DIR: ${MINER_DIR}"
echo "BRANCH   : ${BRANCH}"
echo

# ----- Toolchain -----
echo ">> Rust toolchain"
if command -v rustup >/dev/null 2>&1; then
  rustup show active-toolchain || true
  rustup update nightly || true
else
  WARNINGS+=("rustup nie znaleziony — pominięto update nightly")
fi
if command -v cargo >/dev/null 2>&1; then
  cargo --version
else
  ERRORS+=("Brak cargo w PATH — przerwano build.")
  exit 1
fi
echo

# ----- Helpery -----
ensure_nodekey_ignored () {
  # $1 = repo dir
  local REPO_DIR="$1"
  local CAND="${REPO_DIR%/}/node-key"
  if [[ -f "$CAND" && -d "$REPO_DIR/.git" ]]; then
    grep -qxF "node-key" "$REPO_DIR/.git/info/exclude" 2>/dev/null || echo "node-key" >> "$REPO_DIR/.git/info/exclude" || true
  fi
}

# Akceptuj remotes z i bez sufiksu .git
remote_ok () {
  # $1 = current remote, $2 = expected remote (z .git)
  local CUR="$1"
  local EXP="$2"
  local CUR_NO_GIT="${CUR%.git}"
  local EXP_NO_GIT="${EXP%.git}"
  [[ -z "$EXP" || "$CUR_NO_GIT" == "$EXP_NO_GIT" ]]
}

git_before_info () {
  # $1 = repo dir ; echo trzy linie: HASH, DESC, LINE
  local REPO="$1"
  ( cd "$REPO" && \
    git rev-parse --short HEAD 2>/dev/null || echo "-" ; \
    git describe --tags --always --dirty 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "-" ; \
    git log -1 --pretty=format:'%h %ad %an: %s' --date=iso 2>/dev/null || echo "<no commits>" )
}

git_ff_pull () {
  # $1=ROLE (CHAIN/MINER), $2=repo dir, $3=expected remote (opcjonalnie), $4=branch
  local ROLE="$1"; local REPO_DIR="$2"; local EXPECTED_REMOTE="${3:-}"; local BR="$4"

  echo ">> Repo: ${REPO_DIR}"
  if [[ ! -d "$REPO_DIR/.git" ]]; then
    WARNINGS+=("${ROLE}: katalog nie jest repozytorium git lub nie istnieje: ${REPO_DIR}")
    return 0
  fi

  cd "$REPO_DIR"
  ensure_nodekey_ignored "$REPO_DIR"

  # BEFORE
  local PRE_H PRE_D PRE_L
  read -r PRE_H <<<"$(git_before_info "$REPO_DIR" | sed -n '1p')"
  read -r PRE_D <<<"$(git_before_info "$REPO_DIR" | sed -n '2p')"
  read -r PRE_L <<<"$(git_before_info "$REPO_DIR" | sed -n '3p')"

  # Remote check (akceptuj ± .git)
  local CUR_REMOTE; CUR_REMOTE="$(git remote get-url origin 2>/dev/null || echo '')"
  echo "   origin: ${CUR_REMOTE:-<brak>}"
  if ! remote_ok "$CUR_REMOTE" "$EXPECTED_REMOTE"; then
    WARNINGS+=("${ROLE}: origin NIE wskazuje na oficjalne repo (oczekiwano ${EXPECTED_REMOTE} ± .git; wykryto ${CUR_REMOTE:-<brak>})")
  fi

  # Fetch + switch + pull --ff-only
  git fetch --all --prune || { ERRORS+=("${ROLE}: git fetch nie powiódł się"); return 1; }
  (git switch "$BR" || git checkout "$BR") || { ERRORS+=("${ROLE}: przełączenie na branch '${BR}' nie powiodło się"); return 1; }
  git config pull.ff only || true
  if ! git pull --ff-only; then
    echo "   ❌ Fast-forward nieudany (lokalne zmiany)."
    git status -sb || true
    ERRORS+=("${ROLE}: pull --ff-only nie powiódł się (lokalne zmiany). Napraw ręcznie i uruchom ponownie.")
    return 1
  fi

  # AFTER (do podsumowania)
  local POST_H POST_D POST_L
  read -r POST_H <<<"$(git_before_info "$REPO_DIR" | sed -n '1p')"
  read -r POST_D <<<"$(git_before_info "$REPO_DIR" | sed -n '2p')"
  read -r POST_L <<<"$(git_before_info "$REPO_DIR" | sed -n '3p')"

  echo "   BEFORE: ${PRE_D} | ${PRE_L}"
  echo "   AFTER : ${POST_D} | ${POST_L}"

  # Zapisz do zmiennych podsumowania
  eval "${ROLE}_PRE_DESC=\"\$PRE_D\""
  eval "${ROLE}_PRE_LINE=\"\$PRE_L\""
  eval "${ROLE}_POST_DESC=\"\$POST_D\""
  eval "${ROLE}_POST_LINE=\"\$POST_L\""
}

build_role () {
  # $1=ROLE (CHAIN/MINER) ; $2=repo dir ; $3=crate selector ; $4=bin expected path ; $5=version cmd
  local ROLE="$1"; local DIR="$2"; local CRATE="$3"; local BINPATH="$4"; local VERCMD="$5"
  echo ">> Build ${ROLE,,} (${CRATE})"
  if [[ ! -d "$DIR/.git" ]]; then
    WARNINGS+=("${ROLE}: pomijam build — brak repo ${DIR}")
    return 0
  fi
  cd "$DIR"
  if ! cargo build --release -p "${CRATE}"; then
    ERRORS+=("${ROLE}: build nie powiódł się (cargo build --release -p ${CRATE})")
    return 1
  fi
  if [[ -f "$BINPATH" ]]; then
    eval "${ROLE}_BIN_PATH=\"\$BINPATH\""
    local VER_OUT
    VER_OUT="$($VERCMD 2>/dev/null || true)"
    eval "${ROLE}_BIN_VER=\"\$VER_OUT\""
    echo "   ✔ build OK: ${BINPATH}"
    [[ -n "$VER_OUT" ]] && echo "   bin version: ${VER_OUT}"
  else
    WARNINGS+=("${ROLE}: build ukończony, ale binarki nie znaleziono (${BINPATH})")
  fi
}

# ----- Aktualizacja (FF pull) -----
git_ff_pull "CHAIN" "$CHAIN_DIR" "$CHAIN_EXPECTED_REMOTE" "$BRANCH" || true
git_ff_pull "MINER" "$MINER_DIR" "$MINER_EXPECTED_REMOTE" "$BRANCH" || true
echo

# ----- ZAWSZE build: najpierw chain, potem miner -----
build_role "CHAIN" "$CHAIN_DIR" "quantus-node" "${CHAIN_DIR}/target/release/quantus-node" "${CHAIN_DIR}/target/release/quantus-node --version" || true
build_role "MINER" "$MINER_DIR" "miner-cli"    "${MINER_DIR}/target/release/quantus-miner" "${MINER_DIR}/target/release/quantus-miner --version" || true
echo

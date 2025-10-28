# 🚀 Quantus Network — instalator węzła (node) + minera 

# By    PeWuTeGe      `o_0`

Instalator dla **Quantus Node + Miner**, napisany pod **Ubuntu 22.04 LTS**. Automatyzuje budowę i uruchomienie węzła i minera z repozytoriów Quantus-Network.

**W skrócie — skrypt wykonuje:**

* 📦 instalację zależności (Rust, protoc, cmake, build-essential, itp.)
* 🔐 generowanie kluczy Dilithium (konto nagród) oraz klucza węzła (node-key)
* ⚙️ budowę `quantus-node` i `quantus-miner` z źródeł
* 🧱 uruchomienie obu procesów w oddzielnych sesjach `tmux`
* 🪵 logowanie instalacji i zapis kluczy do plików (`/root/instalacja-logi.txt`, `/root/seed.txt`)

---

## Co robi skrypt (krótko)

1. **Klonuje** repozytoria `Quantus-Network/chain` i `quantus-miner`.
2. **Buduje** obydwa projekty w trybie `--release` (cargo build --release).
3. **Generuje** parę kluczy dla konta (Dilithium) i zapisuje output do `/root/seed.txt` (zawiera: secret phrase, SS58 address, public key base58 „Qm...”).
4. **Generuje** klucz węzła (`node-key`) i wyprowadza PeerID.
5. **Instaluje** binarki do `/usr/local/bin/quantus-node` i `/usr/local/bin/quantus-miner`.
6. **Uruchamia** miner i node w `tmux` (sesje: `quantus-miner`, `quantus-node`).
7. **Konfiguruje** prosty firewall (UFW) i tworzy pomocnicze pliki logów.

---

## Szybkie użycie

1. **Pobierz skrypt** (przykład):

```bash
wget https://github.com/0x477e65/Kuantus/blob/main/pewutege.sh
```

2. **Nadaj prawa do wykonania**:

```bash
sudo chmod +x pewutege.sh
```

3. **(Zalecane) Przejrzyj skrypt** (`nano pewutege.sh`) i zmień konfigurację na początku pliku (`NODENAME`) przed uruchomieniem.

4. **Uruchom jako root** (skrypt wymaga uprawnień root):

```bash
sudo ./pewutege.sh
```

---

## Gdzie są klucze i logi

* Klucze i seed zapisane: `/root/seed.txt` (zawiera: secret phrase, SS58 Address, Dilithium public key `Qm...`, PeerID i node-key w hex/base64)
* Log instalacji: `/root/instalacja-logi.txt`
* Node log (dzień pracy): `/var/lib/quantus/node.log`
* Sesje tmux: `quantus-miner`, `quantus-node`

---

## Backup kluczy (zalecane!)

**Natychmiast** po instalacji wykonaj kopię zapasową `seed.txt` i `node-key`:

```bash
# Skopiuj w bezpieczne miejsce pliki : 
/root/seed.txt
/root/chain/node-key
```
## Jak edytować nazwę węzła i inne ustawienia

Skrypt ma sekcję **CONFIG** na samym początku. Najważniejsze zmienne:

```bash
NODENAME="PeeWuuTeGie"   # zmień na swoją nazwę
CHAIN="schrodinger"      # nazwa chain (domyślnie schrodinger)
CHAIN_DIR="/root/chain"   # katalog z kodem źródłowym
BASE_PATH="/var/lib/quantus" # katalog bazy noda
LOG_FILE="${BASE_PATH}/node.log"
```

Edytuj `NODENAME` przed uruchomieniem, zapisz i uruchom skrypt.

---

## Bezpieczeństwo i uwagi

* Skrypt instaluje `rustup` i ustawia toolchain `nightly`.
* `seed.txt` zawiera wrażliwe dane — wykonaj backup offline i skasuj z maszyn publicznych.
* Firewall UFW jest ustawiony domyślnie (otwiera porty 22, 30333, 9933, 9833)
* Skrypt włącza `--rpc-methods unsafe` i `--rpc-cors all` w `quantus-node` dla wygody — jeśli wystawiasz node na publiczne interfejsy, rozważ ich zmianę.

---

## Licencja

Częstujcie się

---

## ⚙️ Przydatne komendy

**Start minera w TMUX po zabiciu | reebot**

`tmux new-session -d -s quantus-miner "quantus-miner --workers \\$(nproc)"`

**Start NODE w TMUX po zabiciu | reebot**

`tmux new-session -d -s quantus-node "quantus-node \ --validator \ --chain $CHAIN \ --base-path $BASE_PATH \ --name \"$NODENAME\" \ --rewards-address $REWARDS_ADDR \ --node-key-file $NODE_KEY_FILE \ --rpc-external \ --rpc-methods unsafe \ --rpc-cors all \ --enable-peer-sharing \ --out-peers 50 \ --in-peers 100 \ --allow-private-ip \ --external-miner-url http://127.0.0.1:9833 2>&1 | tee -a $LOG_FILE"`





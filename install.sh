#!/usr/bin/env bash
# install.sh — установка и настройка mirea-2fa-parser
set -e

# ── Цвета ──────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}  ✓ $*${NC}"; }
info() { echo -e "${YELLOW}  → $*${NC}"; }
err()  { echo -e "${RED}  ✗ $*${NC}"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="mirea-parser"
CONFIG_DIR="$HOME/.config/mirea-parser"
CONFIG_INI="$SCRIPT_DIR/config.ini"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║         mirea-2fa-parser  installer          ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── 1. Python ──────────────────────────────────────────────────────────────────
info "Проверяю Python 3..."
PYTHON=$(command -v python3 || command -v python || err "Python 3 не найден. Установи: sudo apt install python3")
PY_VER=$($PYTHON -c "import sys; print(sys.version_info.minor)")
[[ "$PY_VER" -ge 8 ]] || err "Нужен Python 3.8+, найден 3.$PY_VER"
ok "Python: $($PYTHON --version)"

# ── 2. Pip-зависимости ─────────────────────────────────────────────────────────
info "Устанавливаю зависимости..."
$PYTHON -m pip install -q --upgrade pip
$PYTHON -m pip install -q -r "$SCRIPT_DIR/requirements.txt"
ok "gspread, google-auth установлены"

# ── 3. JSON-ключ ───────────────────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR"
KEY_PATH="$CONFIG_DIR/key.json"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Шаг 1 из 2: JSON-ключ сервис-аккаунта Google"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -f "$KEY_PATH" ]]; then
    echo ""
    read -rp "  Файл key.json уже существует. Перезаписать? [y/N]: " OVERWRITE
    OVERWRITE="${OVERWRITE:-N}"
fi

if [[ ! -f "$KEY_PATH" || "$OVERWRITE" =~ ^[Yy]$ ]]; then
    echo ""
    echo "  Вставь содержимое JSON-ключа (всё что в фигурных скобках { ... }),"
    echo "  затем нажми Enter, потом Ctrl+D:"
    echo ""
    JSON_CONTENT=$(cat)

    # Проверяем что вставили JSON
    echo "$JSON_CONTENT" | $PYTHON -c "import sys,json; json.load(sys.stdin)" 2>/dev/null \
        || err "Вставленный текст не является валидным JSON. Попробуй ещё раз."

    echo "$JSON_CONTENT" > "$KEY_PATH"
    chmod 600 "$KEY_PATH"
    ok "Ключ сохранён: $KEY_PATH (права 600)"
else
    ok "Используется существующий ключ: $KEY_PATH"
fi

# ── 4. SPREADSHEET_ID ──────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Шаг 2 из 2: ID Google Таблицы"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  URL таблицы выглядит так:"
echo "  https://docs.google.com/spreadsheets/d/<ID>/edit"
echo "                                          ^^^^"

# Берём существующий ID если конфиг уже есть
EXISTING_ID=""
if [[ -f "$CONFIG_INI" ]]; then
    EXISTING_ID=$(grep -Po '(?<=spreadsheet_id = ).*' "$CONFIG_INI" || true)
fi

if [[ -n "$EXISTING_ID" ]]; then
    read -rp "  ID таблицы [${EXISTING_ID}]: " SPREADSHEET_ID
    SPREADSHEET_ID="${SPREADSHEET_ID:-$EXISTING_ID}"
else
    read -rp "  Введи ID таблицы: " SPREADSHEET_ID
fi

[[ -n "$SPREADSHEET_ID" ]] || err "ID таблицы не может быть пустым"

# ── 5. config.ini ──────────────────────────────────────────────────────────────
cat > "$CONFIG_INI" <<EOF
[mirea]
json_key       = $KEY_PATH
spreadsheet_id = $SPREADSHEET_ID
sender         = sso@mirea.ru
imap_host      = imap.mail.ru
imap_port      = 993
EOF
ok "Конфиг создан: $CONFIG_INI"

# ── 6. Проверка подключения к таблице ─────────────────────────────────────────
echo ""
info "Проверяю доступ к Google Таблице..."
$PYTHON - <<PYEOF
import configparser, gspread
from google.oauth2.service_account import Credentials
cfg = configparser.ConfigParser()
cfg.read("$CONFIG_INI")
c = cfg["mirea"]
creds = Credentials.from_service_account_file(c["json_key"], scopes=["https://www.googleapis.com/auth/spreadsheets"])
sheet = gspread.authorize(creds).open_by_key(c["spreadsheet_id"]).sheet1
rows = sheet.get_all_values()
print(f"  Таблица открыта, строк: {len(rows)}")
PYEOF
ok "Доступ к таблице подтверждён"

# ── 7. systemd (только на Linux) ──────────────────────────────────────────────
if [[ "$(uname)" != "Linux" ]]; then
    echo ""
    ok "macOS — systemd пропускаем. Запуск: python3 $SCRIPT_DIR/parser.py"
    exit 0
fi

echo ""
info "Настраиваю systemd-сервис..."

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
PYTHON_PATH=$(command -v python3)

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=MIREA 2FA Code Parser
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$PYTHON_PATH -u $SCRIPT_DIR/parser.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

sleep 2
STATUS=$(systemctl is-active "$SERVICE_NAME")
if [[ "$STATUS" == "active" ]]; then
    ok "Сервис запущен и добавлен в автозапуск"
else
    err "Сервис не поднялся. Смотри логи: sudo journalctl -u $SERVICE_NAME -n 30"
fi

# ── Итог ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║             Установка завершена!             ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Логи:       sudo journalctl -u $SERVICE_NAME -f"
echo "  Остановить: sudo systemctl stop $SERVICE_NAME"
echo "  Запустить:  sudo systemctl start $SERVICE_NAME"
echo ""

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

# ── 2. Зависимости ─────────────────────────────────────────────────────────────
info "Устанавливаю зависимости..."
$PYTHON -m pip install -q --upgrade pip
$PYTHON -m pip install -q -r "$SCRIPT_DIR/requirements.txt"
ok "gspread, google-auth установлены"

# ── 3. JSON-ключ ───────────────────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR"
KEY_PATH="$CONFIG_DIR/key.json"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Шаг 1 из 3: JSON-ключ сервис-аккаунта Google"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

OVERWRITE="N"
if [[ -f "$KEY_PATH" ]]; then
    echo ""
    read -rp "  Файл key.json уже существует. Перезаписать? [y/N]: " OVERWRITE
    OVERWRITE="${OVERWRITE:-N}"
fi

if [[ ! -f "$KEY_PATH" || "$OVERWRITE" =~ ^[Yy]$ ]]; then
    echo ""
    echo "  Открой JSON-файл, скопируй всё содержимое,"
    echo "  вставь сюда, затем нажми Enter и Ctrl+D:"
    echo ""
    JSON_CONTENT=$(cat)
    echo "$JSON_CONTENT" | $PYTHON -c "import sys,json; json.load(sys.stdin)" 2>/dev/null \
        || err "Невалидный JSON. Попробуй ещё раз."
    echo "$JSON_CONTENT" > "$KEY_PATH"
    chmod 600 "$KEY_PATH"
    ok "Ключ сохранён: $KEY_PATH (права 600)"
else
    ok "Используется существующий ключ: $KEY_PATH"
fi

# ── 4. Центральный ящик ────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Шаг 2 из 3: Центральный mail.ru ящик"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  На этот ящик все участники пересылают письма от sso@mirea.ru."
echo "  Используй App Password (не основной пароль от mail.ru)."
echo ""

EXISTING_EMAIL=$(grep -Po '(?<=central_email    = ).*' "$CONFIG_INI" 2>/dev/null || true)
EXISTING_PASS=$(grep  -Po '(?<=central_password = ).*' "$CONFIG_INI" 2>/dev/null || true)

read -rp "  Email центрального ящика [${EXISTING_EMAIL}]: " CENTRAL_EMAIL
CENTRAL_EMAIL="${CENTRAL_EMAIL:-$EXISTING_EMAIL}"
[[ -n "$CENTRAL_EMAIL" ]] || err "Email не может быть пустым"

read -rsp "  App Password: " CENTRAL_PASSWORD
echo ""
CENTRAL_PASSWORD="${CENTRAL_PASSWORD:-$EXISTING_PASS}"
[[ -n "$CENTRAL_PASSWORD" ]] || err "Пароль не может быть пустым"

# ── 5. ID таблицы ──────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Шаг 3 из 3: ID Google Таблицы"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  URL: https://docs.google.com/spreadsheets/d/<ID>/edit"
echo ""

EXISTING_ID=$(grep -Po '(?<=spreadsheet_id   = ).*' "$CONFIG_INI" 2>/dev/null || true)
read -rp "  ID таблицы [${EXISTING_ID}]: " SPREADSHEET_ID
SPREADSHEET_ID="${SPREADSHEET_ID:-$EXISTING_ID}"
[[ -n "$SPREADSHEET_ID" ]] || err "ID таблицы не может быть пустым"

# ── 6. Записываем config.ini ───────────────────────────────────────────────────
cat > "$CONFIG_INI" <<EOF
[mirea]
central_email    = $CENTRAL_EMAIL
central_password = $CENTRAL_PASSWORD
json_key         = $KEY_PATH
spreadsheet_id   = $SPREADSHEET_ID
sender           = sso@mirea.ru
imap_host        = imap.mail.ru
imap_port        = 993
EOF
ok "Конфиг создан: $CONFIG_INI"

# ── 7. Проверка IMAP + таблицы ─────────────────────────────────────────────────
echo ""
info "Проверяю подключение к IMAP и Google Таблице..."
$PYTHON - <<PYEOF
import imaplib, configparser, gspread
from google.oauth2.service_account import Credentials

cfg = configparser.ConfigParser()
cfg.read("$CONFIG_INI")
c = cfg["mirea"]

# IMAP
mail = imaplib.IMAP4_SSL(c.get("imap_host", "imap.mail.ru"), int(c.get("imap_port", "993")))
mail.login(c["central_email"], c["central_password"])
mail.logout()
print("  IMAP: OK")

# Sheets
creds = Credentials.from_service_account_file(c["json_key"], scopes=["https://www.googleapis.com/auth/spreadsheets"])
sheet = gspread.authorize(creds).open_by_key(c["spreadsheet_id"]).sheet1
rows = sheet.get_all_values()
print(f"  Таблица: OK ({len(rows)} строк)")
PYEOF
ok "Все подключения работают"

# ── 8. systemd (только Linux) ─────────────────────────────────────────────────
if [[ "$(uname)" != "Linux" ]]; then
    echo ""
    ok "macOS — systemd пропускаем."
    echo "  Запуск: python3 $SCRIPT_DIR/parser.py"
    echo ""
    exit 0
fi

echo ""
info "Настраиваю systemd-сервис..."
PYTHON_PATH=$(command -v python3)

sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null <<EOF
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
if systemctl is-active --quiet "$SERVICE_NAME"; then
    ok "Сервис запущен и добавлен в автозапуск"
else
    err "Сервис не поднялся. Логи: sudo journalctl -u $SERVICE_NAME -n 30"
fi

# ── Итог ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║             Установка завершена!             ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  Логи:       sudo journalctl -u $SERVICE_NAME -f"
echo "  Остановить: sudo systemctl stop $SERVICE_NAME"
echo "  Перезапуск: sudo systemctl restart $SERVICE_NAME"
echo ""

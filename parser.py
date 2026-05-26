import imaplib
import email
import email.utils
from email.header import decode_header, make_header
import configparser
import re
import time
import socket
import gspread
from google.oauth2.service_account import Credentials
from pathlib import Path

# ── Конфиг ────────────────────────────────────────────────────────────────────

def load_config():
    cfg = configparser.ConfigParser()
    cfg_path = Path(__file__).parent / "config.ini"
    if not cfg_path.exists():
        raise FileNotFoundError(
            f"Файл config.ini не найден: {cfg_path}\n"
            "Запустите ./install.sh для настройки."
        )
    cfg.read(cfg_path)
    return cfg["mirea"]

CFG              = load_config()
JSON_KEY         = CFG["json_key"]
SPREADSHEET_ID   = CFG["spreadsheet_id"]
CENTRAL_EMAIL    = CFG["central_email"]
CENTRAL_PASSWORD = CFG["central_password"]
SENDER           = CFG.get("sender",    "sso@mirea.ru")
IMAP_HOST        = CFG.get("imap_host", "imap.mail.ru")
IMAP_PORT        = int(CFG.get("imap_port", "993"))


# ── Google Sheets ──────────────────────────────────────────────────────────────

def get_sheet():
    creds = Credentials.from_service_account_file(
        JSON_KEY,
        scopes=["https://www.googleapis.com/auth/spreadsheets"],
    )
    return gspread.authorize(creds).open_by_key(SPREADSHEET_ID).sheet1


def find_row(rows: list, edu_email: str) -> int | None:
    """Ищем строку по edu.mirea.ru-адресу в столбце B (без учёта регистра)."""
    edu_email = edu_email.lower()
    for i, row in enumerate(rows[1:], start=2):
        if len(row) >= 2 and row[1].lower().strip() == edu_email:
            return i
    return None


# ── Парсинг письма ─────────────────────────────────────────────────────────────

def parse_message(msg) -> tuple[str | None, str, str]:
    """Возвращает (код, время, edu-адрес получателя)."""
    # Код из темы
    subject = str(make_header(decode_header(msg["Subject"])))
    match   = re.match(r"(\d{6})", subject)
    code    = match.group(1) if match else None

    # Время в локальном часовом поясе
    date     = email.utils.parsedate_to_datetime(msg["Date"]).astimezone()
    time_str = date.strftime("%d.%m.%Y %H:%M")

    # Оригинальный получатель: "Имя <addr@edu.mirea.ru>" → "addr@edu.mirea.ru"
    _, to_addr = email.utils.parseaddr(msg.get("To", ""))
    to_addr = to_addr.lower().strip()

    return code, time_str, to_addr


# ── Обработка пачки новых писем ───────────────────────────────────────────────

def process_new(mail, known_last: bytes | None) -> bytes | None:
    """
    Забирает все письма от SENDER новее known_last,
    пишет коды в таблицу. Возвращает новый known_last.
    """
    _, ids = mail.search(None, f'FROM "{SENDER}"')
    if not ids[0]:
        return known_last

    all_ids = ids[0].split()

    # Берём только то, что пришло после последнего известного ID
    if known_last and known_last in all_ids:
        new_ids = all_ids[all_ids.index(known_last) + 1:]
    else:
        new_ids = all_ids

    if not new_ids:
        return known_last

    # Читаем таблицу один раз на всю пачку
    sheet = get_sheet()
    rows  = sheet.get_all_values()

    for msg_id in new_ids:
        _, data = mail.fetch(msg_id, "(RFC822)")
        msg = email.message_from_bytes(data[0][1])
        code, time_str, to_addr = parse_message(msg)

        if not code:
            print(f"  ⚠  Код не найден в письме (To: {to_addr})")
            continue

        row_idx = find_row(rows, to_addr)
        if row_idx:
            sheet.update(range_name=f"D{row_idx}:E{row_idx}", values=[[code, time_str]])
            print(f"  ✓  {to_addr}  →  {code}  ({time_str})")
        else:
            print(f"  ⚠  Адрес не найден в таблице: {to_addr}")

    return new_ids[-1]


# ── Главный цикл ───────────────────────────────────────────────────────────────

def main():
    print(f"Центральный ящик: {CENTRAL_EMAIL}")
    print("Нажмите Ctrl+C для остановки.\n")

    while True:
        mail = None
        try:
            print("Подключение к IMAP...")
            mail = imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT)
            mail.login(CENTRAL_EMAIL, CENTRAL_PASSWORD)
            mail.select("INBOX")

            # Текущая база — запоминаем последний ID чтобы не дублировать
            _, ids   = mail.search(None, f'FROM "{SENDER}"')
            known_last = ids[0].split()[-1] if ids[0] else None

            print("Ожидание писем (IMAP IDLE)...")

            while True:
                # ── IDLE ──
                tag = mail._new_tag().decode()
                mail.send(f"{tag} IDLE\r\n".encode())

                resp = mail.readline()
                if b"+" not in resp:
                    raise ConnectionError(f"Сервер не поддерживает IDLE: {resp!r}")

                # Ждём уведомление; через 29 мин переотправляем IDLE сами
                mail.socket().settimeout(29 * 60)
                got_new = False
                try:
                    while True:
                        line = mail.readline()
                        if b"EXISTS" in line or b"RECENT" in line:
                            got_new = True
                            break
                        if b"BYE" in line:
                            raise ConnectionError("Сервер закрыл соединение (BYE)")
                except socket.timeout:
                    pass
                finally:
                    mail.socket().settimeout(None)

                # Выходим из IDLE
                mail.send(b"DONE\r\n")
                while True:
                    line = mail.readline()
                    if tag.encode() in line:
                        break

                if got_new:
                    known_last = process_new(mail, known_last)

        except Exception as exc:
            print(f"Ошибка: {exc}")
        finally:
            if mail:
                try:
                    mail.logout()
                except Exception:
                    pass

        print("Переподключение через 10 сек...\n")
        time.sleep(10)


if __name__ == "__main__":
    main()

import imaplib
import email
import email.utils
from email.header import decode_header, make_header
import configparser
import re
import threading
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

CFG            = load_config()
JSON_KEY       = CFG["json_key"]
SPREADSHEET_ID = CFG["spreadsheet_id"]
SENDER         = CFG.get("sender", "sso@mirea.ru")
IMAP_HOST      = CFG.get("imap_host", "imap.mail.ru")
IMAP_PORT      = int(CFG.get("imap_port", "993"))


# ── Google Sheets ──────────────────────────────────────────────────────────────

def get_sheet():
    creds = Credentials.from_service_account_file(
        JSON_KEY,
        scopes=["https://www.googleapis.com/auth/spreadsheets"],
    )
    return gspread.authorize(creds).open_by_key(SPREADSHEET_ID).sheet1


# ── Парсинг письма ─────────────────────────────────────────────────────────────

def parse_message(msg):
    subject = str(make_header(decode_header(msg["Subject"])))
    match   = re.match(r"(\d{6})", subject)
    code    = match.group(1) if match else None

    date     = email.utils.parsedate_to_datetime(msg["Date"]).astimezone()
    time_str = date.strftime("%d.%m.%Y %H:%M")

    return code, time_str


# ── IMAP IDLE worker ───────────────────────────────────────────────────────────

def idle_worker(email_addr: str, password: str, row_idx: int, sheet_lock: threading.Lock):
    def write_to_sheet(code: str, time_str: str):
        with sheet_lock:
            try:
                sheet = get_sheet()
                sheet.update(range_name=f"D{row_idx}:E{row_idx}", values=[[code, time_str]])
                print(f"[{email_addr}] ✓ Код: {code}  Время: {time_str}")
            except Exception as exc:
                print(f"[{email_addr}] Ошибка записи в таблицу: {exc}")

    while True:
        mail = None
        try:
            print(f"[{email_addr}] Подключение к IMAP...")
            mail = imaplib.IMAP4_SSL(IMAP_HOST, IMAP_PORT)
            mail.login(email_addr, password)
            mail.select("INBOX")

            _, ids     = mail.search(None, f'FROM "{SENDER}"')
            known_last = ids[0].split()[-1] if ids[0] else None

            print(f"[{email_addr}] Ожидание новых писем (IMAP IDLE)...")

            while True:
                tag = mail._new_tag().decode()
                mail.send(f"{tag} IDLE\r\n".encode())

                resp = mail.readline()
                if b"+" not in resp:
                    raise ConnectionError(f"Сервер не поддерживает IDLE: {resp!r}")

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

                mail.send(b"DONE\r\n")
                while True:
                    line = mail.readline()
                    if tag.encode() in line:
                        break

                if got_new:
                    _, ids = mail.search(None, f'FROM "{SENDER}"')
                    if ids[0]:
                        new_last = ids[0].split()[-1]
                        if new_last != known_last:
                            known_last = new_last
                            _, data = mail.fetch(new_last, "(RFC822)")
                            msg = email.message_from_bytes(data[0][1])
                            code, time_str = parse_message(msg)
                            if code:
                                write_to_sheet(code, time_str)
                            else:
                                print(f"[{email_addr}] Код не найден в письме")

        except Exception as exc:
            print(f"[{email_addr}] Ошибка: {exc}")
        finally:
            if mail:
                try:
                    mail.logout()
                except Exception:
                    pass

        print(f"[{email_addr}] Переподключение через 10 сек...")
        time.sleep(10)


# ── Точка входа ────────────────────────────────────────────────────────────────

def main():
    sheet_lock = threading.Lock()

    print("Читаем аккаунты из таблицы...")
    rows = get_sheet().get_all_values()

    threads = []
    for i, row in enumerate(rows[1:], start=2):
        if len(row) < 3 or not row[1] or not row[2]:
            continue
        t = threading.Thread(
            target=idle_worker,
            args=(row[1], row[2], i, sheet_lock),
            daemon=True,
            name=row[1],
        )
        t.start()
        threads.append(t)

    if not threads:
        print("Нет аккаунтов в таблице!")
        return

    print(f"\nЗапущено потоков: {len(threads)}. Ожидание писем... (Ctrl+C для выхода)\n")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nОстановка.")


if __name__ == "__main__":
    main()

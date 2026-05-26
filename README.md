# mirea-2fa-parser

Скрипт автоматически забирает 2FA-коды из писем `sso@mirea.ru` по IMAP и пишет их в Google Таблицу в реальном времени.

- **Протокол:** IMAP IDLE — сервер пушит уведомление, задержка ~1 сек
- **Масштаб:** один поток на аккаунт, 30 человек ≈ 150 MB RAM
- **Деплой:** один скрипт `install.sh` — сам ставит зависимости, создаёт конфиг и поднимает systemd

---

## Структура таблицы

| A | B | C | D | E |
|---|---|---|---|---|
| ФИО | Email (mail.ru) | App Password | **Код** ← скрипт | **Время** ← скрипт |

---

## Подготовка (один раз)

### 1. App Password для Mail.ru

Mail.ru не принимает основной пароль через IMAP — нужен отдельный пароль приложения.

1. Войди в аккаунт → **Настройки** → **Безопасность**
2. **Пароли для внешних приложений** → **Добавить**
3. Название: `IMAP parser` → скопируй сгенерированный пароль
4. Вставь его в столбец **C** таблицы

### 2. Google Service Account (JSON-ключ)

1. Открой [console.cloud.google.com](https://console.cloud.google.com)
2. Создай проект → **APIs & Services → Enable APIs** → включи **Google Sheets API**
3. **Credentials → Create Credentials → Service Account**
4. В сервис-аккаунте: вкладка **Keys → Add Key → JSON** → скачай файл
5. Открой Google Таблицу → **Поделиться** → добавь email сервис-аккаунта с правами **Редактор**

---

## Установка

```bash
git clone https://github.com/KoPt2525/mirea-2fa-parser.git
cd mirea-2fa-parser
chmod +x install.sh
./install.sh
```

Скрипт сделает всё сам:

```
╔══════════════════════════════════════════════╗
║         mirea-2fa-parser  installer          ║
╚══════════════════════════════════════════════╝

  → Проверяю Python 3...
  ✓ Python: Python 3.11.2
  → Устанавливаю зависимости...
  ✓ gspread, google-auth установлены

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Шаг 1 из 2: JSON-ключ сервис-аккаунта Google
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Вставь содержимое JSON-ключа, затем Ctrl+D:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Шаг 2 из 2: ID Google Таблицы
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Введи ID таблицы: 1p04Dq6tQ...

  ✓ Доступ к таблице подтверждён
  ✓ Сервис запущен и добавлен в автозапуск

╔══════════════════════════════════════════════╗
║             Установка завершена!             ║
╚══════════════════════════════════════════════╝
```

---

## Управление сервисом

```bash
# Логи в реальном времени
sudo journalctl -u mirea-parser -f

# Статус
sudo systemctl status mirea-parser

# Остановить / запустить / перезапустить
sudo systemctl stop    mirea-parser
sudo systemctl start   mirea-parser
sudo systemctl restart mirea-parser
```

---

## Конфиг

После установки настройки хранятся в `config.ini` — редактировать Python-код не нужно:

```ini
[mirea]
json_key       = /home/user/.config/mirea-parser/key.json
spreadsheet_id = 1p04Dq6tQXRD13s4I0msoa5GBPvdp6ILVnfZmrpy0j-Y
sender         = sso@mirea.ru
imap_host      = imap.mail.ru
imap_port      = 993
```

После изменения конфига — перезапустить сервис:
```bash
sudo systemctl restart mirea-parser
```

---

## Требования к VPS

| Параметр | Минимум |
|----------|---------|
| RAM | 256 MB |
| CPU | любой |
| OS | Ubuntu 22.04 / Debian 12 |
| Python | 3.8+ |

30 аккаунтов ≈ 150 MB RAM, CPU ≈ 0% в простое.

---

## Безопасность

- Пароли от почты хранятся **только в Google Таблице**, не в коде
- JSON-ключ сохраняется с правами `600` (только владелец)
- SSH на VPS: рекомендуется вход только по ключу

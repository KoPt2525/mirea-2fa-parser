# mirea-2fa-parser

Скрипт автоматически забирает 2FA-коды из писем `sso@mirea.ru` по IMAP и пишет их в Google Таблицу в реальном времени.

- **Протокол:** IMAP IDLE — сервер пушит уведомление, задержка ~1 сек
- **Масштаб:** один поток на аккаунт, 30 человек ≈ 150 MB RAM
- **Деплой:** systemd-сервис, автозапуск при перезагрузке VPS

---

## Структура таблицы

| A | B | C | D | E |
|---|---|---|---|---|
| ФИО | Email (mail.ru) | App Password | **Код** | **Время** |

Столбцы D и E заполняются скриптом автоматически.

---

## Подготовка

### 1. App Password для Mail.ru

Mail.ru не принимает основной пароль через IMAP — нужен отдельный пароль приложения.

1. Войди в аккаунт → **Настройки** → **Безопасность**
2. Раздел **Пароли для внешних приложений** → **Добавить**
3. Название: `IMAP parser` → скопируй сгенерированный пароль
4. Вставь его в столбец **C** таблицы

### 2. Google Service Account (JSON-ключ)

1. Открой [console.cloud.google.com](https://console.cloud.google.com)
2. Создай проект → **APIs & Services** → **Enable APIs** → включи **Google Sheets API**
3. **Credentials** → **Create Credentials** → **Service Account**
4. В сервис-аккаунте: вкладка **Keys** → **Add Key** → **JSON** → скачай файл
5. Открой Google Таблицу → **Поделиться** → добавь email сервис-аккаунта с правами **Редактор**

---

## Установка

```bash
git clone https://github.com/KoPt/mirea-2fa-parser.git
cd mirea-2fa-parser
pip3 install -r requirements.txt
```

Отредактируй `parser.py` — укажи пути:

```python
JSON_KEY       = "/путь/до/ключ.json"
SPREADSHEET_ID = "ID_таблицы_из_URL"
```

ID таблицы — часть URL между `/d/` и `/edit`:
```
https://docs.google.com/spreadsheets/d/1p04Dq6tQXRD.../edit
                                        ^^^^^^^^^^^^^^
```

Запуск вручную для проверки:

```bash
python3 parser.py
```

---

## Деплой на VPS (systemd)

```bash
# Копируем файлы на сервер
scp parser.py user@<IP>:~/
scp ключ.json user@<IP>:~/
scp mirea-parser.service user@<IP>:~/

# На сервере
pip3 install -r requirements.txt
chmod 600 ~/ключ.json

sudo cp mirea-parser.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mirea-parser
sudo systemctl start mirea-parser
```

Логи в реальном времени:

```bash
sudo journalctl -u mirea-parser -f
```

---

## Требования к VPS

| Параметр | Минимум |
|----------|---------|
| RAM | 256 MB |
| CPU | любой |
| OS | Ubuntu 22.04 / Debian 12 |
| Python | 3.8+ |

---

## Безопасность

- Пароли от почты хранятся **только в Google Таблице**, не в коде
- JSON-ключ на VPS: `chmod 600 ключ.json`
- SSH на VPS: только по ключу, не по паролю
- Доступ к таблице: только через сервис-аккаунт с минимальными правами

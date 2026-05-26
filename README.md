# mirea-2fa-parser

Скрипт забирает 2FA-коды из писем `sso@mirea.ru` в реальном времени и пишет их в Google Таблицу.

**Архитектура:** все участники пересылают письма от `sso@mirea.ru` на один центральный ящик. Скрипт держит одно IMAP IDLE-соединение с ним и при появлении каждого нового письма определяет получателя по заголовку `To:`, находит его строку в таблице и вписывает код.

```
sso@mirea.ru → ivanov@edu.mirea.ru ──┐
sso@mirea.ru → petrov@edu.mirea.ru ──┼──▶ central@mail.ru ──▶ скрипт ──▶ таблица
sso@mirea.ru → sidorov@edu.mirea.ru ─┘
                                         1 соединение    ~1 сек задержки
```

---

## Структура таблицы

| A | B | C | D | E |
|---|---|---|---|---|
| ФИО | **@edu.mirea.ru** | *(не нужен)* | **Код** ← скрипт | **Время** ← скрипт |

> Столбец B — адрес `@edu.mirea.ru`, именно на него МИРЭА отправляет код.  
> App-пароли от личных ящиков в таблице **не хранятся**.

---

## Подготовка

### 1. Центральный ящик mail.ru

Заведи (или используй существующий) ящик `@mail.ru`, на который все будут пересылать коды.

Создай для него **App Password** (не основной пароль):
1. Настройки аккаунта → **Безопасность**
2. **Пароли для внешних приложений** → **Добавить** → скопируй пароль

### 2. Пересылка у каждого участника

Каждый участник настраивает фильтр в своём `@edu.mirea.ru` или привязанном `@mail.ru`:

> **Письма от:** `sso@mirea.ru` → **Переслать на:** `central@mail.ru`

### 3. Google Service Account

1. [console.cloud.google.com](https://console.cloud.google.com) → создай проект
2. **APIs & Services → Enable APIs** → включи **Google Sheets API**
3. **Credentials → Create Credentials → Service Account**
4. Вкладка **Keys → Add Key → JSON** → скачай файл
5. В таблице: **Поделиться** → добавь email сервис-аккаунта с правами **Редактор**

---

## Установка

```bash
git clone https://github.com/KoPt2525/mirea-2fa-parser.git
cd mirea-2fa-parser
chmod +x install.sh
./install.sh
```

Три шага в интерактивном режиме:

```
Шаг 1 из 3: JSON-ключ  →  вставляешь содержимое файла в терминал (Ctrl+D)
Шаг 2 из 3: Центральный ящик  →  email + app password
Шаг 3 из 3: ID таблицы  →  вставляешь из URL

  ✓ IMAP: OK
  ✓ Таблица: OK (31 строк)
  ✓ Сервис запущен и добавлен в автозапуск
```

---

## Управление

```bash
sudo journalctl -u mirea-parser -f      # логи в реальном времени
sudo systemctl status  mirea-parser     # статус
sudo systemctl restart mirea-parser     # перезапуск (после правки config.ini)
sudo systemctl stop    mirea-parser     # остановить
```

---

## Конфиг

`config.ini` создаётся автоматически через `install.sh`. При необходимости отредактировать вручную:

```ini
[mirea]
central_email    = central@mail.ru
central_password = app_password
json_key         = /home/user/.config/mirea-parser/key.json
spreadsheet_id   = 1p04Dq6tQ...
sender           = sso@mirea.ru
imap_host        = imap.mail.ru
imap_port        = 993
```

После изменений: `sudo systemctl restart mirea-parser`

---

## Требования к VPS

| Параметр | Минимум |
|----------|---------|
| RAM | 128 MB (одно соединение вместо 30) |
| OS | Ubuntu 22.04 / Debian 12 |
| Python | 3.8+ |

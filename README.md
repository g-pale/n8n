# Развертывание n8n на Ubuntu 22.04

Инструкция по развертыванию n8n self-hosted через Docker Compose.

**Важно**: Все скрипты универсальны и не содержат захардкоженных IP адресов или доменов.  
Перед использованием укажите ваш IP/домен через переменные окружения или отредактируйте скрипты.

**💡 Локальные скрипты**: Для удобства можно создать локальные версии скриптов с реальными данными в директории `local/`.  
Эти файлы автоматически исключены из git и не попадут в репозиторий. См. `local/README.md` для подробностей.

## ⚠️ Важно: Секретные данные

**Никогда не коммитьте в репозиторий:**
- Файл `.env` с реальными ключами и паролями
- Файлы с секретами (`.key`, `.pem`, и т.д.)
- Бэкапы конфигураций с реальными данными

Используйте `.env.example` как шаблон для создания `.env` файла на сервере.

## Быстрый старт

1. **Скопируйте шаблон переменных окружения:**
   ```bash
   cp .env.example .env
   ```

2. **Сгенерируйте ключи и заполните `.env`:**
   ```bash
   # Ключ шифрования
   openssl rand -hex 32
   
   # Пароль для входа в UI
   openssl rand -base64 24
   ```
   
   Откройте `.env` и замените `CHANGE_ME` на сгенерированные значения, а также укажите ваш IP или домен:
   ```env
   N8N_HOST=your-server-ip  # или ваш домен
   WEBHOOK_URL=http://your-server-ip:5678/  # или https://yourdomain.com/
   N8N_ENCRYPTION_KEY=<вставьте_сгенерированный_ключ>
   N8N_BASIC_AUTH_PASSWORD=<вставьте_сгенерированный_пароль>
   ```

3. **Запустите n8n:**
   ```bash
   docker compose up -d
   ```

4. **Проверьте работу:**
   ```bash
   # Проверка статуса
   docker ps
   
   # Проверка доступности
   curl -I http://YOUR_SERVER_IP:5678
   
   # Просмотр логов
   docker logs -f n8n
   ```

5. **Откройте в браузере:**
   - `http://YOUR_SERVER_IP:5678` (для IP)
   - или `https://yourdomain.com` (для домена)
   
   Логин: `admin` (или значение из `N8N_BASIC_AUTH_USER`)  
   Пароль: значение из `N8N_BASIC_AUTH_PASSWORD`

## Настройка SSH

### 1. Настройка SSH алиаса (рекомендуется)

Создайте или отредактируйте файл `~/.ssh/config`:

```bash
nano ~/.ssh/config
```

Добавьте конфигурацию:

```
Host n8n-selectel
    HostName your-server-ip
    User root
    IdentityFile ~/.ssh/your_key
```

После настройки все скрипты будут использовать алиас `n8n-selectel` по умолчанию.

### 2. Настройка SSH ключа (чтобы не вводить пароль)

Если при подключении `ssh n8n-selectel` требуется ввод пароля, настройте SSH ключ:

```bash
./copy-ssh-key.sh
```

Скрипт попросит ввести пароль один раз и скопирует ваш SSH ключ на сервер.  
После этого подключение будет работать без пароля.

**Альтернативный способ (если sshpass не установлен):**

1. Подключитесь к серверу: `ssh n8n-selectel`
2. На сервере выполните:
   ```bash
   mkdir -p ~/.ssh
   chmod 700 ~/.ssh
   nano ~/.ssh/authorized_keys
   ```
3. Вставьте ваш публичный ключ (покажите его: `cat ~/.ssh/id_ed25519.pub`)
4. Сохраните файл и установите права: `chmod 600 ~/.ssh/authorized_keys`

### 3. Использование другого SSH алиаса

Если используете другой алиас, укажите его через переменную окружения:
```bash
SSH_HOST=ваш-алиас ./deploy.sh
```

## Переменные окружения для скриптов

Все скрипты используют переменные окружения для указания IP адресов и доменов:

- `SERVER_IP` - IP адрес сервера (для `deploy.sh`, `setup-https.sh`, `manual-deploy.sh`, `copy-ssh-key.sh`, `setup-ssh.sh`)
- `DOMAIN` - домен (для `setup-https.sh`)
- `SUBDOMAIN` - поддомен для n8n (для `enable-https.sh`, `setup-https.sh`)
- `SSH_HOST` - SSH алиас или хост (для всех скриптов, по умолчанию `n8n-selectel`)

**Примеры использования:**

```bash
# Развертывание с указанием IP
SERVER_IP=192.168.1.100 ./deploy.sh

# Подготовка HTTPS с указанием IP и домена
SERVER_IP=192.168.1.100 DOMAIN=example.com ./setup-https.sh

# Включение HTTPS с указанием поддомена
SUBDOMAIN=n8n.example.com ./enable-https.sh
```

**Альтернатива**: Отредактируйте скрипты и замените `YOUR_SERVER_IP`, `YOUR_DOMAIN`, `YOUR_SUBDOMAIN` на ваши значения.

## 💡 Локальные скрипты (опционально)

Для удобства можно использовать локальные версии скриптов с реальными данными:

1. **Создайте директорию `local/`** (если еще не создана)
2. **Скопируйте нужные скрипты** из корня проекта в `local/`
3. **Отредактируйте их**, заменив `YOUR_SERVER_IP`, `YOUR_DOMAIN` на реальные значения
4. **Используйте**: `./local/deploy.sh`, `./local/setup-https.sh` и т.д.

**Важно**: Директория `local/` автоматически исключена из git через `.gitignore`, поэтому ваши реальные данные не попадут в репозиторий.

**Примечание**: В проекте уже есть примеры локальных скриптов в директории `local/` с реальными данными (если вы их создали). Они не попадут в git.

## Варианты развертывания

### Вариант 1: Автоматическое развертывание

**Перед запуском укажите IP адрес или домен вашего сервера:**

```bash
SERVER_IP=your-server-ip ./deploy.sh
```

Или отредактируйте скрипт `deploy.sh` и замените `YOUR_SERVER_IP` на ваш IP/домен.

**Если при подключении `ssh n8n-selectel` требуется ввод пароля:**

Сначала настройте SSH ключ (чтобы не вводить пароль каждый раз):

```bash
./copy-ssh-key.sh
```

Скрипт попросит ввести пароль один раз и скопирует ваш SSH ключ на сервер.  
После этого подключение будет работать без пароля.

**После настройки SSH ключа** запустите развертывание:

```bash
SERVER_IP=your-server-ip ./deploy.sh
```

**Если не хотите настраивать SSH ключ:**
- Используйте ручное развертывание (см. Вариант 2) - оно покажет все команды для выполнения на сервере
- Или используйте панель управления хостингом (VPS панель, Cloud Console и т.д.)

Скрипт автоматически:
- Обновит систему
- Установит Docker и Docker Compose
- Настроит firewall
- Сгенерирует ключи шифрования и пароль
- Запустит n8n

**Важно**: Скрипт покажет сгенерированные ключи - обязательно сохраните их!

### Вариант 2: Ручное развертывание (рекомендуется, если нет SSH ключа)

Если у вас нет настроенного SSH доступа, используйте скрипт для генерации команд:

```bash
./manual-deploy.sh
```

Скрипт сгенерирует все необходимые команды, которые нужно скопировать и выполнить на сервере вручную. Это самый надежный способ, если вы только начинаете работать с сервером.

## Детальное ручное развертывание

### 1) Подключиться по SSH

```bash
ssh root@your-server-ip
```
(замените `your-server-ip` на IP адрес вашего сервера)

### 2) Обновить систему и поставить базовые утилиты

```bash
apt update && apt -y upgrade
apt -y install ca-certificates curl ufw nano
```

### 3) Firewall (открыть SSH и порт 5678)

```bash
ufw allow OpenSSH
ufw allow 5678/tcp
ufw --force enable
ufw status
```

Ожидаемо: разрешены 22/tcp и 5678/tcp.

### 4) Установить Docker + Docker Compose

```bash
curl -fsSL https://get.docker.com | sh
docker --version
docker compose version
```

### 5) Создать директорию и файлы конфигурации

```bash
mkdir -p /opt/n8n && cd /opt/n8n
```

#### 5.1 Сгенерировать ключ шифрования и пароль

Сгенерировать **N8N_ENCRYPTION_KEY**:

```bash
openssl rand -hex 32
```

Сгенерировать пароль для входа:

```bash
openssl rand -base64 24
```

**Важно**: Сохраните эти значения! Ключ шифрования нельзя менять после запуска.

#### 5.2 Создать `.env` файл

```bash
nano .env
```

Вставьте (замените значения на сгенерированные):

```env
N8N_ENCRYPTION_KEY=<ваш_ключ_шифрования>
N8N_BASIC_AUTH_PASSWORD=<ваш_пароль>
```

#### 5.3 Создать `docker-compose.yml`

Скопируйте файл `docker-compose.yml` из этого репозитория на сервер:

```bash
# Если клонировали репозиторий на сервер
cp docker-compose.yml /opt/n8n/

# Или скопируйте содержимое файла вручную
nano /opt/n8n/docker-compose.yml
```

**Важно**: `docker-compose.yml` использует переменные из `.env` файла, поэтому убедитесь, что `.env` заполнен правильно.

### 6) Запустить n8n

```bash
docker compose up -d
docker ps
```

Логи (на случай проверки):

```bash
docker logs -f --tail=200 n8n
```

### 7) Проверка в браузере

Откройте на компьютере:

* `http://your-server-ip:5678`
(замените `your-server-ip` на IP адрес вашего сервера)

Должен запросить логин/пароль (basic auth). Вводите:

* user: `admin`
* password: тот, что указали в `N8N_BASIC_AUTH_PASSWORD`

### 8) Проверка автозапуска после перезагрузки

Перезагрузка сервера:

```bash
reboot
```

Заново подключиться по SSH и проверить:

```bash
ssh root@your-server-ip
docker ps
```
(замените `your-server-ip` на IP адрес вашего сервера)

Ожидаемо: контейнер `n8n` в статусе Up, UI доступен.

## Диагностика

Если UI не открывается:

### 1. Порт слушается?

```bash
ss -lntp | grep 5678
```

### 2. Firewall пропускает?

```bash
ufw status
```

### 3. Контейнер жив?

```bash
docker ps
docker logs --tail=200 n8n
```

### 4. Проверка переменных окружения

```bash
cd /opt/n8n
docker compose config
```

### 5. Проверка HTTPS (если настроен)

```bash
# Проверка доступности HTTPS
curl -I https://n8n.yourdomain.com

# Проверка сертификата
openssl s_client -connect n8n.yourdomain.com:443 -servername n8n.yourdomain.com < /dev/null 2>/dev/null | openssl x509 -noout -dates
```
(замените `n8n.yourdomain.com` на ваш поддомен)

# Логи Caddy
docker logs --tail=50 caddy
```

## Рекомендации по безопасности

После того как убедитесь, что всё работает:

1. **SSH ключи**: включить вход по SSH-ключу, запретить парольный вход
2. **HTTPS**: настроить домен и HTTPS через Caddy (см. раздел "Настройка домена и HTTPS")
3. **Backup**: настроить регулярное резервное копирование данных n8n

## Полезные команды

### Остановить n8n

```bash
cd /opt/n8n
docker compose down
```

### Перезапустить n8n

```bash
cd /opt/n8n
docker compose restart
```

### Обновить n8n

```bash
cd /opt/n8n
docker compose pull
docker compose up -d
```

### Просмотр логов

```bash
# Логи n8n
docker logs -f --tail=200 n8n

# Логи Caddy (если используется HTTPS)
docker logs -f --tail=200 caddy
```

### Резервное копирование данных

```bash
docker run --rm -v n8n_n8n_data:/data -v $(pwd):/backup ubuntu tar czf /backup/n8n-backup-$(date +%Y%m%d).tar.gz /data
```

### Восстановление из backup

```bash
docker run --rm -v n8n_n8n_data:/data -v $(pwd):/backup ubuntu tar xzf /backup/n8n-backup-YYYYMMDD.tar.gz -C /
```

## Настройка домена и HTTPS

После успешного развертывания n8n можно настроить домен и HTTPS.

### Шаг 1: Подготовка сервера (до настройки DNS)

**Перед запуском укажите IP адрес и домен:**

```bash
SERVER_IP=your-server-ip DOMAIN=yourdomain.com ./setup-https.sh
```

Или отредактируйте скрипт `setup-https.sh` и замените `YOUR_SERVER_IP` и `YOUR_DOMAIN`.

Скрипт выполнит:
- Откроет порты 80 и 443 в firewall
- Проверит/создаст файл `.env` с ключами
- Создаст бэкап текущей конфигурации
- Подготовит `Caddyfile` и `docker-compose.https.yml`

**Важно**: Порт 5678 останется открытым до настройки DNS, чтобы не потерять доступ.

### Шаг 2: Настройка DNS

В панели управления доменом добавьте A-запись:
- **Имя**: `n8n` (или `@` для корневого домена)
- **Тип**: `A`
- **Значение**: ваш IP адрес сервера
- **TTL**: `3600` (или по умолчанию)

Полный домен будет: `n8n.yourdomain.com` (замените `yourdomain.com` на ваш домен)

Дождитесь распространения DNS (обычно 5-30 минут). Проверить можно командой:
```bash
dig +short n8n.yourdomain.com @8.8.8.8
```
(замените `n8n.yourdomain.com` на ваш поддомен)

### Шаг 3: Включение HTTPS (после настройки DNS)

**Перед запуском укажите поддомен:**

```bash
SUBDOMAIN=n8n.yourdomain.com ./enable-https.sh
```

Или отредактируйте скрипт `enable-https.sh` и замените `YOUR_SUBDOMAIN`.

Скрипт выполнит:
- Остановит текущий n8n
- Переключит на HTTPS конфигурацию (Caddy)
- Запустит n8n с HTTPS
- Закроет порт 5678 в firewall

После этого n8n будет доступен **только** по адресу: `https://n8n.yourdomain.com` (замените на ваш поддомен)

**Важно**: После включения HTTPS порт 5678 будет закрыт в firewall, доступ по IP больше не будет работать.

## Структура проекта

```
.
├── .gitignore                  # Исключения для git
├── .env.example                # Шаблон файла с переменными окружения
├── docker-compose.yml          # Конфигурация Docker Compose (HTTP, на сервере)
├── docker-compose.https.yml    # Конфигурация для HTTPS (создается на сервере setup-https.sh)
├── Caddyfile                   # Конфигурация Caddy (создается на сервере setup-https.sh)
├── deploy.sh                   # Скрипт автоматического развертывания
├── setup-https.sh              # Подготовка домена и HTTPS
├── enable-https.sh              # Включение HTTPS (после настройки DNS)
├── manual-deploy.sh            # Генератор команд для ручного развертывания
├── copy-ssh-key.sh             # Скрипт настройки SSH ключа
├── setup-ssh.sh                # Альтернативный скрипт настройки SSH ключа
├── set-password.sh             # Скрипт установки пароля root на сервере
└── README.md                   # Эта инструкция
```

**Примечание**: Файлы `docker-compose.https.yml` и `Caddyfile` создаются на сервере в `/opt/n8n` при выполнении `setup-https.sh`.

## Конфигурация

### Переменные окружения

- `N8N_ENCRYPTION_KEY` - ключ шифрования (обязательно, генерируется один раз)
- `N8N_BASIC_AUTH_PASSWORD` - пароль для входа в UI
- `N8N_HOST` - IP адрес или домен сервера
- `WEBHOOK_URL` - базовый URL для webhooks

### Настройки выполнения

- `EXECUTIONS_DATA_SAVE_ON_SUCCESS=none` - не сохранять данные успешных выполнений
- `EXECUTIONS_DATA_SAVE_ON_ERROR=all` - сохранять данные ошибок
- `EXECUTIONS_DATA_PRUNE=true` - автоматически удалять старые выполнения
- `EXECUTIONS_DATA_MAX_AGE=168` - хранить выполнения 168 часов (7 дней)

## Поддержка

При возникновении проблем:

1. Проверьте логи: 
   - `docker logs n8n` (логи n8n)
   - `docker logs caddy` (логи Caddy, если используется HTTPS)
2. Проверьте статус контейнеров: `docker ps`
3. Проверьте firewall: `ufw status`
4. Проверьте порты: 
   - `ss -lntp | grep 5678` (для HTTP режима)
   - `ss -lntp | grep -E "80|443"` (для HTTPS режима)
5. Проверьте DNS (если используется домен): `dig +short n8n.yourdomain.com @8.8.8.8`
6. Проверьте доступность:
   - HTTP: `curl -I http://your-server-ip:5678`
   - HTTPS: `curl -I https://n8n.yourdomain.com`
(замените `your-server-ip` и `n8n.yourdomain.com` на ваши значения)

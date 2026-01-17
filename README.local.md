# Локальное развертывание n8n через Docker Desktop

Инструкция по запуску n8n на локальной машине (macOS, Windows, Linux) через Docker Desktop.

**Важно**: Этот файл содержит инструкции для локального развертывания.  
Для развертывания на сервере см. основной [README.md](README.md).

## Требования

- **Docker Desktop** установлен и запущен
  - macOS: [Скачать Docker Desktop для Mac](https://www.docker.com/products/docker-desktop/)
  - Windows: [Скачать Docker Desktop для Windows](https://www.docker.com/products/docker-desktop/)
  - Linux: Docker и Docker Compose установлены

- **Git** (опционально, для клонирования репозитория)

## Быстрый старт

### 1. Подготовка проекта

Если вы клонировали репозиторий:

```bash
cd /path/to/n8n
```

Если у вас только файлы проекта, убедитесь, что в директории есть:
- `docker-compose.yml`
- `.env.example`

### 2. Создание файла `.env`

Скопируйте шаблон:

```bash
cp .env.example .env
```

### 3. Генерация секретов

Сгенерируйте ключ шифрования и пароль:

```bash
# Ключ шифрования (обязательно!)
openssl rand -hex 32

# Пароль для входа в UI
openssl rand -base64 24
```

**Важно**: Сохраните эти значения! Ключ шифрования (`N8N_ENCRYPTION_KEY`) нельзя менять после первого запуска, иначе вы потеряете доступ к зашифрованным данным.

### 4. Настройка `.env` файла

Откройте файл `.env` в текстовом редакторе и заполните значения:

```env
TZ=Europe/Moscow

# Для локального запуска используйте localhost
N8N_PROTOCOL=http
N8N_HOST=localhost
WEBHOOK_URL=http://localhost:5678/
N8N_SECURE_COOKIE=false

# Вставьте сгенерированные значения
N8N_ENCRYPTION_KEY=<вставьте_ключ_из_openssl_rand_hex_32>
N8N_BASIC_AUTH_PASSWORD=<вставьте_пароль_из_openssl_rand_base64_24>
N8N_BASIC_AUTH_USER=admin
```

**Пример заполненного `.env`:**

```env
TZ=Europe/Moscow
N8N_PROTOCOL=http
N8N_HOST=localhost
WEBHOOK_URL=http://localhost:5678/
N8N_SECURE_COOKIE=false
N8N_ENCRYPTION_KEY=a1b2c3d4e5f6...  # 64 символа
N8N_BASIC_AUTH_PASSWORD=MySecurePassword123!  # ваш пароль
N8N_BASIC_AUTH_USER=admin
```

### 5. Запуск n8n

Убедитесь, что Docker Desktop запущен, затем выполните:

```bash
docker compose up -d
```

Проверьте статус:

```bash
docker ps
```

Должен быть запущен контейнер `n8n` в статусе `Up`.

### 6. Открытие в браузере

Откройте в браузере:

**http://localhost:5678**

Введите:
- **Логин**: `admin` (или значение из `N8N_BASIC_AUTH_USER`)
- **Пароль**: значение из `N8N_BASIC_AUTH_PASSWORD` в файле `.env`

## ⚠️ Важно: Секретные данные

**Никогда не коммитьте в репозиторий:**
- Файл `.env` с реальными ключами и паролями
- Файлы с секретами

Файл `.env` автоматически исключен из git через `.gitignore`.

## Полезные команды

### Просмотр логов

```bash
# Логи n8n
docker logs -f --tail=200 n8n

# Логи в реальном времени
docker logs -f n8n
```

### Остановка n8n

```bash
docker compose down
```

### Перезапуск n8n

```bash
docker compose restart
```

Или полный перезапуск (с пересозданием контейнера):

```bash
docker compose down
docker compose up -d
```

### Обновление n8n

```bash
# Скачать новую версию образа
docker compose pull

# Перезапустить с новой версией
docker compose up -d
```

### Очистка данных (⚠️ удалит все workflows и данные!)

```bash
# Остановить контейнер
docker compose down

# Удалить volume с данными
docker volume rm n8n_n8n_data

# Запустить заново (создаст новый volume)
docker compose up -d
```

## Диагностика

### Контейнер не запускается

1. **Проверьте логи:**
   ```bash
   docker logs n8n
   ```

2. **Проверьте статус контейнера:**
   ```bash
   docker ps -a
   ```

3. **Проверьте, что порт 5678 свободен:**
   ```bash
   # macOS/Linux
   lsof -i :5678
   
   # Windows (в PowerShell)
   netstat -ano | findstr :5678
   ```

4. **Проверьте конфигурацию:**
   ```bash
   docker compose config
   ```

### UI не открывается

1. **Проверьте, что контейнер запущен:**
   ```bash
   docker ps | grep n8n
   ```

2. **Проверьте доступность:**
   ```bash
   curl -I http://localhost:5678
   ```

3. **Проверьте логи на ошибки:**
   ```bash
   docker logs --tail=50 n8n
   ```

4. **Проверьте переменные окружения:**
   ```bash
   docker exec n8n env | grep N8N
   ```

### Проблемы с паролем

Если забыли пароль или нужно его изменить:

1. Остановите контейнер:
   ```bash
   docker compose down
   ```

2. Отредактируйте `.env` и измените `N8N_BASIC_AUTH_PASSWORD`

3. Запустите заново:
   ```bash
   docker compose up -d
   ```

**Важно**: Изменение `N8N_ENCRYPTION_KEY` приведет к потере доступа к зашифрованным данным!

## Резервное копирование данных

### Создание бэкапа

```bash
# Создать директорию для бэкапов
mkdir -p backups

# Создать бэкап
docker run --rm \
  -v n8n_n8n_data:/data \
  -v $(pwd)/backups:/backup \
  ubuntu tar czf /backup/n8n-backup-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .
```

### Восстановление из бэкапа

```bash
# Остановить n8n
docker compose down

# Удалить старый volume (⚠️ удалит текущие данные!)
docker volume rm n8n_n8n_data

# Восстановить из бэкапа
docker run --rm \
  -v n8n_n8n_data:/data \
  -v $(pwd)/backups:/backup \
  ubuntu tar xzf /backup/n8n-backup-YYYYMMDD-HHMMSS.tar.gz -C /data

# Запустить n8n
docker compose up -d
```

## Использование с внешним доступом

Если вы хотите, чтобы n8n был доступен не только на localhost, но и из сети:

### Вариант 1: Изменить `N8N_HOST` на IP вашего компьютера

1. Узнайте IP адрес вашего компьютера:
   ```bash
   # macOS/Linux
   ipconfig getifaddr en0  # macOS
   ip addr show | grep "inet "  # Linux
   
   # Windows (в PowerShell)
   ipconfig
   ```

2. Обновите `.env`:
   ```env
   N8N_HOST=192.168.1.100  # ваш локальный IP
   WEBHOOK_URL=http://192.168.1.100:5678/
   ```

3. Перезапустите:
   ```bash
   docker compose down
   docker compose up -d
   ```

4. Откройте в браузере: `http://192.168.1.100:5678`

### Вариант 2: Использовать `0.0.0.0` (не рекомендуется для production)

Измените в `docker-compose.yml`:

```yaml
ports:
  - "0.0.0.0:5678:5678"  # вместо "5678:5678"
```

**Важно**: Это сделает n8n доступным из любой сети, к которой подключен ваш компьютер. Используйте только в доверенной сети!

## Структура данных

Данные n8n хранятся в Docker volume `n8n_n8n_data`. 

Расположение volume:
- **macOS**: `~/Library/Containers/com.docker.docker/Data/vms/0/data/docker/volumes/n8n_n8n_data/`
- **Windows**: `\\wsl$\docker-desktop-data\data\docker\volumes\n8n_n8n_data\`
- **Linux**: `/var/lib/docker/volumes/n8n_n8n_data/`

Для просмотра содержимого volume:

```bash
docker run --rm -v n8n_n8n_data:/data ubuntu ls -la /data
```

## Отличия от серверного развертывания

| Аспект | Локальное развертывание | Серверное развертывание |
|--------|------------------------|-------------------------|
| **Доступ** | `http://localhost:5678` | `http://IP:5678` или `https://domain.com` |
| **HTTPS** | Не требуется | Настраивается через Caddy |
| **Firewall** | Не требуется | Настраивается UFW |
| **SSH** | Не требуется | Требуется для развертывания |
| **Автозапуск** | Зависит от Docker Desktop | Настраивается через `restart: unless-stopped` |

## Следующие шаги

После успешного локального запуска:

1. **Изучите n8n**: создайте несколько простых workflows для тестирования
2. **Настройте резервное копирование**: используйте команды из раздела "Резервное копирование"
3. **Разверните на сервере**: см. основной [README.md](README.md) для production развертывания

## Поддержка

При возникновении проблем:

1. Проверьте логи: `docker logs n8n`
2. Проверьте статус контейнера: `docker ps`
3. Проверьте конфигурацию: `docker compose config`
4. Убедитесь, что Docker Desktop запущен и работает
5. Проверьте, что порт 5678 не занят другим приложением

## Дополнительные ресурсы

- [Официальная документация n8n](https://docs.n8n.io/)
- [Docker Compose документация](https://docs.docker.com/compose/)
- [Docker Desktop документация](https://docs.docker.com/desktop/)

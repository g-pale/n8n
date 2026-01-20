#!/usr/bin/env bash
# Скрипт для автоматического исправления проблем с сетью и конфигурацией n8n
# Использование: ./fix-config.sh

set -euo pipefail

COMPOSE_DIR="/opt/n8n"
cd "$COMPOSE_DIR"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
warn() { echo "⚠️  $*" >&2; }
info() { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
error() { echo "❌ $*" >&2; }

log "=== FIX CONFIG START ==="

# Проверка прав
if [ "$EUID" -ne 0 ]; then
    error "Скрипт должен запускаться от root или через sudo"
    exit 1
fi

# Определяем режим работы
IS_HTTPS=false
CADDY_RUNNING=false

# Проверяем наличие Caddyfile (признак HTTPS конфигурации) - проверяем первым
if [ -f "Caddyfile" ]; then
    IS_HTTPS=true
    log "Caddyfile найден - используется HTTPS режим"
fi

# Проверяем наличие docker-compose.https.yml или docker-compose.ip.yml (признак того, что был HTTPS)
if [ -f "docker-compose.https.yml" ] || [ -f "docker-compose.ip.yml" ]; then
    IS_HTTPS=true
    log "Найдены файлы HTTPS конфигурации"
fi

# Проверяем наличие запущенного контейнера Caddy
if docker ps --format '{{.Names}}' | grep -qx 'caddy'; then
    CADDY_RUNNING=true
    IS_HTTPS=true
    log "Обнаружен запущенный контейнер Caddy"
fi

# Проверяем наличие Caddy в compose файле
if [ -f "docker-compose.yml" ] && grep -q "^[[:space:]]*caddy:" docker-compose.yml; then
    IS_HTTPS=true
    log "Caddy найден в docker-compose.yml"
fi

# Определяем домен
DOMAIN="n8n.n8n-my-project.ru"  # значение по умолчанию
if [ -f .env ]; then
    set -a
    source .env 2>/dev/null || true
    set +a
    if [ -n "${N8N_HOST:-}" ] && [ "${N8N_HOST}" != "CHANGE_ME" ]; then
        DOMAIN="${N8N_HOST}"
        log "Домен из .env: ${DOMAIN}"
    fi
fi

# Пытаемся определить домен из Caddyfile
if [ -f "Caddyfile" ]; then
    CADDYFILE_DOMAIN=$(grep -E "^[^[:space:]#]+" Caddyfile | head -1 | awk '{print $1}' | tr -d '{' | tr -d '}')
    if [ -n "$CADDYFILE_DOMAIN" ] && [ "$CADDYFILE_DOMAIN" != "$DOMAIN" ]; then
        DOMAIN="$CADDYFILE_DOMAIN"
        log "Домен из Caddyfile: ${DOMAIN}"
    fi
fi

if [ "$IS_HTTPS" = true ]; then
    log "Режим: HTTPS"
    PROTOCOL="https"
else
    log "Режим: HTTP"
    PROTOCOL="http"
    DOMAIN=""  # Для HTTP домен не обязателен
fi

# 1. Остановка контейнеров
log "Остановка контейнеров..."
if docker ps --format '{{.Names}}' | grep -qE "^(n8n|caddy)$"; then
    docker compose down 2>/dev/null || true
    
    # Останавливаем orphan контейнер Caddy если есть
    if [ "$CADDY_RUNNING" = true ]; then
        docker stop caddy 2>/dev/null || true
        docker rm caddy 2>/dev/null || true
        log "Остановлен orphan контейнер Caddy"
    fi
else
    log "Контейнеры не запущены"
fi

# 2. Работа с .env файлом
log "Проверка .env файла..."
if [ ! -f .env ]; then
    warn ".env файл не найден, создаю новый..."
    
    # Генерируем ключи
    ENCRYPTION_KEY=$(openssl rand -hex 32)
    AUTH_PASSWORD=$(openssl rand -base64 24)
    
    cat > .env << ENVEOF
TZ=Europe/Moscow
N8N_PROTOCOL=${PROTOCOL}
N8N_HOST=${DOMAIN}
WEBHOOK_URL=${PROTOCOL}://${DOMAIN}/
N8N_SECURE_COOKIE=$([ "$IS_HTTPS" = true ] && echo "true" || echo "false")
N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
N8N_BASIC_AUTH_PASSWORD=${AUTH_PASSWORD}
N8N_BASIC_AUTH_USER=admin
ENVEOF
    
    success ".env файл создан с автоматически сгенерированными ключами"
    warn "ВАЖНО: Сохраните эти значения!"
    echo "  N8N_ENCRYPTION_KEY: ${ENCRYPTION_KEY}"
    echo "  N8N_BASIC_AUTH_PASSWORD: ${AUTH_PASSWORD}"
else
    log ".env файл существует, проверяю содержимое..."
    
    # Проверяем наличие обязательных переменных
    MISSING_VARS=()
    
    if ! grep -q "^N8N_ENCRYPTION_KEY=" .env; then
        MISSING_VARS+=("N8N_ENCRYPTION_KEY")
    fi
    
    if ! grep -q "^N8N_BASIC_AUTH_PASSWORD=" .env; then
        MISSING_VARS+=("N8N_BASIC_AUTH_PASSWORD")
    fi
    
    if [ "$IS_HTTPS" = true ]; then
        if ! grep -q "^N8N_HOST=" .env || grep -q "^N8N_HOST=$" .env; then
            MISSING_VARS+=("N8N_HOST")
        fi
        if ! grep -q "^WEBHOOK_URL=" .env || grep -q "^WEBHOOK_URL=$" .env; then
            MISSING_VARS+=("WEBHOOK_URL")
        fi
    fi
    
    if [ ${#MISSING_VARS[@]} -gt 0 ]; then
        warn "В .env отсутствуют переменные: ${MISSING_VARS[*]}"
        info "Обновляю .env файл..."
        
        # Создаем бэкап
        cp .env .env.bak.$(date +%Y%m%d-%H%M%S)
        
        # Читаем существующие значения из .env
        # Используем set -a для автоматического экспорта всех переменных
        set -a
        source .env 2>/dev/null || true
        set +a
        
        # Обновляем недостающие переменные
        if [ -z "${N8N_ENCRYPTION_KEY:-}" ] || [ "${N8N_ENCRYPTION_KEY}" = "CHANGE_ME" ]; then
            N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
            warn "Сгенерирован новый N8N_ENCRYPTION_KEY (старые зашифрованные данные будут недоступны!)"
        fi
        
        if [ -z "${N8N_BASIC_AUTH_PASSWORD:-}" ] || [ "${N8N_BASIC_AUTH_PASSWORD}" = "CHANGE_ME" ]; then
            N8N_BASIC_AUTH_PASSWORD=$(openssl rand -base64 24)
        fi
        
        if [ "$IS_HTTPS" = true ]; then
            # Для HTTPS режима обязательно нужны домен и URL
            if [ -z "${N8N_HOST:-}" ] || [ "${N8N_HOST}" = "CHANGE_ME" ]; then
                N8N_HOST="${DOMAIN}"
            fi
            if [ -z "${WEBHOOK_URL:-}" ] || [ "${WEBHOOK_URL}" = "CHANGE_ME" ]; then
                WEBHOOK_URL="${PROTOCOL}://${DOMAIN}/"
            fi
            N8N_PROTOCOL="${N8N_PROTOCOL:-https}"
            N8N_SECURE_COOKIE="${N8N_SECURE_COOKIE:-true}"
        else
            # Для HTTP режима эти переменные могут быть пустыми
            N8N_HOST="${N8N_HOST:-}"
            WEBHOOK_URL="${WEBHOOK_URL:-}"
            N8N_PROTOCOL="${N8N_PROTOCOL:-http}"
            N8N_SECURE_COOKIE="${N8N_SECURE_COOKIE:-false}"
        fi
        
        # Перезаписываем .env
        cat > .env << ENVEOF
TZ=${TZ:-Europe/Moscow}
N8N_PROTOCOL=${N8N_PROTOCOL}
N8N_HOST=${N8N_HOST}
WEBHOOK_URL=${WEBHOOK_URL}
N8N_SECURE_COOKIE=${N8N_SECURE_COOKIE}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER:-admin}
ENVEOF
        
        success ".env файл обновлен"
    else
        success ".env файл содержит все необходимые переменные"
    fi
fi

# 3. Работа с compose файлами (для HTTPS режима)
if [ "$IS_HTTPS" = true ]; then
    log "Настройка HTTPS конфигурации..."
    
    # Используем уже определенный DOMAIN
    SUBDOMAIN="${DOMAIN}"
    
    # Получаем версию n8n из текущего docker-compose.yml
    N8N_IMAGE_VERSION="2.3.5"
    if [ -f "docker-compose.yml" ]; then
        EXTRACTED_VERSION=$(grep -E "^[[:space:]]*image:[[:space:]]*docker\.n8n\.io/n8nio/n8n:" docker-compose.yml | sed -E 's/.*:([0-9.]+)$/\1/' | head -1)
        if [ -n "$EXTRACTED_VERSION" ]; then
            N8N_IMAGE_VERSION="$EXTRACTED_VERSION"
        fi
    fi
    
    if [ -f "docker-compose.https.yml" ]; then
        success "Найден docker-compose.https.yml"
        
        # Сохраняем старый docker-compose.yml если он не HTTPS
        if [ -f "docker-compose.yml" ] && ! grep -q "^[[:space:]]*caddy:" docker-compose.yml; then
            if [ ! -f "docker-compose.ip.yml" ]; then
                mv docker-compose.yml docker-compose.ip.yml
                success "Сохранен старый docker-compose.yml как docker-compose.ip.yml"
            else
                cp docker-compose.yml docker-compose.ip.yml.bak.$(date +%Y%m%d-%H%M%S)
                rm docker-compose.yml
            fi
        fi
        
        # Переключаемся на HTTPS конфигурацию
        if [ ! -f "docker-compose.yml" ] || ! grep -q "^[[:space:]]*caddy:" docker-compose.yml; then
            mv docker-compose.https.yml docker-compose.yml
            success "Переключено на HTTPS конфигурацию"
        else
            log "Уже используется HTTPS конфигурация"
        fi
    else
        warn "docker-compose.https.yml не найден, создаю автоматически..."
        
        # Сохраняем старый docker-compose.yml
        if [ -f "docker-compose.yml" ] && ! grep -q "^[[:space:]]*caddy:" docker-compose.yml; then
            if [ ! -f "docker-compose.ip.yml" ]; then
                mv docker-compose.yml docker-compose.ip.yml
                success "Сохранен старый docker-compose.yml как docker-compose.ip.yml"
            else
                cp docker-compose.yml docker-compose.ip.yml.bak.$(date +%Y%m%d-%H%M%S)
            fi
        fi
        
        # Создаем Caddyfile если его нет
        if [ ! -f "Caddyfile" ]; then
            log "Создание Caddyfile..."
            cat > Caddyfile << CADDYEOF
${SUBDOMAIN} {
    reverse_proxy n8n:5678 {
        header_up Host {host}
        header_up X-Real-IP {remote}
        header_up X-Forwarded-For {remote}
        header_up X-Forwarded-Proto {scheme}
    }
}
CADDYEOF
            success "Caddyfile создан для домена ${SUBDOMAIN}"
        else
            log "Caddyfile уже существует"
        fi
        
        # Создаем docker-compose.https.yml
        log "Создание docker-compose.https.yml..."
        cat > docker-compose.https.yml << COMPOSEEOF
services:
  caddy:
    image: caddy:2.10.2
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - n8n_network

  n8n:
    image: docker.n8n.io/n8nio/n8n:${N8N_IMAGE_VERSION}
    container_name: n8n
    restart: unless-stopped
    environment:
      - TZ=\${TZ:-Europe/Moscow}
      - N8N_PORT=5678

      - N8N_PROTOCOL=https
      - N8N_HOST=\${N8N_HOST}
      - WEBHOOK_URL=\${WEBHOOK_URL}

      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=\${N8N_BASIC_AUTH_USER:-admin}
      - N8N_BASIC_AUTH_PASSWORD=\${N8N_BASIC_AUTH_PASSWORD}

      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=none
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      - EXECUTIONS_DATA_SAVE_ON_PROGRESS=false
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168

      - N8N_SECURE_COOKIE=true
    volumes:
      - n8n_data:/home/node/.n8n
    expose:
      - "5678"
    networks:
      - n8n_network

volumes:
  n8n_data:
  caddy_data:
  caddy_config:

networks:
  n8n_network:
    name: n8n_network
    driver: bridge
COMPOSEEOF
        success "docker-compose.https.yml создан"
        
        # Переключаемся на HTTPS конфигурацию
        mv docker-compose.https.yml docker-compose.yml
        success "Переключено на HTTPS конфигурацию"
    fi
    
    # Проверяем наличие сети в compose файле
    if ! grep -q "n8n_network" docker-compose.yml; then
        warn "Сеть n8n_network не найдена в docker-compose.yml"
        warn "Убедитесь, что compose файл содержит определение сети"
    fi
fi

# 4. Работа с сетью (для HTTPS)
if [ "$IS_HTTPS" = true ]; then
    NETWORK_NAME="n8n_network"
    log "Проверка сети ${NETWORK_NAME}..."
    
    # Проверяем, существует ли сеть и создана ли она через Docker Compose
    if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
        # Проверяем метки сети (создана ли она через compose)
        NETWORK_LABEL=$(docker network inspect "$NETWORK_NAME" --format '{{index .Labels "com.docker.compose.network"}}' 2>/dev/null || echo "")
        
        if [ -z "$NETWORK_LABEL" ] || [ "$NETWORK_LABEL" != "n8n_network" ]; then
            warn "Сеть ${NETWORK_NAME} существует, но не создана через Docker Compose"
            
            # Проверяем, подключены ли контейнеры к сети
            CONTAINERS_IN_NETWORK=$(docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")
            
            if [ -n "$CONTAINERS_IN_NETWORK" ]; then
                warn "Сеть используется контейнерами: $CONTAINERS_IN_NETWORK"
                log "Помечаю сеть как external в compose файле..."
                
                # Помечаем сеть как external - заменяем name и driver на external: true
                if grep -q "driver: bridge" docker-compose.yml; then
                    # Создаем временный файл с правильной конфигурацией
                    TMP_COMPOSE=$(mktemp)
                    awk '
                        /^  n8n_network:/ {
                            print "  n8n_network:"
                            print "    external: true"
                            skip_next=1
                            next
                        }
                        skip_next && /^    (name|driver):/ { skip_next=0; next }
                        { print }
                    ' docker-compose.yml > "$TMP_COMPOSE"
                    
                    if grep -q "external: true" "$TMP_COMPOSE"; then
                        mv "$TMP_COMPOSE" docker-compose.yml
                        success "Сеть помечена как external в compose файле"
                    else
                        rm -f "$TMP_COMPOSE"
                        warn "Не удалось пометить сеть как external"
                    fi
                fi
            else
                log "Сеть не используется, удаляю для пересоздания через Docker Compose..."
                docker network rm "$NETWORK_NAME" 2>/dev/null && success "Сеть удалена" || warn "Не удалось удалить сеть"
            fi
        else
            success "Сеть ${NETWORK_NAME} уже существует и создана через Docker Compose"
        fi
    else
        log "Сеть ${NETWORK_NAME} не существует, будет создана через Docker Compose"
    fi
fi

# 5. Валидация compose конфигурации
log "Валидация docker-compose конфигурации..."
if docker compose config >/dev/null 2>&1; then
    success "Конфигурация docker-compose валидна"
else
    error "Ошибка в конфигурации docker-compose!"
    docker compose config
    exit 1
fi

# 6. Запуск контейнеров
if [ "$IS_HTTPS" = true ]; then
    log "Запуск контейнеров с принудительным пересозданием (для применения сети)..."
    docker compose down 2>/dev/null || true
    docker compose up -d --force-recreate --remove-orphans
else
    log "Запуск контейнеров..."
    docker compose up -d
fi

# Даем время на запуск
sleep 5

# 7. Проверка статуса
log "Проверка статуса контейнеров..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "NAMES|n8n|caddy" || true

# 8. Проверка сети (для HTTPS)
if [ "$IS_HTTPS" = true ]; then
    log "Проверка подключения контейнеров к сети..."
    
    NETWORK_NAME="n8n_network"
    if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
        CONTAINERS_IN_NETWORK=$(docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.Name}} {{end}}')
        
        N8N_IN_NETWORK=false
        CADDY_IN_NETWORK=false
        
        if echo "$CONTAINERS_IN_NETWORK" | grep -q "n8n"; then
            success "Контейнер n8n подключен к сети ${NETWORK_NAME}"
            N8N_IN_NETWORK=true
        else
            warn "Контейнер n8n НЕ подключен к сети ${NETWORK_NAME}"
        fi
        
        if echo "$CONTAINERS_IN_NETWORK" | grep -q "caddy"; then
            success "Контейнер caddy подключен к сети ${NETWORK_NAME}"
            CADDY_IN_NETWORK=true
        else
            warn "Контейнер caddy НЕ подключен к сети ${NETWORK_NAME}"
        fi
        
        if [ -n "$CONTAINERS_IN_NETWORK" ]; then
            info "Контейнеры в сети: $CONTAINERS_IN_NETWORK"
        fi
        
        # Если контейнеры не в сети, пытаемся подключить их вручную
        if [ "$N8N_IN_NETWORK" = false ] || [ "$CADDY_IN_NETWORK" = false ]; then
            warn "Попытка подключить контейнеры к сети вручную..."
            
            if [ "$N8N_IN_NETWORK" = false ] && docker ps --format '{{.Names}}' | grep -q "^n8n$"; then
                docker network connect "$NETWORK_NAME" n8n 2>/dev/null && success "n8n подключен к сети" || warn "Не удалось подключить n8n к сети"
            fi
            
            if [ "$CADDY_IN_NETWORK" = false ] && docker ps --format '{{.Names}}' | grep -q "^caddy$"; then
                docker network connect "$NETWORK_NAME" caddy 2>/dev/null && success "caddy подключен к сети" || warn "Не удалось подключить caddy к сети"
            fi
            
            # Проверяем еще раз
            CONTAINERS_IN_NETWORK=$(docker network inspect "$NETWORK_NAME" --format '{{range .Containers}}{{.Name}} {{end}}')
            if echo "$CONTAINERS_IN_NETWORK" | grep -q "n8n" && echo "$CONTAINERS_IN_NETWORK" | grep -q "caddy"; then
                success "Оба контейнера теперь в сети ${NETWORK_NAME}"
            else
                error "Не удалось подключить контейнеры к сети. Возможно, нужно пересоздать контейнеры вручную."
            fi
        fi
    else
        error "Сеть ${NETWORK_NAME} не существует!"
    fi
fi

# 9. Проверка логов (первые строки)
log "Проверка логов (первые 20 строк)..."
if docker ps --format '{{.Names}}' | grep -q "^n8n$"; then
    echo ""
    info "Логи n8n:"
    docker logs --tail=20 n8n 2>&1 | head -20 || true
fi

if [ "$IS_HTTPS" = true ] && docker ps --format '{{.Names}}' | grep -q "^caddy$"; then
    echo ""
    info "Логи caddy:"
    docker logs --tail=20 caddy 2>&1 | head -20 || true
fi

echo ""
log "=== FIX CONFIG DONE ==="
echo ""
success "Конфигурация исправлена!"
echo ""
info "Следующие шаги:"
echo "  1. Проверьте логи: docker logs -f n8n"
if [ "$IS_HTTPS" = true ]; then
    echo "  2. Проверьте логи Caddy: docker logs -f caddy"
    echo "  3. Проверьте доступность: curl -I https://${DOMAIN}/"
else
    echo "  2. Проверьте доступность: curl -I http://localhost:5678/"
fi
echo "  4. Если нужно изменить пароль или домен, отредактируйте .env и перезапустите:"
echo "     docker compose restart"

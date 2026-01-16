#!/bin/bash

# Скрипт подготовки домена и HTTPS для n8n
# Использование: ./setup-https.sh

set -e

SSH_HOST="${SSH_HOST:-n8n-selectel}"
# IP адрес сервера (можно указать через переменную окружения)
SERVER_IP="${SERVER_IP:-YOUR_SERVER_IP}"
# Домен (можно указать через переменную окружения)
DOMAIN="${DOMAIN:-YOUR_DOMAIN}"
# Поддомен для n8n (можно указать через переменную окружения)
SUBDOMAIN="${SUBDOMAIN:-n8n.${DOMAIN}}"
N8N_DIR="/opt/n8n"

# Проверка наличия значений
if [ "$SERVER_IP" = "YOUR_SERVER_IP" ] || [ "$DOMAIN" = "YOUR_DOMAIN" ]; then
    echo "❌ Ошибка: не указан IP адрес или домен"
    echo ""
    echo "Укажите значения через переменные окружения:"
    echo "   SERVER_IP=your-server-ip DOMAIN=yourdomain.com ./setup-https.sh"
    echo ""
    echo "Или отредактируйте скрипт и замените YOUR_SERVER_IP и YOUR_DOMAIN"
    exit 1
fi

echo "🔐 Подготовка домена и HTTPS для n8n"
echo "📡 SSH хост: $SSH_HOST"
echo "🌐 Домен: $SUBDOMAIN"
echo "📍 IP: $SERVER_IP"
echo ""

# Проверка подключения
echo "📡 Проверка подключения к серверу..."
if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes "$SSH_HOST" "echo 'Connected'" 2>/dev/null; then
    echo "⚠️  Не удалось подключиться по SSH ключу (BatchMode)."
    echo "   Попробую подключиться с возможностью ввода пароля..."
    echo ""
    if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_HOST" "echo 'Connected'" 2>/dev/null; then
        echo "❌ Не удалось подключиться к серверу."
        echo "   Убедитесь, что:"
        echo "   1. SSH ключ настроен: ./copy-ssh-key.sh"
        echo "   2. Или вы можете подключиться вручную: ssh $SSH_HOST"
        exit 1
    fi
fi

echo "✅ Подключение установлено"
echo ""

# Выполнение команд на сервере
echo "🔧 Выполнение команд на сервере..."
echo "   (Если будет запрошен пароль, введите его)"
echo ""
ssh -o StrictHostKeyChecking=no "$SSH_HOST" << EOF
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "A1) Настройка UFW: открытие портов 80 и 443"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ufw allow 80/tcp
ufw allow 443/tcp
echo ""
echo "Текущий статус firewall:"
ufw status
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "A2) Проверка и создание .env файла"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd $N8N_DIR

if [ -f .env ]; then
    echo "✅ Файл .env уже существует"
    echo "Проверка синтаксиса docker-compose.yml..."
    docker compose config >/dev/null && echo "✅ docker-compose.yml синтаксис корректен"
else
    echo "⚠️  Файл .env не найден. Создаю..."
    echo ""
    echo "Генерация ключей..."
    ENCRYPTION_KEY=\$(openssl rand -hex 32)
    AUTH_PASSWORD=\$(openssl rand -base64 24)
    
    echo ""
    echo "⚠️  ВАЖНО: Сохраните эти значения!"
    echo "N8N_ENCRYPTION_KEY: \$ENCRYPTION_KEY"
    echo "N8N_BASIC_AUTH_PASSWORD: \$AUTH_PASSWORD"
    echo ""
    
    cat > .env << ENVEOF
N8N_ENCRYPTION_KEY=\$ENCRYPTION_KEY
N8N_BASIC_AUTH_PASSWORD=\$AUTH_PASSWORD
ENVEOF
    
    echo "✅ Файл .env создан"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "A3) Подготовка файлов для HTTPS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cd $N8N_DIR

echo "A3.1) Создание бэкапа docker-compose.yml..."
if [ -f docker-compose.yml ]; then
    cp docker-compose.yml docker-compose.yml.bak
    echo "✅ Бэкап создан: docker-compose.yml.bak"
else
    echo "⚠️  docker-compose.yml не найден, пропускаю бэкап"
fi
echo ""

echo "A3.2) Создание Caddyfile..."
cat > Caddyfile << CADDYEOF
$SUBDOMAIN {
  reverse_proxy n8n:5678
}
CADDYEOF
echo "✅ Caddyfile создан"
echo ""

echo "A3.3) Создание docker-compose.https.yml..."
cat > docker-compose.https.yml << COMPOSEEOF
services:
  caddy:
    image: caddy:2
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
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    environment:
      - TZ=Europe/Moscow
      - N8N_PORT=5678

      - N8N_PROTOCOL=https
      - N8N_HOST=$SUBDOMAIN
      - WEBHOOK_URL=https://$SUBDOMAIN/

      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
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
    driver: bridge
COMPOSEEOF
echo "✅ docker-compose.https.yml создан"
echo ""

echo "A3.4) Проверка синтаксиса docker-compose.https.yml..."
docker compose -f docker-compose.https.yml config >/dev/null && echo "✅ Синтаксис docker-compose.https.yml корректен" || echo "❌ Ошибка в синтаксисе"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Подготовка завершена!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Созданные файлы:"
ls -la $N8N_DIR/*.yml $N8N_DIR/Caddyfile $N8N_DIR/.env 2>/dev/null | awk '{print "  " \$9}'
echo ""
echo "Следующие шаги:"
echo "1. Настройте DNS: добавьте A-запись для $SUBDOMAIN -> $SERVER_IP"
echo "2. Дождитесь распространения DNS (обычно 5-30 минут)"
echo "3. После настройки DNS запустите: ./enable-https.sh"
echo ""
EOF

echo ""
echo "✅ Подготовка завершена на сервере!"
echo ""
echo "📋 Следующие шаги:"
echo "1. Настройте DNS: добавьте A-запись для $SUBDOMAIN -> $SERVER_IP"
echo "2. Дождитесь распространения DNS (обычно 5-30 минут)"
echo "3. После настройки DNS запустите: ./enable-https.sh"

#!/bin/bash

# Скрипт для генерации команд ручного развертывания n8n
# Использование: ./manual-deploy.sh
# Команды можно скопировать и выполнить на сервере вручную

# IP адрес или домен сервера (можно указать через переменную окружения)
SERVER_IP="${SERVER_IP:-YOUR_SERVER_IP}"
SSH_HOST="${SSH_HOST:-n8n-selectel}"
N8N_DIR="/opt/n8n"

# Проверка наличия IP
if [ "$SERVER_IP" = "YOUR_SERVER_IP" ]; then
    echo "⚠️  ВНИМАНИЕ: IP адрес не указан"
    echo ""
    echo "Укажите IP адрес через переменную окружения:"
    echo "   SERVER_IP=your-server-ip ./manual-deploy.sh"
    echo ""
    echo "Или отредактируйте скрипт и замените YOUR_SERVER_IP на ваш IP/домен"
    echo ""
    read -p "Продолжить с YOUR_SERVER_IP? (y/n): " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "🔑 Генерация ключа шифрования и пароля..."
ENCRYPTION_KEY=$(openssl rand -hex 32)
AUTH_PASSWORD=$(openssl rand -base64 24)

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ИНСТРУКЦИЯ ПО РУЧНОМУ РАЗВЕРТЫВАНИЮ N8N"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "⚠️  ВАЖНО: Сохраните эти значения перед началом!"
echo ""
echo "N8N_ENCRYPTION_KEY: $ENCRYPTION_KEY"
echo "N8N_BASIC_AUTH_PASSWORD: $AUTH_PASSWORD"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

read -p "Нажмите Enter после сохранения значений..."

echo ""
echo "📋 Скопируйте и выполните следующие команды на сервере:"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Подключитесь к серверу:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ssh $SSH_HOST"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. Обновите систему и установите базовые утилиты:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "apt update && apt -y upgrade"
echo "apt -y install ca-certificates curl ufw nano"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. Настройте firewall:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ufw allow OpenSSH"
echo "ufw allow 5678/tcp"
echo "ufw --force enable"
echo "ufw status"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. Установите Docker:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "curl -fsSL https://get.docker.com | sh"
echo "docker --version"
echo "docker compose version"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. Создайте директорию и перейдите в неё:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "mkdir -p $N8N_DIR && cd $N8N_DIR"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. Создайте файл .env:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "cat > .env << 'ENVEOF'"
echo "N8N_ENCRYPTION_KEY=$ENCRYPTION_KEY"
echo "N8N_BASIC_AUTH_PASSWORD=$AUTH_PASSWORD"
echo "ENVEOF"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7. Создайте файл docker-compose.yml:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "cat > docker-compose.yml << 'COMPOSEEOF'"
cat << COMPOSEEOF
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - TZ=\${TZ:-Europe/Moscow}
      - N8N_PORT=5678
      - N8N_PROTOCOL=\${N8N_PROTOCOL:-http}
      - N8N_HOST=\${N8N_HOST}
      - WEBHOOK_URL=\${WEBHOOK_URL}
      - N8N_SECURE_COOKIE=\${N8N_SECURE_COOKIE:-false}
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=\${N8N_BASIC_AUTH_USER:-admin}
      - N8N_BASIC_AUTH_PASSWORD=\${N8N_BASIC_AUTH_PASSWORD}
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=none
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      - EXECUTIONS_DATA_SAVE_ON_PROGRESS=false
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=168
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  n8n_data:
COMPOSEEOF
echo "COMPOSEEOF"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "8. Запустите n8n:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "docker compose up -d"
echo "docker ps"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "9. Проверьте логи (опционально):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "docker logs -f --tail=200 n8n"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ После выполнения всех команд откройте в браузере:"
echo "   http://$SERVER_IP:5678"
echo ""
echo "👤 Логин: admin"
echo "🔑 Пароль: $AUTH_PASSWORD"
echo "═══════════════════════════════════════════════════════════════"
echo ""

#!/bin/bash

# Скрипт развертывания n8n на Ubuntu 22.04
# Использование: ./deploy.sh

set -e

# SSH хост (может быть алиас из ~/.ssh/config или user@host)
SSH_HOST="${SSH_HOST:-n8n-selectel}"
# IP адрес или домен сервера (можно указать через переменную окружения)
SERVER_IP="${SERVER_IP:-YOUR_SERVER_IP}"
N8N_DIR="/opt/n8n"

# Проверка наличия IP
if [ "$SERVER_IP" = "YOUR_SERVER_IP" ]; then
    echo "❌ Ошибка: не указан IP адрес или домен сервера"
    echo ""
    echo "Укажите IP адрес или домен через переменную окружения:"
    echo "   SERVER_IP=your-server-ip ./deploy.sh"
    echo ""
    echo "Или отредактируйте скрипт и замените YOUR_SERVER_IP на ваш IP/домен"
    exit 1
fi

echo "🚀 Начинаем развертывание n8n на $SERVER_IP"
echo "📡 SSH хост: $SSH_HOST"
echo ""

# Проверка подключения
echo "📡 Проверка подключения к серверу..."

# Проверяем подключение с BatchMode (без интерактивного ввода)
if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes "$SSH_HOST" "echo 'Connected'" 2>/dev/null; then
    echo ""
    echo "⚠️  Не удалось подключиться без пароля (SSH ключ не настроен или не используется)."
    echo ""
    echo "Скрипт будет запрашивать пароль при каждом подключении."
    echo ""
    echo "Чтобы настроить SSH ключ и избежать ввода пароля:"
    echo "   ./copy-ssh-key.sh"
    echo ""
    echo "Или используйте скрипт для ручного развертывания:"
    echo "   ./manual-deploy.sh"
    echo ""
    read -p "Продолжить с вводом пароля? (Enter для продолжения, Ctrl+C для отмены): "
    echo ""
fi

echo "✅ Готов к подключению"

# Генерация ключей
echo "🔑 Генерация ключа шифрования и пароля..."
ENCRYPTION_KEY=$(openssl rand -hex 32)
AUTH_PASSWORD=$(openssl rand -base64 24)

echo ""
echo "⚠️  ВАЖНО: Сохраните эти значения!"
echo "N8N_ENCRYPTION_KEY: $ENCRYPTION_KEY"
echo "N8N_BASIC_AUTH_PASSWORD: $AUTH_PASSWORD"
echo ""
read -p "Нажмите Enter после сохранения значений..."

# Выполнение команд на сервере
echo "📦 Обновление системы и установка базовых утилит..."
ssh -o StrictHostKeyChecking=no "$SSH_HOST" << EOF
set -e

# Обновление системы
# Настройка debconf для автоматических ответов
export DEBIAN_FRONTEND=noninteractive
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

apt update && apt -y upgrade
apt -y install ca-certificates curl ufw nano

# Для sshd_config выбираем сохранить текущую версию
echo 'openssh-server openssh-server/sshd_config_keep_local_version boolean true' | debconf-set-selections

# Настройка firewall
echo "🔥 Настройка firewall..."
ufw allow OpenSSH
ufw allow 5678/tcp
ufw --force enable
ufw status

# Установка Docker
echo "🐳 Установка Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
fi
docker --version
docker compose version

# Создание директории
echo "📁 Создание директории для n8n..."
mkdir -p $N8N_DIR
cd $N8N_DIR

# Создание .env файла
echo "📝 Создание .env файла..."
cat > .env << ENVEOF
TZ=Europe/Moscow
N8N_PROTOCOL=http
N8N_HOST=$SERVER_IP
WEBHOOK_URL=http://$SERVER_IP:5678/
N8N_SECURE_COOKIE=false
N8N_ENCRYPTION_KEY=$ENCRYPTION_KEY
N8N_BASIC_AUTH_PASSWORD=$AUTH_PASSWORD
N8N_BASIC_AUTH_USER=admin
ENVEOF

# Копирование docker-compose.yml
echo "📋 Копирование docker-compose.yml..."
cat > docker-compose.yml << COMPOSEEOF
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

# Запуск n8n
echo "🚀 Запуск n8n..."
docker compose up -d

# Проверка статуса
echo "✅ Проверка статуса контейнера..."
sleep 5
docker ps | grep n8n || echo "⚠️  Контейнер не найден в списке"

echo ""
echo "✅ Развертывание завершено!"
echo "🌐 Откройте в браузере: http://$SERVER_IP:5678"
echo "👤 Логин: admin"
echo "🔑 Пароль: $AUTH_PASSWORD"
EOF

echo ""
echo "✅ Развертывание завершено!"
echo "🌐 Откройте в браузере: http://$SERVER_IP:5678"
echo "👤 Логин: admin"
echo "🔑 Пароль: $AUTH_PASSWORD"
echo ""
echo "📊 Для просмотра логов выполните:"
echo "   ssh $SSH_HOST 'docker logs -f --tail=200 n8n'"

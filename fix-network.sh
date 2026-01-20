#!/usr/bin/env bash
# Скрипт для исправления проблем с сетью и конфигурацией n8n
# Использование: ./fix-network.sh

set -euo pipefail

COMPOSE_DIR="/opt/n8n"
cd "$COMPOSE_DIR"

echo "🔍 Диагностика текущего состояния..."
echo ""

# Проверка файлов
echo "📁 Файлы compose:"
ls -la docker-compose*.yml 2>/dev/null || echo "  Нет compose файлов"
echo ""

# Проверка .env
echo "📝 Проверка .env файла:"
if [ -f .env ]; then
    echo "  ✅ .env существует"
    echo "  Содержимое:"
    cat .env | sed 's/^/    /'
else
    echo "  ❌ .env не найден"
fi
echo ""

# Проверка контейнеров
echo "🐳 Статус контейнеров:"
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}" | grep -E "NAMES|n8n|caddy" || echo "  Контейнеры не найдены"
echo ""

# Проверка сетей
echo "🌐 Docker сети:"
docker network ls | grep -E "NETWORK|n8n" || echo "  Сети n8n не найдены"
echo ""

# Проверка, в какой сети находятся контейнеры
if docker ps --format '{{.Names}}' | grep -q "n8n"; then
    echo "📡 Сеть контейнера n8n:"
    docker inspect n8n --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}' 2>/dev/null || echo "  Не удалось определить"
fi

if docker ps --format '{{.Names}}' | grep -q "caddy"; then
    echo "📡 Сеть контейнера caddy:"
    docker inspect caddy --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}' 2>/dev/null || echo "  Не удалось определить"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 Рекомендации:"
echo ""

# Проверяем наличие Caddy
if docker ps --format '{{.Names}}' | grep -qx 'caddy'; then
    echo "✅ Контейнер Caddy запущен"
    echo ""
    
    if [ -f "docker-compose.https.yml" ]; then
        echo "📋 Найден docker-compose.https.yml"
        echo "   Выполните переключение на HTTPS:"
        echo "   mv docker-compose.yml docker-compose.ip.yml"
        echo "   mv docker-compose.https.yml docker-compose.yml"
        echo "   docker compose down"
        echo "   docker compose up -d"
    elif grep -q "^[[:space:]]*caddy:" docker-compose.yml 2>/dev/null; then
        echo "✅ Caddy уже в docker-compose.yml"
        echo "   Проверьте, что сеть n8n_network определена в compose файле"
    else
        echo "⚠️  Caddy запущен, но не в docker-compose.yml"
        echo "   Нужно создать docker-compose.https.yml через setup-https.sh"
    fi
else
    echo "ℹ️  Контейнер Caddy не запущен (HTTP режим)"
fi

echo ""
echo "📝 Для создания/обновления .env файла используйте:"
echo "   nano .env"
echo ""
echo "   Минимальные переменные для HTTPS:"
echo "   N8N_ENCRYPTION_KEY=<ваш_ключ>"
echo "   N8N_BASIC_AUTH_PASSWORD=<ваш_пароль>"
echo "   N8N_HOST=n8n.n8n-my-project.ru"
echo "   WEBHOOK_URL=https://n8n.n8n-my-project.ru/"

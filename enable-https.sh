#!/bin/bash

# Скрипт включения HTTPS для n8n (после настройки DNS)
# Использование: ./enable-https.sh

set -e

SSH_HOST="${SSH_HOST:-n8n-selectel}"
N8N_DIR="/opt/n8n"
# Поддомен для n8n (можно указать через переменную окружения)
SUBDOMAIN="${SUBDOMAIN:-YOUR_SUBDOMAIN}"

# Проверка наличия домена
if [ "$SUBDOMAIN" = "YOUR_SUBDOMAIN" ]; then
    echo "❌ Ошибка: не указан поддомен"
    echo ""
    echo "Укажите поддомен через переменную окружения:"
    echo "   SUBDOMAIN=n8n.yourdomain.com ./enable-https.sh"
    echo ""
    echo "Или отредактируйте скрипт и замените YOUR_SUBDOMAIN"
    exit 1
fi

echo "🔐 Включение HTTPS для n8n"
echo "📡 SSH хост: $SSH_HOST"
echo "🌐 Домен: $SUBDOMAIN"
echo ""

# Проверка подключения
echo "📡 Проверка подключения к серверу..."
if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes "$SSH_HOST" "echo 'Connected'" 2>/dev/null; then
    echo "⚠️  Не удалось подключиться по SSH ключу (BatchMode)."
    echo "   Попробую подключиться с возможностью ввода пароля..."
    echo ""
    if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_HOST" "echo 'Connected'" 2>/dev/null; then
        echo "❌ Не удалось подключиться к серверу."
        exit 1
    fi
fi

echo "✅ Подключение установлено"
echo ""

# Проверка DNS
echo "🔍 Проверка DNS..."
DNS_IP=$(dig +short $SUBDOMAIN @8.8.8.8 | tail -1)
if [ -z "$DNS_IP" ]; then
    echo "⚠️  DNS запись для $SUBDOMAIN не найдена или еще не распространилась"
    echo "   Продолжить все равно? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Отменено."
        exit 1
    fi
else
    echo "✅ DNS запись найдена: $SUBDOMAIN -> $DNS_IP"
fi
echo ""

# Выполнение команд на сервере
echo "🔧 Выполнение команд на сервере..."
echo "   (Если будет запрошен пароль, введите его)"
echo ""
ssh -o StrictHostKeyChecking=no "$SSH_HOST" << EOF
set -e

cd $N8N_DIR

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "C1) Переключение на HTTPS конфигурацию и перезапуск"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ ! -f docker-compose.https.yml ]; then
    echo "❌ Файл docker-compose.https.yml не найден!"
    echo "   Сначала выполните: ./setup-https.sh"
    exit 1
fi

# Переименовываем файлы согласно части C
if [ -f docker-compose.yml ]; then
    mv docker-compose.yml docker-compose.ip.yml
    echo "✅ docker-compose.yml переименован в docker-compose.ip.yml"
fi

mv docker-compose.https.yml docker-compose.yml
echo "✅ docker-compose.https.yml переименован в docker-compose.yml"
echo ""

echo "Остановка текущих контейнеров..."
docker compose down
echo ""

echo "Запуск контейнеров с HTTPS конфигурацией..."
docker compose up -d
echo ""

echo "Ожидание запуска контейнеров (5 секунд)..."
sleep 5

echo ""
echo "Проверка статуса контейнеров:"
docker ps
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "C2) Проверка логов Caddy (выпуск сертификата)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Ожидание получения сертификата (до 30 секунд)..."
echo ""

# Ждем получения сертификата (максимум 30 секунд)
CERT_OBTAINED=false
for i in {1..30}; do
    sleep 1
    if docker logs caddy 2>&1 | grep -qi "certificate obtained successfully\|certificate obtained"; then
        CERT_OBTAINED=true
        break
    fi
    # Проверяем на критические ошибки
    if docker logs caddy 2>&1 | grep -qiE "\"level\":\"error\"|\"level\":\"fatal\""; then
        echo "❌ Обнаружена критическая ошибка в логах Caddy"
        docker logs --tail=50 caddy 2>&1 | grep -iE "error|fatal" | tail -10
        echo ""
        echo "Проверьте логи полностью: docker logs caddy"
        exit 1
    fi
done

echo ""
echo "Просмотр последних 50 строк логов Caddy:"
echo ""
docker logs --tail=50 caddy 2>&1 | tail -30
echo ""

# Проверка на критические ошибки (не просто "acme" или "error" в info сообщениях)
if docker logs caddy 2>&1 | grep -qiE "\"level\":\"error\"|\"level\":\"fatal\""; then
    echo "⚠️  Обнаружены критические ошибки в логах Caddy"
    echo "   Проверьте логи выше. Возможные причины:"
    echo "   - DNS еще не распространился"
    echo "   - Порты 80/443 недоступны извне"
    echo "   - Проблемы с ACME (Let's Encrypt)"
    echo ""
    echo "Продолжить с закрытием порта 5678? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Отменено. Проверьте логи и DNS, затем запустите скрипт снова."
        exit 1
    fi
elif [ "$CERT_OBTAINED" = true ]; then
    echo "✅ Сертификат успешно получен!"
elif docker logs caddy 2>&1 | grep -qi "trying to solve challenge\|served key authentication"; then
    echo "✅ Caddy работает, процесс получения сертификата идет"
    echo "   (Сертификат может быть получен в фоновом режиме)"
else
    echo "⚠️  Не удалось определить статус получения сертификата"
    echo "   Проверьте логи: docker logs caddy"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "C3) Закрытие порта 5678 в firewall"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  ВНИМАНИЕ: После закрытия порта 5678 доступ по IP будет недоступен!"
echo "   Убедитесь, что HTTPS работает: https://$SUBDOMAIN"
echo ""
echo "Закрыть порт 5678? (y/n)"
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Порт 5678 оставлен открытым. Закройте его вручную командой:"
    echo "   ufw delete allow 5678/tcp"
    exit 0
fi

ufw delete allow 5678/tcp
echo "✅ Порт 5678 закрыт в firewall"
echo ""

echo "Текущий статус firewall:"
ufw status
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ HTTPS включен и порт 5678 закрыт!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🌐 n8n теперь доступен ТОЛЬКО по адресу:"
echo "   https://$SUBDOMAIN"
echo ""
echo "⚠️  Доступ по IP больше НЕ работает!"
echo ""
echo "📊 Полезные команды для управления:"
echo "   Просмотр логов Caddy:  docker logs -f caddy"
echo "   Просмотр логов n8n:    docker logs -f n8n"
echo "   Перезапуск:            cd $N8N_DIR && docker compose restart"
echo "   Остановка:             cd $N8N_DIR && docker compose down"
echo ""
EOF

echo ""
echo "✅ HTTPS включен!"
echo ""
echo "🌐 n8n теперь доступен по адресу:"
echo "   https://$SUBDOMAIN"
echo ""
echo "📊 Для проверки логов Caddy:"
echo "   ssh $SSH_HOST 'docker logs -f caddy'"
echo ""

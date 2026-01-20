#!/usr/bin/env bash
# Скрипт для очистки временных файлов и бэкапов
# Использование: ./cleanup.sh [--server]

set -euo pipefail

CLEANUP_SERVER=false

if [ "${1:-}" = "--server" ]; then
    CLEANUP_SERVER=true
fi

echo "🧹 Очистка временных файлов..."
echo ""

if [ "$CLEANUP_SERVER" = true ]; then
    echo "📡 Очистка на сервере..."
    SSH_HOST="${SSH_HOST:-n8n-selectel}"
    N8N_DIR="/opt/n8n"
    
    ssh "$SSH_HOST" << 'EOF'
cd /opt/n8n

echo "Удаление старых бэкапов .env (старше 7 дней)..."
find . -name ".env.bak.*" -type f -mtime +7 -delete 2>/dev/null && echo "✅ Старые бэкапы .env удалены" || echo "Нет старых бэкапов .env"

echo "Удаление старых бэкапов docker-compose (старше 7 дней)..."
find . -name "docker-compose*.bak*" -type f -mtime +7 -delete 2>/dev/null && echo "✅ Старые бэкапы compose удалены" || echo "Нет старых бэкапов compose"

echo ""
echo "Текущие бэкапы (последние 7 дней):"
ls -lh .env.bak* docker-compose*.bak* 2>/dev/null | tail -10 || echo "Нет недавних бэкапов"

echo ""
echo "✅ Очистка завершена"
EOF
else
    echo "📁 Очистка локальной директории..."
    
    # Удаляем временные файлы
    echo "Поиск временных файлов..."
    find . -name "*.bak" -o -name "*.tmp" -o -name "*.swp" -o -name "*~" 2>/dev/null | while read -r file; do
        echo "  Удаление: $file"
        rm -f "$file"
    done
    
    echo ""
    echo "✅ Локальная очистка завершена"
fi

echo ""
echo "📋 Рекомендации:"
echo "  - Бэкапы .env можно удалить вручную, если они больше не нужны"
echo "  - Скрипты fix-* и restore-* можно оставить для документации"
echo "  - Или переместить в папку archive/ если хотите их сохранить"

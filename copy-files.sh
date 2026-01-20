#!/bin/bash

# Скрипт для копирования файлов проекта на сервер
# Использование: ./copy-files.sh

set -e

# SSH хост (может быть алиас из ~/.ssh/config или user@host)
SSH_HOST="${SSH_HOST:-n8n-selectel}"
N8N_DIR="/opt/n8n"

echo "📋 Копирование файлов на сервер"
echo "📡 SSH хост: $SSH_HOST"
echo "📁 Директория на сервере: $N8N_DIR"
echo ""

# Проверка подключения
echo "📡 Проверка подключения к серверу..."
if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes "$SSH_HOST" "echo 'Connected'" 2>/dev/null; then
    echo "⚠️  SSH ключ не настроен, будет использоваться парольная аутентификация."
    echo "   При копировании файлов будет запрошен пароль."
    echo ""
    echo "💡 Чтобы избежать ввода пароля, настройте SSH ключ:"
    echo "   ./copy-ssh-key.sh"
    echo ""
    read -p "Продолжить с вводом пароля? (Enter для продолжения, Ctrl+C для отмены): "
    echo ""
fi

echo "✅ Готов к подключению"
echo ""

# Создание директории на сервере (если не существует)
echo "📁 Создание директории на сервере..."
echo "   (Если будет запрошен пароль, введите его)"
ssh -o StrictHostKeyChecking=no "$SSH_HOST" "mkdir -p $N8N_DIR"
echo ""

# Копирование файлов
echo "📋 Копирование файлов..."
echo "   (Если будет запрошен пароль, введите его)"
echo ""

# backup.sh
if [ -f "backup.sh" ]; then
    echo "  → backup.sh"
    scp -o StrictHostKeyChecking=no backup.sh "${SSH_HOST}:${N8N_DIR}/backup.sh"
    ssh -o StrictHostKeyChecking=no "$SSH_HOST" "chmod +x ${N8N_DIR}/backup.sh"
    echo "     ✅ Скопирован"
else
    echo "  ⚠️  backup.sh не найден в текущей директории"
fi

# update.sh
if [ -f "update.sh" ]; then
    echo "  → update.sh"
    scp -o StrictHostKeyChecking=no update.sh "${SSH_HOST}:${N8N_DIR}/update.sh"
    ssh -o StrictHostKeyChecking=no "$SSH_HOST" "chmod +x ${N8N_DIR}/update.sh"
    echo "     ✅ Скопирован"
else
    echo "  ⚠️  update.sh не найден в текущей директории"
fi

# docker-compose.yml (обновление версии)
if [ -f "docker-compose.yml" ]; then
    echo "  → docker-compose.yml"
    scp -o StrictHostKeyChecking=no docker-compose.yml "${SSH_HOST}:${N8N_DIR}/docker-compose.yml"
    echo "     ✅ Скопирован"
else
    echo "  ⚠️  docker-compose.yml не найден в текущей директории"
fi

# fix-config.sh
if [ -f "fix-config.sh" ]; then
    echo "  → fix-config.sh"
    scp -o StrictHostKeyChecking=no fix-config.sh "${SSH_HOST}:${N8N_DIR}/fix-config.sh"
    ssh -o StrictHostKeyChecking=no "$SSH_HOST" "chmod +x ${N8N_DIR}/fix-config.sh"
    echo "     ✅ Скопирован"
else
    echo "  ⚠️  fix-config.sh не найден в текущей директории"
fi

# fix-network.sh (диагностика)
if [ -f "fix-network.sh" ]; then
    echo "  → fix-network.sh"
    scp -o StrictHostKeyChecking=no fix-network.sh "${SSH_HOST}:${N8N_DIR}/fix-network.sh"
    ssh -o StrictHostKeyChecking=no "$SSH_HOST" "chmod +x ${N8N_DIR}/fix-network.sh"
    echo "     ✅ Скопирован"
else
    echo "  ⚠️  fix-network.sh не найден в текущей директории"
fi

# cleanup.sh (очистка временных файлов)
if [ -f "cleanup.sh" ]; then
    echo "  → cleanup.sh"
    scp -o StrictHostKeyChecking=no cleanup.sh "${SSH_HOST}:${N8N_DIR}/cleanup.sh"
    ssh -o StrictHostKeyChecking=no "$SSH_HOST" "chmod +x ${N8N_DIR}/cleanup.sh"
    echo "     ✅ Скопирован"
else
    echo "  ⚠️  cleanup.sh не найден в текущей директории"
fi

echo ""
echo "✅ Файлы скопированы!"
echo ""
echo "📊 Проверка на сервере:"
ssh -o StrictHostKeyChecking=no "$SSH_HOST" "ls -lh ${N8N_DIR}/backup.sh ${N8N_DIR}/update.sh ${N8N_DIR}/docker-compose.yml ${N8N_DIR}/fix-config.sh ${N8N_DIR}/fix-network.sh ${N8N_DIR}/cleanup.sh 2>/dev/null | grep -v 'cannot access' || echo 'Некоторые файлы не найдены'"
echo ""
echo "🚀 Готово! Теперь можно использовать:"
echo "   # Для диагностики проблем:"
echo "   ssh $SSH_HOST 'cd $N8N_DIR && ./fix-network.sh'"
echo ""
echo "   # Для автоматического исправления:"
echo "   ssh $SSH_HOST 'cd $N8N_DIR && sudo ./fix-config.sh'"
echo ""
echo "   # Для обновления n8n:"
echo "   ssh $SSH_HOST 'cd $N8N_DIR && sudo ./update.sh'"

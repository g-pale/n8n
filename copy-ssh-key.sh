#!/bin/bash

# Скрипт для копирования SSH ключа на сервер с использованием пароля
# Использование: ./copy-ssh-key.sh

# SSH хост (может быть алиас из ~/.ssh/config или user@host)
SSH_HOST="${SSH_HOST:-n8n-selectel}"
# IP адрес сервера (опционально, используется только в сообщениях)
SERVER_IP="${SERVER_IP:-}"

echo "🔑 Настройка SSH ключа на сервере"
echo "📡 SSH хост: $SSH_HOST"
echo ""

# Пытаемся найти ключ из SSH конфига
SSH_CONFIG_KEY=$(ssh -G "$SSH_HOST" 2>/dev/null | grep "^identityfile" | head -1 | awk '{print $2}' | sed "s|~|$HOME|g")

KEY_FILE=""
KEY_NAME=""

# Сначала проверяем ключ из SSH конфига
if [ -n "$SSH_CONFIG_KEY" ]; then
    # Проверяем публичный ключ
    if [ -f "${SSH_CONFIG_KEY}.pub" ]; then
        KEY_FILE="${SSH_CONFIG_KEY}.pub"
        KEY_NAME=$(basename "$SSH_CONFIG_KEY")
        echo "✅ Найден ключ из SSH конфига: $KEY_FILE"
    elif [ -f "$SSH_CONFIG_KEY" ]; then
        # Если указан приватный ключ, ищем .pub рядом
        KEY_FILE="${SSH_CONFIG_KEY}.pub"
        if [ -f "$KEY_FILE" ]; then
            KEY_NAME=$(basename "$SSH_CONFIG_KEY")
            echo "✅ Найден ключ из SSH конфига: $KEY_FILE"
        fi
    fi
fi

# Если ключ из конфига не найден, ищем стандартные ключи
if [ -z "$KEY_FILE" ]; then
    if [ -f ~/.ssh/id_ed25519.pub ]; then
        KEY_FILE=~/.ssh/id_ed25519.pub
        KEY_NAME="id_ed25519"
    elif [ -f ~/.ssh/id_rsa.pub ]; then
        KEY_FILE=~/.ssh/id_rsa.pub
        KEY_NAME="id_rsa"
    elif [ -f ~/.ssh/id_ecdsa.pub ]; then
        KEY_FILE=~/.ssh/id_ecdsa.pub
        KEY_NAME="id_ecdsa"
    fi
fi

# Если ключ все еще не найден, создаем новый
if [ -z "$KEY_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "📝 SSH ключ не найден. Создаю новый ключ..."
    read -p "Введите email для ключа (или нажмите Enter для пропуска): " EMAIL
    if [ -z "$EMAIL" ]; then
        EMAIL="root@$SSH_HOST"
    fi
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "$EMAIL" -N ""
    KEY_FILE=~/.ssh/id_ed25519.pub
    KEY_NAME="id_ed25519"
    echo "✅ SSH ключ создан"
    echo ""
fi

if [ -n "$KEY_FILE" ]; then
    echo "📋 Используется ключ: $KEY_FILE"
fi

echo ""
echo "Публичный ключ:"
cat "$KEY_FILE"
echo ""

# Проверяем, установлен ли sshpass
if ! command -v sshpass &> /dev/null; then
    echo "⚠️  Утилита sshpass не установлена."
    echo ""
    echo "Для macOS установите через Homebrew:"
    echo "   brew install hudochenkov/sshpass/sshpass"
    echo ""
    echo "Или используйте ручной способ (см. ниже)"
    echo ""
    read -p "Нажмите Enter для продолжения с ручным способом..."
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  РУЧНОЙ СПОСОБ НАСТРОЙКИ SSH КЛЮЧА"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Подключитесь к серверу (если знаете пароль):"
    echo "   ssh $SSH_HOST"
    echo ""
    echo "2. На сервере выполните:"
    echo "   mkdir -p ~/.ssh"
    echo "   chmod 700 ~/.ssh"
    echo "   nano ~/.ssh/authorized_keys"
    echo ""
    echo "3. Вставьте следующий публичный ключ:"
    echo ""
    cat "$KEY_FILE"
    echo ""
    echo "4. Сохраните файл (Ctrl+O, Enter, Ctrl+X)"
    echo ""
    echo "5. Установите правильные права:"
    echo "   chmod 600 ~/.ssh/authorized_keys"
    echo ""
    echo "6. Проверьте подключение:"
    echo "   exit"
    echo "   ssh $SSH_HOST"
    echo ""
    exit 0
fi

# Используем sshpass для копирования ключа
echo "🔐 Копирование ключа на сервер..."
echo "   Вам будет предложено ввести пароль root пользователя"
echo "   (если пароль не установлен, используйте панель управления хостингом)"
echo ""

read -sp "Введите пароль для $SSH_HOST: " PASSWORD
echo ""

if [ -z "$PASSWORD" ]; then
    echo "❌ Пароль не введен. Используйте ручной способ (см. выше)."
    exit 1
fi

# Копируем ключ с использованием пароля
if sshpass -p "$PASSWORD" ssh-copy-id -i "$KEY_FILE" -o StrictHostKeyChecking=no "$SSH_HOST" 2>/dev/null; then
    echo ""
    echo "✅ SSH ключ успешно скопирован на сервер!"
    echo ""
    echo "🧪 Проверяю подключение без пароля..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SSH_HOST" "echo 'SSH ключ работает!'" 2>/dev/null; then
        echo "✅ Подключение без пароля работает!"
        echo ""
        echo "Теперь вы можете использовать:"
        echo "   ./deploy.sh - для автоматического развертывания"
        echo "   ./set-password.sh - для установки пароля (опционально)"
    else
        echo "⚠️  Подключение без пароля не работает. Проверьте настройки на сервере."
    fi
else
    echo ""
    echo "❌ Не удалось скопировать ключ. Возможные причины:"
    echo "1. Неправильный пароль"
    echo "2. Пароль не установлен на сервере"
    echo "3. SSH сервер не разрешает парольную аутентификацию"
    echo ""
    echo "Используйте ручной способ (см. выше) или настройте через панель управления хостингом."
fi

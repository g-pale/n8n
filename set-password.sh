#!/bin/bash

# Скрипт для установки пароля root на сервере
# Использование: ./set-password.sh
# Требует: SSH ключ должен быть настроен (используйте ./copy-ssh-key.sh)

# SSH хост (может быть алиас из ~/.ssh/config или user@host)
SSH_HOST="${SSH_HOST:-n8n-selectel}"

echo "🔐 Установка пароля для root пользователя на сервере"
echo "📡 SSH хост: $SSH_HOST"
echo ""

# Проверка подключения по SSH ключу
echo "📡 Проверка подключения по SSH ключу..."
if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes "$SSH_HOST" "echo 'Connected'" 2>/dev/null; then
    echo "❌ Не удалось подключиться по SSH ключу."
    echo ""
    echo "Сначала настройте SSH ключ:"
    echo "   ./copy-ssh-key.sh"
    echo ""
    echo "Или убедитесь, что:"
    echo "1. SSH ключ настроен и работает"
    echo "2. Вы можете подключиться командой: ssh $SSH_HOST"
    echo ""
    echo "Если используете другой SSH алиас, укажите его:"
    echo "   SSH_HOST=ваш-алиас ./set-password.sh"
    echo ""
    exit 1
fi

echo "✅ Подключение установлено"
echo ""

# Запрос нового пароля
echo "Введите новый пароль для root пользователя:"
read -s PASSWORD1
echo ""
echo "Повторите пароль:"
read -s PASSWORD2
echo ""

if [ "$PASSWORD1" != "$PASSWORD2" ]; then
    echo "❌ Пароли не совпадают!"
    exit 1
fi

if [ -z "$PASSWORD1" ]; then
    echo "❌ Пароль не может быть пустым!"
    exit 1
fi

echo "🔑 Устанавливаю пароль на сервере..."
if ssh -o StrictHostKeyChecking=no "$SSH_HOST" "echo 'root:$PASSWORD1' | chpasswd" 2>/dev/null; then
    echo "✅ Пароль успешно установлен!"
    echo ""
    echo "Теперь вы можете использовать пароль для доступа к серверу."
    echo "Для автоматического развертывания используйте: ./deploy.sh"
else
    echo "❌ Не удалось установить пароль."
    echo ""
    echo "Попробуйте установить пароль вручную:"
    echo "   ssh $SSH_HOST 'passwd'"
    exit 1
fi

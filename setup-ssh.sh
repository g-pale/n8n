#!/bin/bash

# Скрипт для настройки SSH ключа на сервере
# Использование: ./setup-ssh.sh

# IP адрес или домен сервера (можно указать через переменную окружения)
SERVER_IP="${SERVER_IP:-YOUR_SERVER_IP}"
SERVER_USER="${SERVER_USER:-root}"

# Проверка наличия IP
if [ "$SERVER_IP" = "YOUR_SERVER_IP" ]; then
    echo "❌ Ошибка: не указан IP адрес или домен сервера"
    echo ""
    echo "Укажите IP адрес через переменную окружения:"
    echo "   SERVER_IP=your-server-ip ./setup-ssh.sh"
    echo ""
    echo "Или отредактируйте скрипт и замените YOUR_SERVER_IP"
    exit 1
fi

echo "🔐 Настройка SSH ключа для сервера $SERVER_IP"
echo ""

# Проверка наличия SSH ключа
if [ ! -f ~/.ssh/id_rsa.pub ] && [ ! -f ~/.ssh/id_ed25519.pub ]; then
    echo "📝 SSH ключ не найден. Создаю новый ключ..."
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
    echo "✅ SSH ключ создан"
    echo ""
fi

# Определяем какой ключ использовать
if [ -f ~/.ssh/id_ed25519.pub ]; then
    KEY_FILE=~/.ssh/id_ed25519.pub
elif [ -f ~/.ssh/id_rsa.pub ]; then
    KEY_FILE=~/.ssh/id_rsa.pub
fi

echo "📋 Публичный ключ:"
cat "$KEY_FILE"
echo ""

echo "🔑 Копирую ключ на сервер..."
echo "   Вам будет предложено ввести пароль root пользователя"
echo "   (если пароль еще не установлен, установите его командой: ssh root@$SERVER_IP 'passwd')"
echo ""

# Копируем ключ на сервер
if ssh-copy-id -i "$KEY_FILE" "$SERVER_USER@$SERVER_IP" 2>/dev/null; then
    echo ""
    echo "✅ SSH ключ успешно скопирован на сервер!"
    echo ""
    echo "🧪 Проверяю подключение без пароля..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$SERVER_USER@$SERVER_IP" "echo 'SSH ключ работает!'" 2>/dev/null; then
        echo "✅ Подключение без пароля работает!"
        echo ""
        echo "Теперь вы можете использовать ./deploy.sh для автоматического развертывания"
    else
        echo "⚠️  Подключение без пароля не работает. Возможно, нужно настроить сервер вручную."
    fi
else
    echo ""
    echo "❌ Не удалось скопировать ключ автоматически."
    echo ""
    echo "Альтернативный способ:"
    echo "1. Скопируйте публичный ключ вручную:"
    echo "   cat $KEY_FILE"
    echo ""
    echo "2. Подключитесь к серверу:"
    echo "   ssh $SERVER_USER@$SERVER_IP"
    echo ""
    echo "3. На сервере выполните:"
    echo "   mkdir -p ~/.ssh"
    echo "   chmod 700 ~/.ssh"
    echo "   echo '$(cat "$KEY_FILE")' >> ~/.ssh/authorized_keys"
    echo "   chmod 600 ~/.ssh/authorized_keys"
fi

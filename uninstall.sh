#!/bin/bash
# Останавливает и удаляет launchd-агенты Elgato Camera Control.
# Файлы проекта и config.json не трогает.

set -uo pipefail

AGENTS_DIR="$HOME/Library/LaunchAgents"
UID_NUM="$(id -u)"

for label in com.elgato.camera-control com.elgato.homekit-bridge; do
    plist="$AGENTS_DIR/$label.plist"
    if [[ -f "$plist" ]]; then
        launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null || launchctl unload -w "$plist" 2>/dev/null
        rm -f "$plist"
        echo "✅ $label остановлен и удалён"
    else
        echo "ℹ️  $label не установлен"
    fi
done

echo ""
echo "Готово. Логи остались в ~/Library/Logs/elgato-*.log (можно удалить вручную)."
echo "Если мост был добавлен в Home App — удалите 'Elgato Bridge' в настройках дома."

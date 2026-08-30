#!/bin/bash
# Установка Elgato Camera Control одной командой:
#   ./install.sh              — камера-контроль + HomeKit-мост
#   ./install.sh --no-homekit — только камера-контроль
#
# Что делает:
#   1. Ставит Python-зависимости
#   2. Собирает CoreMediaIO helper для надёжного определения камеры
#   3. Создаёт config.json и ищет Key Light в сети
#   4. Ставит launchd-агенты (автозапуск при входе, авторестарт)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$HOME/Library/Logs"
AGENTS_DIR="$HOME/Library/LaunchAgents"
CAMERA_LABEL="com.elgato.camera-control"
HOMEKIT_LABEL="com.elgato.homekit-bridge"
UID_NUM="$(id -u)"

WITH_HOMEKIT=1
[[ "${1:-}" == "--no-homekit" ]] && WITH_HOMEKIT=0

if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ Этот скрипт предназначен только для macOS"
    exit 1
fi

PYTHON="$(command -v python3 || true)"
if [[ -z "$PYTHON" ]]; then
    echo "❌ python3 не найден. Установите Xcode Command Line Tools: xcode-select --install"
    exit 1
fi
echo "🐍 Python: $PYTHON"

echo ""
echo "==> 1/4 Установка Python-зависимостей..."
if ! "$PYTHON" -m pip install --quiet --user -r "$SCRIPT_DIR/requirements.txt" 2>/dev/null; then
    # Homebrew Python (PEP 668) требует явного флага
    "$PYTHON" -m pip install --quiet --user --break-system-packages -r "$SCRIPT_DIR/requirements.txt" || {
        echo "❌ Не удалось установить зависимости (requests, zeroconf, HAP-python)"
        exit 1
    }
fi
echo "✅ Зависимости установлены"

echo ""
echo "==> 2/4 Сборка CoreMediaIO helper (надёжное определение камеры)..."
if xcode-select -p >/dev/null 2>&1 && command -v swiftc >/dev/null 2>&1; then
    mkdir -p "$SCRIPT_DIR/.build"
    if swiftc -O "$SCRIPT_DIR/Tools/camera-state.swift" -o "$SCRIPT_DIR/.build/camera-state" 2>&1; then
        echo "✅ Helper собран: .build/camera-state"
    else
        echo "⚠️  Сборка helper не удалась — будет использован lsof (менее надёжно)"
    fi
else
    echo "⚠️  swiftc не найден — будет использован lsof (менее надёжно)"
    echo "   Для надёжного режима: xcode-select --install, затем повторите ./install.sh"
fi

echo ""
echo "==> 3/4 Конфигурация..."
if [[ ! -f "$SCRIPT_DIR/config.json" ]]; then
    cat > "$SCRIPT_DIR/config.json" <<'JSON'
{
  "lights": [],
  "settings": {
    "check_interval": 2.0,
    "turn_on_delay": 0.5,
    "turn_off_delay": 2.0,
    "auto_discovery": true,
    "notifications": true
  },
  "profiles": {
    "default": {
      "brightness": 100,
      "temperature": 200
    }
  }
}
JSON
    echo "✅ Создан config.json"
fi

echo "🔍 Поиск Key Light в сети (10с)..."
"$PYTHON" "$SCRIPT_DIR/elgato_camera_control_advanced.py" --discover || true

HAS_LIGHTS="$("$PYTHON" -c "import json; print(1 if json.load(open('$SCRIPT_DIR/config.json')).get('lights') else 0)")"
if [[ "$HAS_LIGHTS" == "0" && -t 0 ]]; then
    echo ""
    echo "Если лампа не нашлась автоматически, можно указать её IP вручную"
    echo "(IP виден в приложении Elgato Control Center, в настройках устройства)."
    read -r -p "IP адрес Key Light (Enter — пропустить, найдётся позже автоматически): " LIGHT_IP
    if [[ -n "$LIGHT_IP" ]]; then
        "$PYTHON" - "$SCRIPT_DIR/config.json" "$LIGHT_IP" <<'PYEOF'
import json, sys
path, ip = sys.argv[1], sys.argv[2]
with open(path) as f:
    config = json.load(f)
config.setdefault("lights", []).append({
    "name": "Key Light",
    "ip": ip,
    "enabled": True,
    "brightness": 100,
    "temperature": 200,
})
with open(path, "w") as f:
    json.dump(config, f, indent=2)
print(f"✅ Добавлена лампа {ip}")
PYEOF
    fi
fi

echo ""
echo "==> 4/4 Установка launchd-агентов (автозапуск)..."
mkdir -p "$AGENTS_DIR" "$LOG_DIR"

install_agent() {
    local label="$1"
    local plist="$AGENTS_DIR/$label.plist"
    sed -e "s|__PYTHON__|$PYTHON|g" \
        -e "s|__SCRIPT_DIR__|$SCRIPT_DIR|g" \
        -e "s|__LOG_DIR__|$LOG_DIR|g" \
        "$SCRIPT_DIR/launchd/$label.plist.template" > "$plist"

    launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null
    if launchctl bootstrap "gui/$UID_NUM" "$plist" 2>/dev/null; then
        echo "✅ $label запущен"
    elif launchctl load -w "$plist" 2>/dev/null; then
        echo "✅ $label запущен (legacy load)"
    else
        echo "❌ Не удалось запустить $label — проверьте: launchctl print gui/$UID_NUM/$label"
    fi
}

install_agent "$CAMERA_LABEL"
if [[ "$WITH_HOMEKIT" == "1" ]]; then
    install_agent "$HOMEKIT_LABEL"
fi

echo ""
echo "🎉 Готово!"
echo ""
echo "Камера-контроль работает в фоне: камера включилась → свет включился,"
echo "камера выключилась → свет выключился. Автозапуск при входе в систему."
if [[ "$WITH_HOMEKIT" == "1" ]]; then
    echo ""
    echo "🏠 HomeKit: добавьте мост в Home App:"
    echo '   "+" → Добавить аксессуар → "Нет кода..." → Elgato Bridge → код 031-45-154'
fi
echo ""
echo "Логи:"
echo "   tail -f \"$LOG_DIR/elgato-camera-control.log\""
[[ "$WITH_HOMEKIT" == "1" ]] && echo "   tail -f \"$LOG_DIR/elgato-homekit-bridge.log\""
echo ""
echo "Удаление: ./uninstall.sh"

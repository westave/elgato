#!/bin/bash
# Установка Elgato Camera Control одной командой:
#   ./install.sh              — камера-контроль + HomeKit-мост
#   ./install.sh --no-homekit — только камера-контроль
#   ./install.sh --homekit-only — только мост, если уже работает .app
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
WITH_CAMERA=1
for arg in "$@"; do
    case "$arg" in
        --no-homekit) WITH_HOMEKIT=0 ;;
        --homekit-only) WITH_CAMERA=0 ;;
        -h|--help)
            echo "Использование: ./install.sh [--no-homekit | --homekit-only]"
            exit 0
            ;;
        *) echo "❌ Неизвестный параметр: $arg" >&2; exit 1 ;;
    esac
done
if [[ "$WITH_HOMEKIT" == "0" && "$WITH_CAMERA" == "0" ]]; then
    echo "❌ --no-homekit и --homekit-only нельзя использовать вместе" >&2
    exit 1
fi

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
if [[ ! -x "$SCRIPT_DIR/.venv/bin/python" ]]; then
    "$PYTHON" -m venv "$SCRIPT_DIR/.venv" || exit 1
fi
PYTHON="$SCRIPT_DIR/.venv/bin/python"
"$PYTHON" -m pip install --quiet -r "$SCRIPT_DIR/requirements.txt" || {
    echo "❌ Не удалось установить зависимости (requests, zeroconf, HAP-python)"
    exit 1
}
echo "✅ Зависимости установлены"

echo ""
echo "==> 2/4 Сборка CoreMediaIO helper (надёжное определение камеры)..."
if [[ "$WITH_CAMERA" == "0" ]]; then
    echo "ℹ️  Используется работающее приложение — helper не требуется"
elif xcode-select -p >/dev/null 2>&1 && command -v swiftc >/dev/null 2>&1; then
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
    "check_interval": 0.5,
    "turn_on_delay": 0.0,
    "turn_off_delay": 2.0,
    "auto_discovery": true,
    "notifications": true,
    "apply_profiles": false
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

HAS_LIGHTS="$("$PYTHON" -c 'import json, sys; print(1 if json.load(open(sys.argv[1])).get("lights") else 0)' "$SCRIPT_DIR/config.json")"
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
        "$SCRIPT_DIR/launchd/$label.plist.template" > "$plist" || return 1
    plutil -lint "$plist" || return 1

    launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null
    if launchctl bootstrap "gui/$UID_NUM" "$plist" 2>/dev/null; then
        echo "✅ $label запущен"
    elif launchctl load -w "$plist" 2>/dev/null; then
        echo "✅ $label запущен (legacy load)"
    else
        echo "❌ Не удалось запустить $label — проверьте: launchctl print gui/$UID_NUM/$label" >&2
        return 1
    fi
}

if [[ "$WITH_CAMERA" == "1" ]]; then
    install_agent "$CAMERA_LABEL" || exit 1
fi
if [[ "$WITH_HOMEKIT" == "1" ]]; then
    install_agent "$HOMEKIT_LABEL" || exit 1
fi

echo ""
echo "🎉 Готово!"
echo ""
if [[ "$WITH_CAMERA" == "1" ]]; then
    echo "Камера-контроль работает в фоне: камера включилась → свет включился,"
    echo "камера выключилась → свет выключился. Автозапуск при входе в систему."
else
    echo "Установлен только HomeKit-мост. Камерой и светом управляет приложение."
fi
if [[ "$WITH_HOMEKIT" == "1" ]]; then
    echo ""
    echo "🏠 HomeKit: добавьте мост в Home App:"
    echo '   "+" → Добавить аксессуар → "Нет кода..." → Elgato Bridge → код 031-45-154'
fi
echo ""
echo "Логи:"
[[ "$WITH_CAMERA" == "1" ]] && echo "   tail -f \"$LOG_DIR/elgato-camera-control.log\""
[[ "$WITH_HOMEKIT" == "1" ]] && echo "   tail -f \"$LOG_DIR/elgato-homekit-bridge.log\""
echo ""
echo "Удаление: ./uninstall.sh"

# 🚀 Быстрый старт - Advanced версия

## Что нового в Advanced версии?

✅ **Все функции реализованы:**
1. ⚙️ Настройка яркости и цветовой температуры
2. 💡 Поддержка нескольких Key Light одновременно
3. 🔍 Автоматическое обнаружение устройств в сети (mDNS)
4. ⏱️ Задержки включения/выключения (избегаем мигания)
5. 🎯 Профили света для разных приложений (Zoom, FaceTime, и т.д.)
6. 🔔 Системные уведомления macOS

---

## Установка (5 минут)

### Шаг 1: Установите зависимости

```bash
pip3 install requests zeroconf
```

Или через requirements.txt:
```bash
pip3 install -r requirements.txt
```

---

### Шаг 2: Найдите ваши устройства автоматически

```bash
python3 elgato_camera_control_advanced.py --discover
```

Вы увидите:
```
🔍 Сканирование сети (на 10 сек)...
🔍 Обнаружено устройство: Elgato Key Light 1A2B на 192.168.1.100:9123
🔍 Обнаружено устройство: Elgato Key Light 3C4D на 192.168.1.101:9123

✅ Найдено устройств: 2
   Elgato Key Light 1A2B - 192.168.1.100:9123
   Elgato Key Light 3C4D - 192.168.1.101:9123
```

**Запишите IP адреса!**

---

### Шаг 3: Создайте конфигурацию

#### Вариант A: Автоматически (рекомендуется)

```bash
python3 elgato_camera_control_advanced.py --create-config
```

Затем отредактируйте `config.json`:
```bash
nano config.json
# или
open -a TextEdit config.json
```

Вставьте ваш IP адрес:
```json
{
  "lights": [
    {
      "name": "Main Key Light",
      "ip": "192.168.1.100",  // ← ВАШИХ IP ЗДЕСЬ
      "enabled": true,
      "brightness": 100,
      "temperature": 200
    }
  ]
}
```

#### Вариант B: Скопируйте пример

```bash
cp config.example.json config.json
nano config.json  # Отредактируйте IP адреса
```

---

### Шаг 4: Запустите!

```bash
python3 elgato_camera_control_advanced.py
```

Готово! 🎉

---

## Примеры конфигураций

### Один Key Light (минимальная конфигурация)

```json
{
  "lights": [
    {
      "name": "My Key Light Neo",
      "ip": "192.168.1.100",
      "enabled": true,
      "brightness": 100,
      "temperature": 200
    }
  ]
}
```

---

### Два Key Light с разными настройками

```json
{
  "lights": [
    {
      "name": "Main Light",
      "ip": "192.168.1.100",
      "enabled": true,
      "brightness": 100,
      "temperature": 200
    },
    {
      "name": "Fill Light",
      "ip": "192.168.1.101",
      "enabled": true,
      "brightness": 60,
      "temperature": 180
    }
  ]
}
```

---

### Полная конфигурация с профилями

```json
{
  "lights": [
    {
      "name": "Main Key Light",
      "ip": "192.168.1.100",
      "enabled": true,
      "brightness": 100,
      "temperature": 200
    }
  ],
  "settings": {
    "check_interval": 2.0,
    "turn_on_delay": 0.5,
    "turn_off_delay": 2.0,
    "auto_discovery": true,
    "notifications": true
  },
  "profiles": {
    "Zoom": {
      "brightness": 100,
      "temperature": 200,
      "comment": "Полная яркость для видеозвонков"
    },
    "FaceTime": {
      "brightness": 90,
      "temperature": 180,
      "comment": "Чуть прохладнее"
    },
    "Photo Booth": {
      "brightness": 100,
      "temperature": 220,
      "comment": "Теплее для фото"
    },
    "default": {
      "brightness": 100,
      "temperature": 200,
      "comment": "По умолчанию для неизвестных приложений"
    }
  }
}
```

---

## Настройки

### Яркость (`brightness`)
- Диапазон: `0-100` (проценты)
- 100 = максимальная яркость
- 50 = средняя яркость
- Рекомендуется: 80-100 для видеозвонков

### Цветовая температура (`temperature`)
- Диапазон: `143-344` (единицы Elgato)
- **143** = 7000K (холодный дневной свет) ❄️
- **200** = 4500K (нейтральный белый) ⚪
- **260** = 3500K (теплый белый) 🔆
- **344** = 2900K (теплый лампа накаливания) 🔥

### Задержки (`settings`)

**turn_on_delay** (задержка включения):
- Рекомендуется: `0.5-1.0` секунды
- Избегает мгновенного включения (камера может открываться на секунду)

**turn_off_delay** (задержка выключения):
- Рекомендуется: `2.0-5.0` секунд
- Свет не будет мигать при временном отключении камеры

**check_interval** (интервал проверки):
- Рекомендуется: `1.0-3.0` секунды
- Чем меньше = быстрее реакция, но больше нагрузка

---

## Профили приложений

Автоматически определяются следующие приложения:
- **Zoom** (`zoom.us`)
- **FaceTime**
- **Photo Booth**
- **Google Chrome** → профиль `Chrome`
- **Safari**
- **Microsoft Teams** → профиль `Teams`
- **Skype**
- **Discord**
- **OBS**

Для неизвестных приложений используется профиль `default`.

---

## Команды

### Обнаружить устройства
```bash
python3 elgato_camera_control_advanced.py --discover
```

### Создать config.json
```bash
python3 elgato_camera_control_advanced.py --create-config
```

### Использовать другой конфиг
```bash
python3 elgato_camera_control_advanced.py --config /path/to/config.json
```

### Запустить обычную версию
```bash
python3 elgato_camera_control.py 192.168.1.100
```

---

## Уведомления macOS

Когда `notifications: true`, вы будете получать уведомления:

- 💡 "Свет включен (Zoom)" - когда камера включается
- 🌙 "Свет выключен" - когда камера выключается

Отключить: установите `"notifications": false` в config.json

---

## Автозапуск

### Вариант 1: Login Items (простой)

1. Создайте bash скрипт `start_elgato.sh`:
```bash
#!/bin/bash
cd /path/to/elgato
python3 elgato_camera_control_advanced.py
```

2. `chmod +x start_elgato.sh`

3. Системные настройки → Основные → Объекты входа → Добавить скрипт

### Вариант 2: launchd (продвинутый)

Создайте `~/Library/LaunchAgents/com.elgato.cameracontrol.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.elgato.cameracontrol</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/python3</string>
        <string>/Users/YOURNAME/elgato/elgato_camera_control_advanced.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
```

Затем:
```bash
launchctl load ~/Library/LaunchAgents/com.elgato.cameracontrol.plist
```

---

## Примеры использования

### Видеозвонки
```json
"Zoom": {
  "brightness": 100,
  "temperature": 200
}
```
Полная яркость, нейтральный свет

### Стримы
```json
"OBS": {
  "brightness": 80,
  "temperature": 180
}
```
Немного приглушено, прохладнее

### Фотография
```json
"Photo Booth": {
  "brightness": 100,
  "temperature": 260
}
```
Полная яркость, теплый свет

---

## Troubleshooting

### Устройства не обнаруживаются
```bash
# Проверьте, что устройства в той же сети
ping 192.168.1.100

# Попробуйте установить Bonjour Browser для отладки mDNS
```

### Ошибка импорта zeroconf
```bash
pip3 install --upgrade zeroconf
```

### Камера не детектится
```bash
# Проверьте разрешения в System Settings
# Privacy & Security → Camera → Terminal (разрешить)
```

### Уведомления не работают
Первый раз нужно разрешить уведомления от Terminal/Python

---

## Сравнение версий

| Функция | Базовая | Advanced |
|---------|---------|----------|
| Управление одним светом | ✅ | ✅ |
| Несколько светов | ❌ | ✅ |
| Настройка яркости/температуры | ❌ | ✅ |
| Автообнаружение | ❌ | ✅ |
| Задержки | ❌ | ✅ |
| Профили приложений | ❌ | ✅ |
| Уведомления | ❌ | ✅ |
| Конфигурационный файл | ❌ | ✅ |

---

**Приятного использования! 💡📹**

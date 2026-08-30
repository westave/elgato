#!/usr/bin/env python3
"""
Elgato Key Light Camera Control - Advanced Version
Автоматическое управление Elgato Key Light с расширенными возможностями
"""

import subprocess
import time
import requests
import json
import sys
import os
import argparse
from typing import Optional, List, Dict, Tuple
from pathlib import Path
from zeroconf import ServiceBrowser, ServiceListener, Zeroconf
import threading

class ElgatoDevice:
    """Представление одного Elgato Key Light устройства"""

    def __init__(self, name: str, ip: str, brightness: int = 100, temperature: int = 200, enabled: bool = True):
        self.name = name
        self.ip = ip
        self.brightness = brightness
        self.temperature = temperature
        self.enabled = enabled
        self.port = 9123
        self.base_url = f"http://{ip}:{self.port}/elgato/lights"
        self.is_on = False
        # Состояние лампы, запомненное перед выключением, — чтобы включать
        # ровно с теми же яркостью/температурой
        self.last_brightness: Optional[int] = None
        self.last_temperature: Optional[int] = None

    def turn_on(self, brightness: Optional[int] = None, temperature: Optional[int] = None) -> bool:
        """Включить свет.

        Без параметров восстанавливается состояние, запомненное перед
        последним выключением (или, если его нет, лампа включается со
        своими текущими настройками).
        """
        if brightness is None and temperature is None:
            brightness = self.last_brightness
            temperature = self.last_temperature

        if self._set_state(True, brightness, temperature):
            self.is_on = True
            return True
        return False

    def turn_off(self) -> bool:
        """Выключить свет, запомнив текущие яркость/температуру"""
        self._remember_state()
        if self._set_state(False):
            self.is_on = False
            return True
        return False

    def _remember_state(self):
        """Сохранить текущие яркость/температуру лампы"""
        state = self.get_state()
        if state:
            if 'brightness' in state:
                self.last_brightness = int(state['brightness'])
            if 'temperature' in state:
                self.last_temperature = int(state['temperature'])

    def get_state(self) -> Optional[Dict]:
        """Получить текущее состояние лампы (on/brightness/temperature)"""
        try:
            response = requests.get(self.base_url, timeout=3)
            if response.status_code == 200:
                lights = response.json().get('lights') or []
                if lights:
                    return lights[0]
        except requests.exceptions.RequestException:
            pass
        return None

    def _set_state(self, on: bool, brightness: Optional[int] = None,
                   temperature: Optional[int] = None) -> bool:
        """Установить состояние света; None-параметры не отправляются"""
        if not self.enabled:
            return False

        light: Dict[str, int] = {"on": 1 if on else 0}
        if brightness is not None:
            light["brightness"] = brightness
        if temperature is not None:
            light["temperature"] = temperature

        payload = {
            "numberOfLights": 1,
            "lights": [light]
        }

        try:
            response = requests.put(
                self.base_url,
                json=payload,
                timeout=5
            )

            if response.status_code == 200:
                return True
            else:
                print(f"⚠️  {self.name}: responded with status {response.status_code}")
                return False

        except requests.exceptions.RequestException as e:
            print(f"❌ Error controlling {self.name}: {e}")
            return False

    def get_status(self) -> Optional[bool]:
        """Получить текущее состояние света"""
        try:
            response = requests.get(self.base_url, timeout=5)
            if response.status_code == 200:
                data = response.json()
                if 'lights' in data and len(data['lights']) > 0:
                    return data['lights'][0].get('on') == 1
        except requests.exceptions.RequestException:
            pass
        return None


class ElgatoDiscovery(ServiceListener):
    """Автоматическое обнаружение Elgato устройств через mDNS"""

    def __init__(self):
        self.discovered_devices: List[Dict[str, str]] = []
        self.lock = threading.Lock()

    def add_service(self, zc: Zeroconf, type_: str, name: str) -> None:
        info = zc.get_service_info(type_, name)
        if info:
            address = '.'.join(map(str, info.addresses[0]))
            port = info.port

            with self.lock:
                self.discovered_devices.append({
                    'name': name,
                    'ip': address,
                    'port': port
                })
                print(f"🔍 Обнаружено устройство: {name} на {address}:{port}")

    def remove_service(self, zc: Zeroconf, type_: str, name: str) -> None:
        pass

    def update_service(self, zc: Zeroconf, type_: str, name: str) -> None:
        pass

    @staticmethod
    def discover(timeout: int = 5) -> List[Dict[str, str]]:
        """Сканировать сеть на наличие Elgato устройств"""
        print(f"🔍 Сканирование сети (на {timeout} сек)...")

        zeroconf = Zeroconf()
        listener = ElgatoDiscovery()
        browser = ServiceBrowser(zeroconf, "_elg._tcp.local.", listener)

        time.sleep(timeout)

        zeroconf.close()

        return listener.discovered_devices


class CameraMonitor:
    """Мониторинг состояния камеры на macOS"""

    # Бинарник собирается install.sh из Tools/camera-state.swift и опрашивает
    # CoreMediaIO (kCMIODevicePropertyDeviceIsRunningSomewhere) — тот же
    # сигнал, что и зелёный индикатор камеры. Работает на Intel и Apple
    # Silicon, в отличие от эвристики по lsof.
    HELPER_PATH = Path(__file__).resolve().parent / '.build' / 'camera-state'

    def __init__(self, detect_apps: bool = False):
        self.last_state = False
        self.active_app = None
        # Определение приложения требует полного скана lsof (до 5-8 секунд
        # на нагруженном Mac) — включаем только если реально используются
        # профили приложений, иначе это лишняя задержка включения света
        self.detect_apps = detect_apps

        helper = self.HELPER_PATH
        if helper.is_file() and os.access(helper, os.X_OK):
            self.helper: Optional[str] = str(helper)
            print("📷 Определение камеры: CoreMediaIO helper (надёжный режим)")
        else:
            self.helper = None
            print("📷 Определение камеры: lsof (ненадёжно на новых macOS!)")
            print("   Запустите ./install.sh чтобы собрать CoreMediaIO helper")

    def is_camera_active(self) -> Tuple[bool, Optional[str]]:
        """
        Проверить, активна ли камера и какое приложение её использует
        Возвращает (is_active, app_name)
        """
        if self.helper:
            state = self._check_via_helper()
            if state is not None:
                app_name = None
                if state and self.detect_apps:
                    app_name = self._detect_app()
                return state, app_name

        return self._check_via_lsof()

    def _check_via_helper(self) -> Optional[bool]:
        """Проверка через CoreMediaIO helper. None = helper не сработал."""
        try:
            result = subprocess.run(
                [self.helper],
                capture_output=True,
                timeout=5
            )
            if result.returncode == 0:
                return True
            if result.returncode == 1:
                return False
        except Exception as e:
            print(f"⚠️  camera-state helper error: {e}")
        return None

    def _detect_app(self) -> Optional[str]:
        """Определить приложение, использующее камеру (best-effort, через lsof)"""
        # Пока камера остаётся активной, не пересканируем lsof каждый цикл
        if self.last_state and self.active_app:
            return self.active_app

        _, app_name = self._check_via_lsof()
        return app_name

    def _check_via_lsof(self) -> Tuple[bool, Optional[str]]:
        """Старый метод определения камеры по процессам (fallback)"""
        try:
            result = subprocess.run(
                ['lsof', '-w'],
                capture_output=True,
                text=True,
                timeout=5
            )

            output = result.stdout

            # Ищем процессы, использующие камеру
            camera_keywords = [
                ('AppleCamera', 'Camera'),
                ('VDCAssistant', 'VDC'),
            ]

            # Проверяем известные приложения
            app_patterns = {
                'zoom.us': 'Zoom',
                'FaceTime': 'FaceTime',
                'Photo Booth': 'Photo Booth',
                'Google Chrome': 'Chrome',
                'Safari': 'Safari',
                'Microsoft Teams': 'Teams',
                'Skype': 'Skype',
                'Discord': 'Discord',
                'OBS': 'OBS',
            }

            for line in output.split('\n'):
                for keyword, _ in camera_keywords:
                    if keyword in line:
                        # Попытаться определить приложение
                        for pattern, app_name in app_patterns.items():
                            if pattern in line:
                                return True, app_name
                        return True, None

            return False, None

        except subprocess.TimeoutExpired:
            print("⚠️  lsof timeout")
            return False, None
        except Exception as e:
            print(f"❌ Error checking camera status: {e}")
            return False, None

    def check_state_changed(self) -> Tuple[bool, bool, Optional[str]]:
        """
        Проверить изменилось ли состояние камеры
        Возвращает (is_active, has_changed, app_name)
        """
        current_state, app_name = self.is_camera_active()
        has_changed = current_state != self.last_state

        self.active_app = app_name if current_state else None
        if has_changed:
            self.last_state = current_state

        return current_state, has_changed, app_name


class Config:
    """Управление конфигурацией"""

    DEFAULT_CONFIG = {
        "lights": [],
        "settings": {
            "check_interval": 0.5,
            "turn_on_delay": 0.0,
            "turn_off_delay": 2.0,
            "auto_discovery": True,
            "notifications": True,
            "apply_profiles": False
        },
        "profiles": {
            "default": {
                "brightness": 100,
                "temperature": 200
            }
        }
    }

    def __init__(self, config_path: Optional[str] = None):
        if config_path is None:
            config_path = os.path.join(os.path.dirname(__file__), 'config.json')

        self.config_path = config_path
        self.data = self.load()

    def load(self) -> dict:
        """Загрузить конфигурацию из файла"""
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, 'r') as f:
                    config = json.load(f)
                    # Merge with defaults
                    merged = self.DEFAULT_CONFIG.copy()
                    merged.update(config)
                    return merged
            except Exception as e:
                print(f"⚠️  Ошибка загрузки конфига: {e}")
                return self.DEFAULT_CONFIG.copy()
        return self.DEFAULT_CONFIG.copy()

    def save(self) -> bool:
        """Сохранить конфигурацию в файл"""
        try:
            with open(self.config_path, 'w') as f:
                json.dump(self.data, f, indent=2)
            return True
        except Exception as e:
            print(f"❌ Ошибка сохранения конфига: {e}")
            return False

    def get_devices(self) -> List[ElgatoDevice]:
        """Получить список устройств из конфига"""
        devices = []
        for light_config in self.data.get('lights', []):
            device = ElgatoDevice(
                name=light_config.get('name', 'Unknown'),
                ip=light_config['ip'],
                brightness=light_config.get('brightness', 100),
                temperature=light_config.get('temperature', 200),
                enabled=light_config.get('enabled', True)
            )
            devices.append(device)
        return devices

    def get_profile(self, app_name: Optional[str]) -> Dict[str, int]:
        """Получить профиль света для приложения"""
        profiles = self.data.get('profiles', {})

        if app_name and app_name in profiles:
            return profiles[app_name]

        return profiles.get('default', {'brightness': 100, 'temperature': 200})


class NotificationManager:
    """Управление системными уведомлениями macOS"""

    @staticmethod
    def send(title: str, message: str, sound: bool = False):
        """Отправить системное уведомление"""
        script = f'''
        display notification "{message}" with title "{title}"
        '''

        if sound:
            script += ' sound name "default"'

        try:
            subprocess.run(
                ['osascript', '-e', script],
                capture_output=True,
                timeout=5
            )
        except Exception:
            pass


class ElgatoCameraControl:
    """Главный контроллер приложения"""

    def __init__(self, config_path: Optional[str] = None):
        self.config = Config(config_path)
        self.devices: List[ElgatoDevice] = []
        self.camera = CameraMonitor(
            detect_apps=self.config.data['settings'].get('apply_profiles', False)
        )
        self.running = False
        self.turn_on_timer = None
        self.turn_off_timer = None

    def setup(self):
        """Начальная настройка"""
        print("🎥 Elgato Key Light Camera Control - Advanced")
        print("=" * 60)

        # Автообнаружение, если включено
        if self.config.data['settings'].get('auto_discovery', False):
            discovered = ElgatoDiscovery.discover()

            if discovered:
                print(f"\n✅ Найдено устройств: {len(discovered)}")

                # Добавить обнаруженные устройства в конфиг если их нет
                existing_ips = [l['ip'] for l in self.config.data.get('lights', [])]

                for device in discovered:
                    if device['ip'] not in existing_ips:
                        self.config.data.setdefault('lights', []).append({
                            'name': device['name'],
                            'ip': device['ip'],
                            'enabled': True,
                            'brightness': 100,
                            'temperature': 200
                        })

                self.config.save()

        # Загрузить устройства
        self.devices = self.config.get_devices()

        if not self.devices:
            print("\n❌ Не найдено ни одного устройства!")
            print("   Создайте config.json на основе config.example.json")
            return False

        print(f"\n📋 Загружено устройств: {len(self.devices)}")
        for device in self.devices:
            status = device.get_status()
            status_str = "ON" if status else "OFF" if status is not None else "OFFLINE"
            enabled_str = "✅" if device.enabled else "⏸️"
            print(f"   {enabled_str} {device.name} ({device.ip}) - {status_str}")

        # Показать настройки
        settings = self.config.data['settings']
        print(f"\n⚙️  Настройки:")
        print(f"   Интервал проверки: {settings['check_interval']}с")
        print(f"   Задержка включения: {settings['turn_on_delay']}с")
        print(f"   Задержка выключения: {settings['turn_off_delay']}с")
        print(f"   Уведомления: {'Вкл' if settings['notifications'] else 'Выкл'}")

        # Показать профили
        profiles = self.config.data.get('profiles', {})
        if profiles:
            print(f"\n💡 Профили освещения: {len(profiles)}")
            for app, profile in profiles.items():
                print(f"   {app}: {profile['brightness']}% яркость, {profile['temperature']} температура")

        return True

    def turn_lights_on(self, app_name: Optional[str]):
        """Включить все светы (с профилем, если включено apply_profiles)"""
        app_str = f" ({app_name})" if app_name else ""
        print(f"💡 Включаю свет{app_str}...")

        # По умолчанию профили выключены: лампа включается с последними
        # своими настройками яркости/температуры, не затирая их.
        if self.config.data['settings'].get('apply_profiles', False):
            profile = self.config.get_profile(app_name)
            brightness, temperature = profile['brightness'], profile['temperature']
            print(f"   Профиль: {brightness}% яркость, {temperature} температура")
        else:
            brightness = temperature = None
            print("   Восстанавливаю последнее состояние лампы")

        for device in self.devices:
            if device.enabled:
                device.turn_on(brightness, temperature)
                print(f"   ✅ {device.name}: ON")

        if self.config.data['settings']['notifications']:
            NotificationManager.send(
                "Elgato Key Light",
                f"Свет включен{app_str}"
            )

    def turn_lights_off(self):
        """Выключить все светы"""
        print(f"🌙 Выключаю свет...")

        for device in self.devices:
            if device.enabled:
                device.turn_off()
                print(f"   ✅ {device.name}: OFF")

        if self.config.data['settings']['notifications']:
            NotificationManager.send(
                "Elgato Key Light",
                "Свет выключен"
            )

    def handle_camera_change(self, is_active: bool, app_name: Optional[str]):
        """Обработать изменение состояния камеры с задержками"""
        settings = self.config.data['settings']

        # Отменить предыдущие таймеры
        if self.turn_on_timer:
            self.turn_on_timer.cancel()
        if self.turn_off_timer:
            self.turn_off_timer.cancel()

        if is_active:
            delay = settings['turn_on_delay']
            if delay <= 0:
                print("📹 Камера АКТИВНА")
                self.turn_lights_on(app_name)
            else:
                print(f"📹 Камера АКТИВНА (задержка {delay}с)...")
                self.turn_on_timer = threading.Timer(
                    delay,
                    lambda: self.turn_lights_on(app_name)
                )
                self.turn_on_timer.start()
        else:
            # Выключить с задержкой
            delay = settings['turn_off_delay']
            print(f"📴 Камера НЕАКТИВНА (задержка {delay}с)...")

            self.turn_off_timer = threading.Timer(
                delay,
                self.turn_lights_off
            )
            self.turn_off_timer.start()

    def run(self, daemon: bool = False):
        """Запустить мониторинг.

        daemon=True (запуск из launchd): не завершаться, если устройства
        ещё не найдены (сеть могла не подняться после логина/сна), а
        повторять поиск каждые 30 секунд.
        """
        while not self.setup():
            if not daemon:
                return
            print("⏳ Устройства не найдены, повторный поиск через 30с...")
            time.sleep(30)

        print("\n🚀 Мониторинг камеры начат...")
        print("   (Нажмите Ctrl+C для выхода)\n")

        self.running = True
        check_interval = self.config.data['settings']['check_interval']

        try:
            while self.running:
                is_active, has_changed, app_name = self.camera.check_state_changed()

                if has_changed:
                    timestamp = time.strftime("%H:%M:%S")
                    print(f"\n[{timestamp}] ", end="")
                    self.handle_camera_change(is_active, app_name)

                time.sleep(check_interval)

        except KeyboardInterrupt:
            print("\n\n👋 Завершение работы...")

            # Отменить таймеры
            if self.turn_on_timer:
                self.turn_on_timer.cancel()
            if self.turn_off_timer:
                self.turn_off_timer.cancel()

            self.running = False


def main():
    """Главная функция"""
    parser = argparse.ArgumentParser(
        description='Elgato Key Light Camera Control - Advanced'
    )
    parser.add_argument(
        '--config',
        '-c',
        help='Path to config file (default: config.json)',
        default=None
    )
    parser.add_argument(
        '--discover',
        '-d',
        action='store_true',
        help='Discover Elgato devices and exit'
    )
    parser.add_argument(
        '--create-config',
        action='store_true',
        help='Create example config.json and exit'
    )
    parser.add_argument(
        '--daemon',
        action='store_true',
        help='Run as launchd daemon: retry discovery instead of exiting when no devices found'
    )

    args = parser.parse_args()

    # Режим обнаружения
    if args.discover:
        devices = ElgatoDiscovery.discover(timeout=10)
        if devices:
            print(f"\n✅ Найдено устройств: {len(devices)}")
            for d in devices:
                print(f"   {d['name']} - {d['ip']}:{d['port']}")
        else:
            print("\n❌ Устройства не найдены")
        return

    # Создание конфига
    if args.create_config:
        config_path = 'config.json'
        if os.path.exists(config_path):
            print(f"⚠️  {config_path} уже существует!")
            return

        example_config = Config.DEFAULT_CONFIG.copy()
        example_config['lights'] = [
            {
                "name": "Main Key Light",
                "ip": "192.168.1.100",
                "enabled": True,
                "brightness": 100,
                "temperature": 200
            }
        ]

        with open(config_path, 'w') as f:
            json.dump(example_config, f, indent=2)

        print(f"✅ Создан {config_path}")
        print("   Отредактируйте IP адрес и запустите снова")
        return

    # Запустить приложение
    controller = ElgatoCameraControl(args.config)
    controller.run(daemon=args.daemon)


if __name__ == "__main__":
    main()

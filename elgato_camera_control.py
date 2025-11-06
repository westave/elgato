#!/usr/bin/env python3
"""
Elgato Key Light Camera Control
Автоматически управляет Elgato Key Light в зависимости от активности камеры на macOS
"""

import subprocess
import time
import requests
import json
import sys
from typing import Optional

class ElgatoController:
    """Управление Elgato Key Light через HTTP API"""

    def __init__(self, ip_address: str, port: int = 9123):
        self.ip_address = ip_address
        self.port = port
        self.base_url = f"http://{ip_address}:{port}/elgato/lights"

    def turn_on(self) -> bool:
        """Включить свет"""
        return self._set_state(True)

    def turn_off(self) -> bool:
        """Выключить свет"""
        return self._set_state(False)

    def _set_state(self, on: bool) -> bool:
        """Установить состояние света"""
        payload = {
            "numberOfLights": 1,
            "lights": [
                {
                    "on": 1 if on else 0,
                    "brightness": 100,
                    "temperature": 200
                }
            ]
        }

        try:
            response = requests.put(
                self.base_url,
                json=payload,
                timeout=5
            )

            if response.status_code == 200:
                state_str = "ON" if on else "OFF"
                print(f"✅ Key Light turned {state_str}")
                return True
            else:
                print(f"⚠️  Key Light responded with status {response.status_code}")
                return False

        except requests.exceptions.RequestException as e:
            print(f"❌ Error controlling Key Light: {e}")
            return False

    def get_status(self) -> Optional[bool]:
        """Получить текущее состояние света"""
        try:
            response = requests.get(self.base_url, timeout=5)
            if response.status_code == 200:
                data = response.json()
                if 'lights' in data and len(data['lights']) > 0:
                    return data['lights'][0].get('on') == 1
        except requests.exceptions.RequestException as e:
            print(f"❌ Error getting Key Light status: {e}")
        return None


class CameraMonitor:
    """Мониторинг состояния камеры на macOS"""

    def __init__(self):
        self.last_state = False

    def is_camera_active(self) -> bool:
        """Проверить, активна ли камера"""
        try:
            # Используем lsof для проверки процессов, использующих камеру
            result = subprocess.run(
                ['lsof'],
                capture_output=True,
                text=True,
                timeout=5
            )

            output = result.stdout

            # Ключевые слова, указывающие на использование камеры
            camera_keywords = [
                'AppleCamera',
                'VDCAssistant',
                'FaceTime',
                'USBVDC',
                '0x8000000004',  # FaceTime HD Camera ID
            ]

            for keyword in camera_keywords:
                if keyword in output:
                    return True

            return False

        except subprocess.TimeoutExpired:
            print("⚠️  lsof timeout")
            return False
        except Exception as e:
            print(f"❌ Error checking camera status: {e}")
            return False

    def check_state_changed(self) -> tuple[bool, bool]:
        """
        Проверить изменилось ли состояние камеры
        Возвращает (is_active, has_changed)
        """
        current_state = self.is_camera_active()
        has_changed = current_state != self.last_state

        if has_changed:
            self.last_state = current_state

        return current_state, has_changed


def main():
    """Главная функция"""
    print("🎥 Elgato Key Light Camera Control")
    print("=" * 50)

    # Получить IP адрес от пользователя
    if len(sys.argv) > 1:
        key_light_ip = sys.argv[1]
    else:
        key_light_ip = input("Введите IP адрес Elgato Key Light: ").strip()

    if not key_light_ip:
        print("❌ IP адрес не указан")
        sys.exit(1)

    # Инициализация
    elgato = ElgatoController(key_light_ip)
    camera = CameraMonitor()

    # Проверить соединение со светом
    print(f"\n🔍 Проверка соединения с {key_light_ip}...")
    status = elgato.get_status()
    if status is None:
        print("❌ Не удалось подключиться к Key Light")
        print("   Проверьте IP адрес и убедитесь, что устройство включено")
        sys.exit(1)

    print(f"✅ Подключено к Key Light (текущее состояние: {'ON' if status else 'OFF'})")
    print("\n🚀 Мониторинг камеры начат...")
    print("   (Нажмите Ctrl+C для выхода)\n")

    check_interval = 2  # секунды

    try:
        while True:
            is_active, has_changed = camera.check_state_changed()

            if has_changed:
                timestamp = time.strftime("%H:%M:%S")
                if is_active:
                    print(f"[{timestamp}] 📹 Камера АКТИВНА → Включаю свет...")
                    elgato.turn_on()
                else:
                    print(f"[{timestamp}] 📴 Камера НЕАКТИВНА → Выключаю свет...")
                    elgato.turn_off()

            time.sleep(check_interval)

    except KeyboardInterrupt:
        print("\n\n👋 Завершение работы...")
        # Опционально: выключить свет при завершении
        # elgato.turn_off()
        sys.exit(0)


if __name__ == "__main__":
    main()

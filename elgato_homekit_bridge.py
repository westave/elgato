#!/usr/bin/env python3
"""
Elgato Key Light → HomeKit Bridge
Виртуальный HomeKit-мост (HAP-python): все Key Light из config.json
появляются в Apple Home как обычные лампы с яркостью и цветовой
температурой. Состояние синхронизируется в обе стороны — если свет
включил скрипт камеры, Home App это увидит через пару секунд.

Запуск:  python3 elgato_homekit_bridge.py
Пары:    Home App → "+" → Добавить аксессуар → "Нет кода или не удаётся
         отсканировать" → Elgato Bridge → код 031-45-154
"""

import asyncio
import json
import os
import signal
import sys
import time
from pathlib import Path

import requests
from pyhap.accessory import Accessory, Bridge
from pyhap.accessory_driver import AccessoryDriver
from pyhap.const import CATEGORY_LIGHTBULB

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from elgato_camera_control_advanced import Config, ElgatoDiscovery  # noqa: E402

PINCODE = b"031-45-154"
HAP_PORT = 51826
STATE_FILE = SCRIPT_DIR / ".homekit.state"

# Elgato использует миреды (144–344 ≈ 7000K–2900K), HomeKit тоже миреды —
# конвертация не нужна, только ограничение диапазона.
ELGATO_TEMP_MIN = 143
ELGATO_TEMP_MAX = 344
ELGATO_BRIGHTNESS_MIN = 3


class KeyLightAccessory(Accessory):
    """Один Elgato Key Light как HomeKit-лампа"""

    category = CATEGORY_LIGHTBULB

    def __init__(self, driver, name: str, ip: str):
        super().__init__(driver, name)
        self.ip = ip
        self.url = f"http://{ip}:9123/elgato/lights"

        service = self.add_preload_service(
            "Lightbulb", chars=["Brightness", "ColorTemperature"]
        )
        self.char_on = service.configure_char(
            "On", setter_callback=self.set_on
        )
        self.char_brightness = service.configure_char(
            "Brightness", value=100, setter_callback=self.set_brightness
        )
        self.char_temperature = service.configure_char(
            "ColorTemperature", value=200, setter_callback=self.set_temperature
        )
        self.char_temperature.override_properties(properties={
            "minValue": ELGATO_TEMP_MIN,
            "maxValue": ELGATO_TEMP_MAX,
            "minStep": 1,
        })

    # --- HomeKit → лампа -------------------------------------------------

    def _put(self, fields: dict) -> None:
        payload = {"numberOfLights": 1, "lights": [fields]}
        try:
            requests.put(self.url, json=payload, timeout=2)
        except requests.exceptions.RequestException as e:
            print(f"⚠️  {self.display_name}: не удалось отправить команду: {e}")

    def set_on(self, value):
        self._put({"on": 1 if value else 0})

    def set_brightness(self, value):
        self._put({"brightness": max(ELGATO_BRIGHTNESS_MIN, int(value))})

    def set_temperature(self, value):
        temp = max(ELGATO_TEMP_MIN, min(ELGATO_TEMP_MAX, int(value)))
        self._put({"temperature": temp})

    # --- лампа → HomeKit -------------------------------------------------

    @Accessory.run_at_interval(3)
    async def run(self):
        """Опрос лампы, чтобы Home App показывал актуальное состояние"""
        try:
            response = requests.get(self.url, timeout=2)
            if response.status_code != 200:
                return
            lights = response.json().get("lights") or []
            if not lights:
                return
            state = lights[0]
        except (requests.exceptions.RequestException, ValueError):
            return

        if "on" in state:
            self.char_on.set_value(bool(state["on"]))
        if "brightness" in state:
            self.char_brightness.set_value(int(state["brightness"]))
        if "temperature" in state:
            temp = max(ELGATO_TEMP_MIN,
                       min(ELGATO_TEMP_MAX, int(state["temperature"])))
            self.char_temperature.set_value(temp)


def wait_for_lights(config: Config) -> list:
    """Получить лампы из конфига; если их нет — искать в сети до успеха"""
    while True:
        lights = [l for l in config.data.get("lights", [])
                  if l.get("enabled", True)]
        if lights:
            return lights

        print("🔍 В конфиге нет ламп, ищу в сети...")
        discovered = ElgatoDiscovery.discover(timeout=10)
        for device in discovered:
            config.data.setdefault("lights", []).append({
                "name": device["name"].split(".")[0],
                "ip": device["ip"],
                "enabled": True,
                "brightness": 100,
                "temperature": 200,
            })
        if discovered:
            config.save()
        else:
            print("⏳ Лампы не найдены, повторный поиск через 30с...")
            time.sleep(30)


def run_driver(driver: AccessoryDriver) -> None:
    """Запуск event loop без driver.start().

    driver.start() в HAP-python (вплоть до 5.0.0) вызывает
    asyncio.SafeChildWatcher, который удалён в Python 3.14 — на нём мост
    падал на старте. Здесь то же самое, что делает start(), но без
    child watcher (дочерние процессы мост не запускает).
    """
    loop = driver.loop
    try:
        driver.add_job(driver.async_start())
        loop.run_forever()
    except KeyboardInterrupt:
        loop.call_soon_threadsafe(loop.create_task, driver.async_stop())
        loop.run_forever()
    finally:
        loop.close()


def main():
    print("🏠 Elgato Key Light → HomeKit Bridge")
    print("=" * 60)

    config = Config(str(SCRIPT_DIR / "config.json"))
    lights = wait_for_lights(config)

    driver = AccessoryDriver(
        port=HAP_PORT,
        persist_file=str(STATE_FILE),
        pincode=PINCODE,
    )

    bridge = Bridge(driver, "Elgato Bridge")
    for light in lights:
        name = light.get("name", f"Key Light {light['ip']}")
        print(f"💡 Добавляю в мост: {name} ({light['ip']})")
        bridge.add_accessory(KeyLightAccessory(driver, name, light["ip"]))

    driver.add_accessory(accessory=bridge)
    signal.signal(signal.SIGTERM, driver.signal_handler)

    print()
    print("✅ Мост запущен. Добавление в Home App:")
    print('   1. Home App → "+" → Добавить аксессуар')
    print('   2. "Нет кода или не удаётся отсканировать"')
    print('   3. Выберите "Elgato Bridge"')
    print(f"   4. Код: {PINCODE.decode()}")
    print()

    run_driver(driver)


if __name__ == "__main__":
    main()

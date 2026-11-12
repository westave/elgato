import asyncio
import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from pyhap.accessory import Bridge
from pyhap.accessory_driver import AccessoryDriver

from elgato_homekit_bridge import KeyLightAccessory, accessory_ids, run_driver


class BridgeStateTests(unittest.TestCase):
    def test_lamp_ids_survive_reordering_removal_and_addition(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            initial = accessory_ids(root, [{"ip": "a"}, {"ip": "b"}])
            changed = accessory_ids(root, [{"ip": "b"}, {"ip": "c"}, {"ip": "a"}])
            self.assertEqual(changed["a"], initial["a"])
            self.assertEqual(changed["b"], initial["b"])
            after_removal = accessory_ids(root, [{"ip": "a"}, {"ip": "d"}])
            self.assertNotIn(after_removal["d"], initial.values())

    def test_startup_failure_exits_instead_of_leaving_an_unreachable_process(self):
        loop = asyncio.new_event_loop()

        class FailedDriver:
            async def async_start(self):
                raise OSError("Port already in use")

        driver = FailedDriver()
        driver.loop = loop
        with patch("sys.stderr"), self.assertRaises(SystemExit) as failure:
            run_driver(driver)
        self.assertEqual(failure.exception.code, 1)
        self.assertTrue(loop.is_closed())

    def test_fresh_installations_have_different_bridge_identities(self):
        with tempfile.TemporaryDirectory() as directory:
            identities = []
            for index in range(2):
                loop = asyncio.new_event_loop()
                path = Path(directory) / f"state-{index}.json"
                driver = AccessoryDriver(address="127.0.0.1", loop=loop,
                                         pincode=b"031-45-154", persist_file=str(path))
                driver.add_accessory(Bridge(driver, "Elgato Bridge"))
                identities.append(json.loads(path.read_text())["mac"])
                loop.close()
            self.assertNotEqual(*identities)


class PollingTests(unittest.IsolatedAsyncioTestCase):
    async def test_slow_lamp_does_not_block_homekit_event_loop(self):
        driver = AccessoryDriver(address="127.0.0.1", loop=asyncio.get_running_loop())
        driver.aio_stop_event = asyncio.Event()
        driver.aio_stop_event.set()
        lamp = KeyLightAccessory(driver, "Test lamp", "127.0.0.1")

        def slow_read():
            time.sleep(0.15)
            return {"on": 1, "brightness": 19, "temperature": 344}

        with patch.object(lamp, "_read_state", side_effect=slow_read):
            polling = asyncio.create_task(lamp.run())
            await asyncio.sleep(0.02)
            self.assertFalse(polling.done())
            await asyncio.wait_for(polling, timeout=3)
        self.assertTrue(lamp.char_on.value)
        self.assertEqual(lamp.char_brightness.value, 19)
        self.assertEqual(lamp.char_temperature.value, 344)


if __name__ == "__main__":
    unittest.main()

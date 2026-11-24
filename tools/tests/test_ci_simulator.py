import importlib.util
from pathlib import Path
import unittest


SPEC = importlib.util.spec_from_file_location(
    "ci_simulator", Path(__file__).resolve().parents[1] / "select-ci-ios-simulator.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CISimulatorTests(unittest.TestCase):
    def device(self, identifier, name="iPad Pro 11-inch (M5)", available=True):
        return {"udid": identifier, "name": name, "isAvailable": available}

    def test_selects_sdk_runtime_not_first_or_booted_older_runtime(self):
        devices = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                self.device("old") | {"state": "Booted"}
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [self.device("matching")],
        }}
        self.assertEqual(MODULE.select_device(devices, "26.2")[0], "matching")

    def test_prefers_ipad_pro_over_other_ipad_models(self):
        devices = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
            self.device("unavailable", "iPad Air 13-inch (M4)", False),
            self.device("regular", "iPad (A16)"),
            self.device("preferred", "iPad Pro 11-inch (M5)"),
        ]}}
        self.assertEqual(MODULE.select_device(devices, "26.2")[0], "preferred")

    def test_newest_available_runtime_wins_over_exact_sdk_runtime(self):
        devices = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [self.device("broken")],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-2": [self.device("healthy")],
        }}
        self.assertEqual(MODULE.select_device(devices, "27.0")[0], "healthy")

    def test_missing_ipad_runtime_fails(self):
        with self.assertRaisesRegex(ValueError, "No available iPad simulator"):
            MODULE.select_device({"devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [self.device("old", "iPhone 16")]
            }}, "26.2")

    def test_unavailable_or_non_ipad_devices_are_rejected(self):
        with self.assertRaises(ValueError):
            MODULE.select_device({"devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
                    self.device("off", available=False),
                    self.device("phone", "iPhone 16 Pro"),
                ]
            }}, "26.2")


if __name__ == "__main__":
    unittest.main()

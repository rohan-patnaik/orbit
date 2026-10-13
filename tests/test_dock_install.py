import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("install_dock", Path(__file__).resolve().parents[1] / "scripts/install-dock.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class DockInstallTests(unittest.TestCase):
    def test_existing_pins_order_and_other_widgets_are_preserved(self):
        old = {"bar": {"position": "bottom", "centerAnchor": "taskbar", "layout": {"left": [{"id": "clock"}], "center": [{"id": "taskbar", "type": "qml", "source": "old/Taskbar.qml", "pins": [{"desktopId": "firefox", "extra": 7}], "taskOrder": ["firefox", "files"], "future": True}], "right": [{"id": "tray"}]}}, "plugins": [{"id": "unrelated", "enabled": False}]}
        new = installer.dock_configuration(old)
        taskbar = new["bar"]["layout"]["center"][0]
        self.assertEqual(taskbar["pins"], old["bar"]["layout"]["center"][0]["pins"])
        self.assertEqual(taskbar["taskOrder"], ["firefox", "files"])
        self.assertTrue(taskbar["future"])
        self.assertEqual(new["plugins"], old["plugins"])
        self.assertEqual(new["bar"]["layout"]["left"], old["bar"]["layout"]["left"])
        self.assertEqual(new["bar"]["layout"]["right"], old["bar"]["layout"]["right"])
        self.assertEqual(old["bar"]["layout"]["center"][0]["source"], "old/Taskbar.qml")
        self.assertEqual(installer.dock_configuration(new), new)

    def test_new_dock_does_not_replace_existing_center_widgets(self):
        old = {"bar": {"layout": {"center": [{"id": "existing"}]}}, "plugins": []}
        new = installer.dock_configuration(old)
        self.assertEqual(new["bar"]["layout"]["center"][0], {"id": "existing"})
        self.assertEqual(new["bar"]["layout"]["center"][1]["id"], "taskbar")
        self.assertEqual(new["bar"]["centerAnchor"], "taskbar")

    def test_removal_preserves_pins_added_after_installation(self):
        old = {"bar": {"layout": {"center": [{"id": "taskbar", "type": "qml", "source": "old/Taskbar.qml", "pins": ["firefox"]}]}}}
        installed = installer.dock_configuration(old)
        installed["bar"]["layout"]["center"][0]["pins"].append("new-app")
        restored = installer.dock_configuration(installed, remove=True)
        taskbar = restored["bar"]["layout"]["center"][0]
        self.assertEqual(taskbar["source"], "old/Taskbar.qml")
        self.assertEqual(taskbar["pins"], ["firefox", "new-app"])
        self.assertNotIn("orbitPreviousDock", taskbar)

    def test_new_dock_removal_retains_settings_for_reinstallation(self):
        installed = installer.dock_configuration({"bar": {"layout": {"center": [{"id": "clock"}]}}})
        installed["bar"]["layout"]["center"][1]["pins"] = ["firefox"]
        removed = installer.dock_configuration(installed, remove=True)
        self.assertEqual(removed["bar"]["layout"]["center"], [{"id": "clock"}])
        self.assertEqual(removed["bar"]["orbitDockSettings"]["pins"], ["firefox"])
        reinstalled = installer.dock_configuration(removed)
        self.assertEqual(reinstalled["bar"]["layout"]["center"][1]["pins"], ["firefox"])

    def test_removal_does_not_guess_without_restore_evidence(self):
        installed = {"bar": {"layout": {"center": [{"id": "taskbar", "source": installer.DOCK_SOURCE}]}}}
        with self.assertRaises(ValueError):
            installer.dock_configuration(installed, remove=True)


if __name__ == "__main__":
    unittest.main()

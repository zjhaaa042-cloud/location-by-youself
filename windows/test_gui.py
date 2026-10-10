"""Headless regression tests for the GUI's asynchronous renewal lifecycle."""
import importlib.util
from pathlib import Path
import sys
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import Mock, patch


class Widget:
    def __init__(self, *args, **kwargs):
        self.state = kwargs.get('state', 'normal')
        self.text = kwargs.get('text', '')
        self.command = kwargs.get('command')
        self.messages = []
        self.callbacks = []
        widgets.append(self)

    def configure(self, **kwargs):
        self.state = kwargs.get('state', self.state)

    def insert(self, position, message):
        self.messages.append(message)

    def after(self, delay, callback):
        self.callbacks.append(callback)

    def __getattr__(self, name):
        return lambda *args, **kwargs: None


class Variable:
    def __init__(self, value):
        self.value = value
        variables.append(self)

    def get(self):
        return self.value

    def set(self, value):
        self.value = value


widgets = []
variables = []


class GuiTests(unittest.TestCase):
    def test_renewal_single_flight_and_completion(self):
        for exit_code in (0, 1):
            with self.subTest(exit_code=exit_code):
                widgets.clear()
                variables.clear()
                tk = ModuleType('tkinter')
                tk.Tk = tk.Text = Widget
                tk.StringVar = Variable
                tk.ttk = SimpleNamespace(Frame=Widget, Label=Widget, Entry=Widget, Button=Widget)
                tk.filedialog = tk.simpledialog = SimpleNamespace()
                spec = importlib.util.spec_from_file_location('gui_under_test', Path(__file__).with_name('gui.py'))
                gui = importlib.util.module_from_spec(spec)
                with patch.dict(sys.modules, {'tkinter': tk}):
                    spec.loader.exec_module(gui)
                workers = []
                def thread(**kwargs):
                    workers.append(kwargs['target'])
                    return SimpleNamespace(start=lambda: None)
                process = Mock()
                process.wait.return_value = exit_code
                with patch.object(gui.subprocess, 'Popen', return_value=process) as launch, patch.object(gui.threading, 'Thread', side_effect=thread):
                    gui.main()
                    variables[0].set('phone')
                    variables[1].set('app.ipa')
                    button = next(w for w in widgets if w.text == '免费 Apple ID：电脑安装 / 续签')
                    button.command()
                    self.assertEqual(button.state, 'disabled')
                    button.command()
                    self.assertEqual(launch.call_count, 1)
                    workers.pop()()
                    widgets[0].callbacks.pop(0)()
                    self.assertEqual(button.state, 'normal')
                    output = ''.join(m for w in widgets for m in w.messages)
                    self.assertIn('已完成' if exit_code == 0 else '失败', output)
                    button.command()
                    self.assertEqual(launch.call_count, 2)


if __name__ == '__main__':
    unittest.main()

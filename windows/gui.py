"""Small desktop front end; all device work runs outside the Tk event thread."""
from argparse import Namespace
import queue
import threading
import tkinter as tk
from tkinter import ttk, filedialog, simpledialog
import webbrowser
import installer


def main():
    root = tk.Tk()
    root.title('LocationMocker · Windows 安装与续签')
    root.geometry('750x510')
    frame = ttk.Frame(root, padding=20)
    frame.pack(fill='both', expand=True)
    values = {}
    for row, (name, label) in enumerate((('udid', '设备 UDID'), ('ipa', 'LocationMocker IPA'),
                                       ('p12', '签名证书 P12'), ('profile', '新描述文件'),
                                       ('zsign', 'zsign 路径'), ('openssl', 'OpenSSL 路径'))):
        ttk.Label(frame, text=label).grid(row=row, column=0, sticky='w', pady=5)
        value = tk.StringVar(value=name if name in ('zsign', 'openssl') else '')
        values[name] = value
        ttk.Entry(frame, textvariable=value, width=60).grid(row=row, column=1, sticky='ew')
        if name != 'udid':
            def browse(target=value):
                selected = filedialog.askopenfilename()
                if selected:
                    target.set(selected)
            ttk.Button(frame, text='选择', command=browse).grid(row=row, column=2)
    frame.columnconfigure(1, weight=1)
    output = tk.Text(frame, height=9, wrap='word', state='disabled')
    output.grid(row=8, column=0, columnspan=3, sticky='nsew', pady=10)
    events = queue.Queue()
    buttons = []

    def show(message):
        output.configure(state='normal')
        output.insert('end', message + '\n')
        output.see('end')
        output.configure(state='disabled')

    def action(kind):
        args = Namespace(**{k: v.get().strip() for k, v in values.items()})
        password = None
        if kind == 'prepare':
            args.output = filedialog.asksaveasfilename(defaultextension='.ipa')
            if not args.output:
                return
        if kind == 'install':
            password = simpledialog.askstring('签名', 'P12 密码（留空表示无密码）', show='*')
            if password is None:
                return
        for button in buttons:
            button.configure(state='disabled')
        show('正在处理，请保持手机解锁并确认信任…')

        def worker():
            try:
                if kind == 'devices':
                    result = installer.devices()
                elif kind == 'prepare':
                    result = installer.prepare(args)
                elif kind == 'status':
                    result = installer.status(args)
                else:
                    result = installer.sign_install(args, password=password)
                events.put((kind, result, None))
            except installer.InstallError as error:
                events.put((kind, None, f'{error.code}: {error}'))
            except Exception:
                events.put((kind, None, '操作失败，请检查依赖、设备信任和输入文件。'))
        threading.Thread(target=worker, daemon=True).start()

    bar = ttk.Frame(frame)
    bar.grid(row=6, column=0, columnspan=3, pady=12)
    for kind, title in (('devices', '检测手机'), ('prepare', '生成 iLoader 专用 IPA'),
                        ('status', '检查 IPA 到期日'), ('install', '签名并安装 / 续签')):
        button = ttk.Button(bar, text=title, command=lambda k=kind: action(k))
        button.pack(side='left', padx=3)
        buttons.append(button)
    ttk.Button(frame, text='获取 iLoader（免费 Apple ID 签名）',
               command=lambda: webbrowser.open('https://github.com/nab138/iloader')).grid(row=7, columnspan=3)

    def poll():
        try:
            kind, result, error = events.get_nowait()
            for button in buttons:
                button.configure(state='normal')
            if error:
                show(error)
            elif kind == 'devices':
                if len(result) == 1:
                    values['udid'].set(result[0]['udid'])
                show('\n'.join(f"{d['name']} / iOS {d['ios']} / {d['udid']}" for d in result) or '没有找到手机。')
            elif kind == 'prepare':
                show('已生成设备专属 IPA。请在 iLoader 导入此文件并签名安装：' + result['output'])
            else:
                show(str(result))
        except queue.Empty:
            pass
        root.after(100, poll)
    root.after(100, poll)
    root.mainloop()


if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == '--pmd':
        import runpy
        sys.argv = ['pymobiledevice3', *sys.argv[2:]]
        runpy.run_module('pymobiledevice3', run_name='__main__')
    else:
        main()

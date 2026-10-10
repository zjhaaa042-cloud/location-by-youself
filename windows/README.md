# Windows 安装工具

支持 Windows 11、Python 3.12，桌面界面与 CLI 共用核心。首次运行需要安装 Apple 设备驱动（Apple Devices 或 iTunes），手机解锁、开启开发者模式并信任电脑。

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r windows\requirements.txt
.\.venv\Scripts\python.exe windows\gui.py
```

GitHub Actions 的 `Windows installer` 会运行测试并生成 `LocationMocker-Windows` 压缩产物；下载并解压整个目录后运行其中的 EXE。zsign 和 OpenSSL 需要另行安装，未随 EXE 分发。

## 免费 Apple ID

1. 下载由 Mac/Xcode 构建的 LocationMocker IPA。
2. 点击“检测手机”，选择 IPA。
3. 点击“生成 iLoader 专用 IPA”，选择一个新的输出位置。
4. 在 [iLoader](https://github.com/nab138/iloader) 中导入输出 IPA，使用自己的 Apple ID 签名安装。
5. 续签时在 iLoader 中用相同账户、团队和应用标识重新签名安装，或导入 SideStore 后通过其刷新功能续签。后台刷新依赖这些工具的配置与运行条件。

输出 IPA 含此设备的配对私钥，仅供本机自用，不能分享或上传。它必须经过 iLoader 签名才能安装。工具不会申请 Apple ID 证书，也不会自行延长过期证书有效期。

## 已有开发证书

准备有效的 P12 和包含当前 UDID 的新 `.mobileprovision` 文件。安装 [zsign](https://github.com/zhlynn/zsign)（Windows 构建见其官方说明）和 OpenSSL 后，在界面选择这两个工具路径、IPA、证书和描述文件，点击“签名并安装 / 续签”。P12 密码只用于本次操作，不保存、不传入子进程参数。

```powershell
py windows\installer.py devices
py windows\installer.py prepare --udid YOUR_UDID --ipa LocationMocker.ipa --output personal.ipa
py windows\installer.py install --udid YOUR_UDID --ipa LocationMocker.ipa --p12 development.p12 --profile fresh.mobileprovision --zsign C:\Tools\zsign.exe --openssl C:\Tools\openssl.exe
py windows\installer.py renew --udid YOUR_UDID --ipa LocationMocker.ipa --p12 development.p12 --profile fresh.mobileprovision
py windows\installer.py status --udid YOUR_UDID --ipa signed.ipa
```

`install` 与 `renew` 都生成当前设备配对记录、校验描述文件、重签并覆盖安装，不执行卸载。使用相同 bundle identifier 和团队才能保留原应用数据；工具不提供跨团队的数据迁移。`status` 检查指定 IPA 的有效期，而非读取手机内 App 的实时到期日。JSON 输出只写 stdout，密码提示写 stderr。

## 当前限制与验证

- 只支持本项目无 App Extension 的 IPA，保留 OpenSSL.framework。
- 描述文件校验 CMS 完整性、到期日、UDID、应用标识和证书匹配；最终 Apple 信任、签名和 entitlements 判定由手机安装服务执行。
- 更新证书需用户提供新材料；无需把 Apple 账号交给本工具。
- Windows USB/RP pairing/DDI 与各 iOS 版本的兼容性需真机验证。App 注入仍需要 LocalDevVPN 和准备好的开发者服务，安装成功不代表注入成功。
- 当前不提供后台自动续签、账号证书申请、证书永久保存、自动启动 App 或完整 .NET GUI。桌面界面为 Tkinter。
- 私钥只在任务临时目录存在，任务结束清理；强制终止进程时可能留下临时目录，应在本机清理。配对库本身也可能在用户目录保存设备信任记录。

测试：`py -m unittest discover -s windows -p 'test_*.py' -v`。覆盖 IPA 路径攻击、设备/证书/profile 不匹配、失效、Framework 保留和错误脱敏；不能替代 Windows iPhone 真机验收。

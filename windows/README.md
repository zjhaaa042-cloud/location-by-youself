# Windows 安装工具

支持 Windows 11、Python 3.12，桌面界面与 CLI 共用核心。首次运行需要安装 Apple 设备驱动（Apple Devices 或 iTunes），手机解锁、开启开发者模式并信任电脑。

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r windows\requirements.txt
.\.venv\Scripts\python.exe windows\gui.py
```

在 [Windows installer 构建页](https://github.com/zjhaaa042-cloud/location-by-youself/actions/workflows/windows-installer.yml)选择 `ios` 分支最近一次成功运行，下载 Artifacts 中的 `LocationMocker-Windows`，完整解压后运行 EXE。免费账号模式已内置签名组件；只有 P12 模式需要另行安装 zsign 和 OpenSSL。下载需要登录 GitHub，构建产物有保存期限。

## 免费 Apple ID

推荐：选择原始 LocationMocker IPA、点击“检测手机”，再点击“免费 Apple ID：电脑安装 / 续签”。新窗口将要求输入 Apple ID、隐藏输入密码和验证码，并完成设备注册、证书/描述文件申请、签名和安装。无需 SideStore，也无需手动准备 P12。

签名组件使用 [isideload](https://github.com/nab138/isideload) 0.4.4（iLoader 同源的 MIT 开源库）。密码和验证码不保存；签名证书、所选团队和 Anisette 状态保存在 Windows 凭据存储中，便于下次复用。达到证书数量上限时会停止，需用户自己检查现有证书后重试。

```powershell
py windows\installer.py free-renew --udid YOUR_UDID --ipa original.ipa --helper windows\free-sign\target\release\locationmocker-free-sign.exe
# 如默认 Anisette 服务不可达，可指定支持 v3 的 HTTPS 服务：
py windows\installer.py free-renew --udid YOUR_UDID --ipa original.ipa --helper C:\Tools\locationmocker-free-sign.exe --anisette https://YOUR_SERVER
```

源码运行先执行 `cargo build --release --manifest-path windows/free-sign/Cargo.toml`；下载的 EXE 包已内置此组件。登录密码/验证码不通过命令参数传递。Anisette 由第三方服务提供，使用前请确认服务来源；Apple 登录通过签名库完成，兼容性会受 Apple 接口变化影响。

每次续签都选择同一个原始 IPA、相同 Apple ID 和团队。签名库会为应用标识附加团队 ID，因此首次从 Xcode 或其他签名工具迁移时可能会安装成另一个 App，原有收藏不会自动迁移。后续使用本工具保持同一标识才可覆盖更新。它仍受免费账号约七天有效期限制，需要到期前在电脑上重签，当前没有无人值守的定时登录。

备用流程（iLoader）：

1. 下载由 Mac/Xcode 构建的 LocationMocker IPA。
2. 点击“检测手机”，选择 IPA。
3. 点击“生成 iLoader 专用 IPA”，选择一个新的输出位置。
4. 在 [iLoader](https://github.com/nab138/iloader) 中导入输出 IPA，使用自己的 Apple ID 签名安装。
5. 续签时在 iLoader 中用相同账户、团队和应用标识重新签名安装。

输出 IPA 含此设备的配对私钥，仅供本机自用，不能分享或上传。备用流程的输出必须经过 iLoader 签名才能安装；内置免费账号流程会自动重签临时 IPA 并清理它。

## 已有开发证书

准备有效的 P12 和包含当前 UDID 的新 `.mobileprovision` 文件。安装 [zsign](https://github.com/zhlynn/zsign)（Windows 构建见其官方说明）和 OpenSSL 后，在界面选择这两个工具路径、IPA、证书和描述文件，点击“签名并安装 / 续签”。P12 密码只用于本次操作，不保存、不传入子进程参数。

```powershell
py windows\installer.py devices
py windows\installer.py prepare --udid YOUR_UDID --ipa LocationMocker.ipa --output personal.ipa
py windows\installer.py install --udid YOUR_UDID --ipa LocationMocker.ipa --p12 development.p12 --profile fresh.mobileprovision --zsign C:\Tools\zsign.exe --openssl C:\Tools\openssl.exe
py windows\installer.py renew --udid YOUR_UDID --ipa LocationMocker.ipa --p12 development.p12 --profile fresh.mobileprovision
py windows\installer.py status --udid YOUR_UDID --ipa signed.ipa
```

`install` 与 `renew` 都生成当前设备配对记录、校验描述文件、重签并覆盖安装，不执行卸载。使用相同 bundle identifier 和团队才能保留原应用数据；工具不提供跨团队的数据迁移。`status` 检查指定 IPA 的有效期，而非读取手机内 App 的实时到期日。普通命令的结果以 JSON 写入 stdout；`free-renew` 还会显示签名组件的交互提示，不能把整个输出当作纯 JSON 解析。

## 当前限制与验证

- 只支持本项目无 App Extension 的 IPA，保留 OpenSSL.framework。
- 描述文件校验 CMS 完整性、到期日、UDID、应用标识和证书匹配；最终 Apple 信任、签名和 entitlements 判定由手机安装服务执行。
- P12 模式更新证书需用户提供新材料；免费账号模式在交互登录后向 Apple 申请描述文件及必要的证书。
- Windows USB/RP pairing/DDI 与各 iOS 版本的兼容性需真机验证。App 注入仍需要 LocalDevVPN 和准备好的开发者服务，安装成功不代表注入成功。
- 当前不提供后台自动续签、自动启动 App 或完整 .NET GUI。桌面界面为 Tkinter，免费账号签名使用独立交互窗口。
- 私钥只在任务临时目录存在，任务结束清理；强制终止进程时可能留下临时目录，应在本机清理。配对库本身也可能在用户目录保存设备信任记录。

测试：`py -m unittest discover -s windows -p 'test_*.py' -v`。覆盖 IPA 路径攻击、设备/证书/profile 不匹配、失效、Framework 保留和错误脱敏；不能替代 Windows iPhone 真机验收。

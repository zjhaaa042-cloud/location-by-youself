# Windows 安装与证书续签方案

## 目标

让 Windows 用户可以通过 USB 或同一 Wi‑Fi 完成以下操作：

1. 安装已签名的 LocationMocker IPA。
2. 在证书到期前重新签名并更新应用。
3. 保留应用数据和现有配置。
4. 为每台 iPhone 生成并写入设备专属的 RemotePairing 文件。
5. 在不暴露 Apple 登录凭据、证书私钥和配对私钥的前提下显示结果和错误原因。

本方案只面向用户自有设备、开发测试和个人签名场景，不绕过 Apple 的签名或设备注册限制。

## 现状与边界

当前 iOS App 依赖三类设备相关材料：

- IPA 内的签名、嵌入式 provisioning profile 和 entitlements；
- 每台手机的 lockdown pairing record；
- 每台手机生成的 RemotePairing Ed25519 记录（`rp_pairing_file.plist`）。

其中后两项包含私钥，不能进入 Git、日志、云端构建产物或诊断压缩包。Windows 端不能运行 Xcode，因此不把 Xcode 当作运行时依赖；构建签名与手机安装分成两个职责。

## 推荐架构

```text
Windows 控制台 / GUI
  ├─ DeviceAdapter        发现设备、信任状态、USB/Wi‑Fi 连接
  ├─ PairingManager       导出 lockdown，生成设备专属 RP 记录
  ├─ SigningProvider      Apple ID / Developer Team 的签名与 profile
  ├─ IPAInstaller         安装、覆盖更新、启动和验证 App
  ├─ RenewalScheduler     到期前提醒与手动/自动续签
  └─ SecretStore          Windows Credential Manager + DPAPI

可选构建服务
  └─ macOS/GitHub Actions 生成签名 IPA（不返回私钥）

iPhone
  └─ LocationMocker + LocalDevVPN + 设备专属 RP pairing 文件
```

### 第一阶段：可交付的 Windows CLI

先做无 GUI 的 `locationmocker-win`，降低实现风险并方便自动化测试：

```text
device list
device pair --udid <UDID>
app install --ipa <path> --udid <UDID>
app renew --udid <UDID>
app status --udid <UDID>
```

建议使用 Python 3.12 + `pymobiledevice3` 处理设备配对和文件传输；IPA 解包、重签和压缩使用 Python 标准库与 Windows SDK 工具。所有命令都必须支持 `--json`，方便后续 GUI 调用。

### 第二阶段：Windows GUI

使用 WinUI 3 或 .NET 8 WPF 包装同一套核心库，提供：

- 设备卡片：名称、iOS 版本、USB/Wi‑Fi、信任/开发者模式状态；
- 签名状态：团队、Profile 到期日、剩余天数；
- “安装 / 更新 / 重新配对 / 查看诊断”按钮；
- 分阶段进度：连接 → 配对 → 签名 → 安装 → 启动验证；
- 可复制但已脱敏的错误信息。

## 安装与续签流程

### 新设备安装

1. 用户解锁手机、开启开发者模式并信任 Windows 电脑。
2. `DeviceAdapter` 读取真实 UDID，禁止把 CoreDevice 展示 ID 当作 UDID。
3. `PairingManager` 导出 lockdown record 到 Windows 临时目录。
4. 生成设备专属 `rp_pairing_file.plist`，仅写入内存或受保护临时文件。
5. `SigningProvider` 获取或生成该设备可用的 provisioning profile。
6. 重签 IPA，并把 RP 文件注入 Debug/个人签名资源位置。
7. 通过设备安装服务覆盖安装。
8. 启动 App，检查 bundle id、版本和配对文件 identifier 是否匹配当前设备。
9. 清理临时 IPA、profile、pairing record 和日志中的敏感字段。

### 到期前更新

1. 从已安装 App 或本地状态读取过期时间。
2. 默认在剩余 2 天和 1 天提醒；不在后台静默登录 Apple ID。
3. 用户点击“更新”后重新执行签名与安装流程。
4. 保留 App 容器数据；若 bundle id 或 App ID 变化，必须明确提示用户可能无法保留数据。
5. 安装后再次做启动验证，并记录非敏感的结果。

## 签名策略

支持两种模式，但不混用：

### 个人 Apple ID

- 适合自用和少量测试设备；
- 有效期通常较短，需要频繁刷新；
- Apple 登录凭据交给官方登录流程或现有成熟工具，不在项目中保存明文密码；
- 不承诺绕过设备数量、有效期或 Apple 的验证策略。

### Apple Developer Program

- 适合长期测试和团队设备；
- 使用开发或 Ad Hoc profile；
- 设备必须在团队中注册，profile 和证书到期后仍需更新；
- 私钥只保存在 Windows Credential Manager/DPAPI 或 CI 的加密密钥库中，不写入仓库。

## 安全要求

- `.mobiledevicepairing`、`rp_pairing_file.plist`、`.p12`、私钥、Apple session token 必须加入忽略规则并禁止上传。
- 日志只显示 UDID 前后各 4 位、证书指纹前 8 位和错误类型。
- 所有临时敏感文件使用随机目录，任务结束立即删除。
- 提供 `--diagnostic` 时也必须脱敏，默认不收集 Apple ID、设备配对数据或 IPA 内容。
- 不实现企业证书滥用、批量分发、盗用账号或绕过 Apple 验证的功能。

## 错误处理

统一错误码，避免直接把底层堆栈展示给用户：

| 错误码 | 含义 | 用户动作 |
|---|---|---|
| `DEVICE_NOT_FOUND` | USB/Wi‑Fi 未发现设备 | 解锁手机并重连数据线 |
| `PAIRING_REQUIRED` | 尚未信任电脑 | 在手机上确认“信任” |
| `DEVELOPER_MODE_REQUIRED` | 开发者模式关闭 | 开启开发者模式并重启 |
| `PROFILE_EXPIRED` | profile 已过期 | 重新签名并安装 |
| `DEVICE_NOT_REGISTERED` | 设备不在团队 profile 中 | 注册 UDID 后重新生成 profile |
| `PAIRING_ID_MISMATCH` | RP 文件属于另一台手机 | 删除旧临时记录并重新配对 |
| `INSTALL_FAILED` | 安装服务拒绝 | 检查签名、bundle id 和磁盘空间 |
| `VPN_REQUIRED` | LocalDevVPN 未连接 | 连接 LocalDevVPN 后重试注入 |

## 实施拆分

1. `windows/core`：设备抽象、敏感数据模型、统一错误码和 JSON 输出。
2. `windows/pairing`：设备发现、lockdown 导出、RP pairing 生成和匹配校验。
3. `windows/signing`：profile/证书导入、IPA 重签、签名验证。
4. `windows/install`：安装、启动、版本检查和容器数据保护。
5. `windows/cli`：命令行入口和退出码。
6. `windows/gui`：在 CLI 稳定后再实现。
7. CI：静态检查、无设备单元测试、IPA 结构测试；真机测试只在受保护 runner 上执行。

## 验收标准

- 在干净 Windows 11 环境安装依赖后，能列出已信任 iPhone。
- 首次安装能生成与当前 UDID 匹配的 RP 文件并成功启动 App。
- 重新安装不会删除 App 数据。
- 续签成功后能显示新的到期时间，失败时给出上表中的可行动错误码。
- 仓库扫描不到 pairing 私钥、P12、Apple token 和用户 IPA。
- 无设备时所有命令都能在 3 秒内返回明确错误，不崩溃、不卡死。

## 本 PR 的范围

本 PR 先提交方案和安全边界，不提交签名私钥、不提交设备配对文件，也不伪装成已经完成 Windows 真机安装。后续 PR 按上述实施拆分逐步交付 CLI、签名适配器和 GUI。

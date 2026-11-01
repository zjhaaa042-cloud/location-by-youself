# iOS 免费签名：从 macOS 迁移到 Windows 11

## 目标

把原本依赖 Mac（Xcode / 免费个人团队）的 iOS 签名与续签流程，整体迁移到 Windows 11，做到：

1. 只需 Windows 11 + 一根 USB 数据线，不依赖任何 Mac；
2. 用自己的免费 Apple ID 完成签名与安装；
3. 7 天到期后可以低成本续签，不丢 App 数据；
4. 凭据、配对私钥、IPA 全程不进仓库、不进日志。

本文只覆盖**签名与安装**。定位功能是否可用属于另一条链路（LocalDevVPN 隧道 + App 内轨迹），必须单独验收。

## 迁移前与迁移后

| 环节 | 迁移前（macOS） | 迁移后（Windows 11） |
|---|---|---|
| 构建 | Xcode 本地编译 | GitHub Actions 的 macOS runner 出未签名 IPA |
| 签名 | Xcode 免费个人团队 | iLoader 2.4.x + 免费 Apple ID |
| anisette | 真实 Mac 硬件，Apple 自家生成 | 远程 Mac 类型 anisette 服务（当前为 `StikStore`） |
| 安装 | Xcode / Finder | iLoader 通过 USB 安装 |
| 续签 | Xcode 重新运行 | 运维脚本 / iLoader 重新导入 IPA |

## 三条实测结论（迁移中最费时间的部分）

以下结论均在本机复现，不是推测。

### 1. 登录名必须用 `+86` 手机号，不能用邮箱

用绑定邮箱作为 Apple ID 登录时，Sideloadly 与 iLoader 都会在**密码校验阶段**返回：

```
-22406 Enter the correct password for this Apple Account
```

而同一账号、同一密码在 apple.com 网页端可以正常登录（并完成 2FA）。把登录名改成 `+86` 开头的手机号后**一次通过**，并可正常收到 6 位验证码。两个不同账号都复现了该现象。

### 2. 2026-10-21 起 Apple 只接受 Mac 类型 anisette

Sideloadly 在签发 App Token 阶段会明确报出：

```
-80046 This action cannot be completed at this time.
Since 2026-10-21 Apple rejects this anisette type (non-Mac) when issuing app tokens,
which affects all sideloading tools. Try a different anisette type.
Remote Anisette (available to our Patreon supporters) is not affected.
```

含义与处置：

- 非 Mac 类型 anisette（本地生成、多数第三方服务）会在**签发阶段**被拒，与密码是否正确无关；
- Sideloadly 的 `Remote Anisette`（Mac 类型）是 Patreon 付费功能；
- 免费可用组合：**iLoader + `StikStore`**（`ani3.stikstore.app`），本机已实测完成签名与安装；
- 同一套 iLoader 里 `SideStore (.io)` 会报 `-22421`（proof login 阶段），换服务后需点 `Reset Anisette State` 并重新过 2FA。

### 3. 手机热点会让 2FA 之后的请求超时

对 `gsa.apple.com:443` 连续做 6 次 TCP 连接：4 次成功、2 次超时（各 6 秒）。表现为验证码提交后报：

```
HTTPSConnectionPool(host='gsa.apple.com', port=443): Max retries exceeded
url: /grandslam/GsService2/validate ... [WinError 10060]
```

签名/安装本身走 USB，与电脑联网方式无关，因此换到稳定宽带即可，不必换手机。

## 首次安装步骤

1. iPhone：开启 **开发者模式**（设置 → 隐私与安全性），USB 连接并信任本机。
2. Windows：安装 [iLoader](https://github.com/nab138/iloader)。它需要能枚举 USB 设备；若同时装了 Microsoft Store 版「Apple 设备」，请确认设备在 iLoader 的 DEVICES 列表里可见。
3. 取得未签名 IPA（本仓库 `.github/workflows/ios-unsigned.yml` 可在 GitHub Actions 的 macOS runner 上构建）。
4. iLoader → SETTINGS → Anisette Server 选 **StikStore** → 点 `Reset Anisette State`。
5. ACCOUNT 里填 **`+86` 手机号** + 密码 + 6 位验证码登录。
6. DEVICES 里点击设备卡（必须显示 `Selected`）→ `Import IPA` → 选择 IPA。
7. 等待弹窗出现 `Operation completed`。
8. 手机上：设置 → 通用 → VPN 与设备管理 → 信任 `Apple Development: <你的手机号>`。

完成后设备侧应显示 `ProfileValidated = True`、`get-task-allow = True`。

## 每 7 天续签

免费个人团队的描述文件 7 天到期，到期后 App 无法启动（不是数据丢失）。

**自动方式**（本仓库 `windows/signing-ops/`）：

```powershell
Copy-Item windows\signing-ops\config.example.json windows\signing-ops\config.json
# 填 workRoot / ipaPath / bundleId / appleId / teamId / signedOn
powershell -File windows\signing-ops\renew.ps1 -DryRun   # 预检
powershell -File windows\signing-ops\renew.ps1           # 续签
```

脚本只驱动 iLoader 界面，不读取也不保存密码；会话过期时会以退出码 7 停下，要求人工登录后重跑。成功后自动更新 `config.json` 的 `signedOn`，7 天重新计时。

**人工方式**：iLoader 中选中设备 → `Import IPA` → 选择同一个 IPA → 等 `Operation completed`。

**到期提醒**：`windows/signing-ops/install-schedule.ps1` 注册每日体检任务，剩余 ≤ 2 天时弹通知。严重程度只看签名年龄——手机没插线是正常状态，不是故障。

## 错误码速查

| 错误 | 阶段 | 原因 | 处置 |
|---|---|---|---|
| `-22406` | 密码校验 | 登录名用了邮箱别名 | 改用 `+86` 手机号 |
| `-22421` | proof login | 该 anisette 服务不可用 | 换服务（`StikStore` → `iloader` → `Jkcoxson`），并 `Reset Anisette State` |
| `-80046` | 签发 App Token | 非 Mac 类型 anisette | 不要用本地/非 Mac 服务；用 iLoader + `StikStore` |
| `WinError 10060` | 2FA 后 validate | 网络丢包 | 换稳定宽带 |
| `file dialog did not appear` | 界面自动化 | 设备掉线或设备卡未选中 | 重插 USB、确认 `Selected` |
| 图标闪退 / 不受信任 | 启动 | 证书信任被撤或已过期 | 重新信任证书；过期则先续签 |

## 安全边界

- Apple ID 密码、验证码只在本机交互窗口输入，脚本从不读取、不记录；
- `rp_pairing_file.plist`、IPA、iLoader 的 `data.json`、本地 `config.json` 含私钥或账号会话，**不得进入 Git、Issue、日志或构建产物**；
- 本方案不绕过 Apple 的签名、设备注册或系统安全机制，只自动化合法的 7 天续签循环。

## 已知限制

1. **7 天有效期**：免费账号硬限制，只能周期续签。
2. **配额**：同一免费账号设备上最多 3 个自签名 App，7 天内最多创建 10 个 App ID。
3. **bundle ID 会被加团队后缀**：原 bundle ID 属于其他团队时，iLoader 会签成 `com.example.app.<TEAM>`，于是成为**独立 App**，旧 App 的数据与设置不会迁移。
4. **VPN 隧道是独立 App**：本项目的 `LocalDevVPN` 为 App Store 签名版本，不会过期，也不占用上述 3 个名额。
5. **第三方 anisette 服务可能失效**：届时在 iLoader 里换服务；即使全部失效，付费开发者账号（每年 99 美元）可用本地离线签名，完全绕开 anisette。

## 验收清单

签名成功不等于功能可用，按顺序验收：

- [ ] 设备侧 `ProfileValidated = True`、`get-task-allow = True`
- [ ] App 能启动，不就地闪退
- [ ] 开发者证书已在手机上信任
- [ ] LocalDevVPN 隧道能建立
- [ ] App 内选择轨迹后，系统定位确实被改变
- [ ] 到期日已记录，提醒任务已注册

# LocationMocker for iOS

LocationMocker 是一个实验性的 iOS 真机系统级定位模拟工具，支持固定点、路线回放和跑道跑步三种模式，不依赖越狱。定位通过 iOS 17+ 的 RemotePairing / CoreDevice / DTX LocationSimulation 链路注入，对所有使用 CoreLocation 的 App 生效。

> 仅用于自有设备的开发、测试和研究。请遵守当地法律、平台规则和第三方服务条款。

## 目录

- [工作原理](#工作原理)
- [功能特性](#功能特性)
- [前提准备](#前提准备)
- [下载与安装](#下载与安装)
- [日常使用](#日常使用)
- [注意事项](#注意事项)
- [常见问题排查](#常见问题排查)
- [已知限制](#已知限制)
- [运行测试](#运行测试)
- [项目结构](#项目结构)
- [安全说明](#安全说明)

---

## 工作原理

### 注入链路

iOS 17 之后，苹果把开发者磁盘镜像（DDI）中的调试服务迁到了 RemotePairing / CoreDevice 体系。LocationMocker 在手机上自建一条到本机 `remoted` 服务的加密通道，直接调用其中的 `DTX LocationSimulation` 服务来改写系统级定位：

```text
LocationMocker
  └─ LocalDevVPN 回环 → 10.7.0.1:49152
      └─ RPPairing pair-verify
          └─ TLS 1.2 PSK + CDTunnel
              └─ 用户态 IPv6/TCP → RemoteXPC/RSD
                  └─ DTX LocationSimulation → 系统定位
```

各环节说明：

- **LocalDevVPN**：提供手机本地回环隧道（loopback），让 App 能以网络接口访问本机的 RemotePairing 端口。它只做回环，不把流量转发到外部服务器。使用它是因为免费 Personal Team 没有 Network Extension 签名权限，无法自建隧道。
- **RPPairing pair-verify**：用首次配对时生成的设备专属 Ed25519 密钥完成双向验证（SRP 握手），证明"这台 Mac 是被这台手机信任的"。
- **TLS 1.2 PSK + CDTunnel**：验证通过后建立加密隧道，App 在用户态实现 IPv6/TCP 协议栈与对端通信。
- **RemoteXPC / RSD**：隧道之上跑苹果的远程 XPC 协议，连接到 Remote Service Discovery 暴露的调试服务。
- **DTX LocationSimulation**：最终调用 `startLocationSimulation` / `stopLocationSimulation`，将坐标写入系统定位框架。停止时发送显式清除指令，并保持隧道 3 秒确保指令送达。

### 坐标系处理

中国大陆地图使用 GCJ-02 坐标，系统定位框架需要 WGS-84。本项目的策略是：

- UI 层（地图点选、路线编辑、跑道预览）全程保持 MapKit 坐标系，不做转换。
- 只有坐标即将送入 DTX 注入时才执行 GCJ-02 → WGS-84 转换。
- 境外坐标不转换，原样注入。

## 功能特性

- 地图点选与地址搜索
- 固定点系统定位
- 多点路线：单次、循环、往返
- 跑道生成：地图中心对准、附近操场候选、方向/周长/起点微调
- 跑道收藏：微调结果一键保存，随时载入复用或导出 GPX 分享
- 一键定位到当前真实位置
- 签名到期提醒：读取内嵌描述文件计算剩余天数，到期前 1 天本地通知 + 到期前 2 天 App 内横幅
- 自然跑步速度与轻微轨迹漂移
- 后台定位与静音音频保活
- 一键停止：发送 `stopLocationSimulation` 后保持隧道 3 秒再断开
- 诊断页与本地日志

### 当前验证状态

- 已在 iPhone 16 Pro（iOS 26.4.2）与 iPhone SE 3（iOS 26.5）、Xcode 26.5 上验证。
- 固定点注入、路线游标、标准跑道回放和显式清除已接入主界面。
- 模拟器单元测试 90+ 项全部通过（协议金样、SRP、TCP 校验和、坐标转换、路线与跑道几何、跑道收藏、签名到期解析）。
- App 内自动挂载 Developer Disk Image 尚未完成，仍依赖 Xcode 挂载过一次。

---

## 前提准备

首次安装前需要备齐以下全部内容。之后的日常重签/重装只需要其中一小部分。

### 1. Mac 端环境

- macOS 与 Xcode 26（建议使用项目验证过的 Xcode 26.5）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（由 `project.yml` 生成 Xcode 工程）
- `pymobiledevice3` 9.x（导出配对记录、建立 RemotePairing 用）

```bash
brew install xcodegen pipx
pipx install pymobiledevice3
```

注意：`pipx install` 只对命令行生效；配对脚本内部用 `python3` 运行，需要当前 `python3` 能 import 该包（例如 `pip3 install pymobiledevice3`，或在对应虚拟环境中运行）。

### 2. iPhone 端条件

- iOS 17 或更高版本的真机（模拟器不能执行真机注入）
- 已开启「开发者模式」：设置 → 隐私与安全性 → 开发者模式，开启后按提示重启并再次确认
- 已信任当前 Mac：数据线连接后，手机上点「信任此电脑」
- **Wi-Fi 必须开启并连接到可用网络**（RemotePairing 链路走 Wi-Fi 接口，仅插 USB 或用蜂窝网络无法建立）

### 3. 安装 LocalDevVPN

LocalDevVPN 目前在中国大陆 App Store 不可用，下载前需要准备一个可访问该应用的境外 Apple 账号（例如美区账号）。请只使用自己注册和管理的账号，不要使用购买或共享账号。创建或切换账号时，可参考 [kjfx/AppleID 的美区 Apple 账号教程](https://github.com/kjfx/AppleID.git)。账号地区和应用上架情况可能会变化，以 App Store 实际显示为准。

**下载步骤：**

1. 在 iPhone 打开「设置」→ Apple 账户 →「媒体与购买项目」。**只退出「媒体与购买项目」**，不要退出 iCloud 或移除设备上的主 Apple 账户。
2. 使用准备好的境外 Apple 账号登录「媒体与购买项目」。
3. 打开 [LocalDevVPN 的 App Store 页面](https://apps.apple.com/us/app/localdevvpn/id6755608044)，或在 App Store 搜索 `LocalDevVPN`，下载并安装。
4. 下载完成后，可以在「媒体与购买项目」中切回日常使用的账号；已安装的 LocalDevVPN 不会因此被删除。后续如需更新该 App，可能仍需切回下载它的账号。

**首次连接：**

1. 确认手机 Wi-Fi 已开启并连接。
2. 打开 LocalDevVPN，点击连接；iOS 弹出「添加 VPN 配置」或 VPN 权限提示时选择「允许」，并按提示验证设备密码。
3. 等待 LocalDevVPN 显示「已连接」，同时在 iPhone「设置」中确认 VPN 状态已连接。

### 4. 首次配对（每台手机只做一次）

RemotePairing 使用设备专属 Ed25519 私钥。仓库不会、也绝不能包含可直接使用的配对文件。

1. 用支持**数据传输**的 USB 数据线连接 iPhone 与 Mac（避免只充电线、无供电扩展坞），手机保持解锁。
2. 打开 Xcode →「Window」→「Devices and Simulators」，确认设备可用（无「未信任」「Developer Mode disabled」等提示）。首次连接 Xcode 会自动准备开发者支持文件（DDI），等待完成。
3. 查询 UDID：

   ```bash
   xcrun devicectl list devices
   ```

4. 导出当前 Mac 与手机的 lockdown 记录：

   ```bash
   pymobiledevice3 lockdown save-pair-record pairing_record.mobiledevicepairing --udid YOUR_UDID
   ```

5. 生成 App 使用的 RemotePairing 记录：

   ```bash
   python3 tools/bootstrap_rp_pairing.py \
     --udid YOUR_UDID \
     --lockdown-record pairing_record.mobiledevicepairing
   ```

脚本默认写入 `LocationMocker/LocationMocker/Resources/Debug/rp_pairing_file.plist`。该文件和 lockdown 记录都含私钥，已由 `.gitignore` 排除，**不要上传、分享或复制到其他设备**。

> 也可以直接运行 `tools/setup.sh`，一键完成「查询 UDID → 导出 lockdown 记录 → 生成 RemotePairing 文件 → xcodegen 生成工程 → 打开 Xcode」。多台设备同时连接时脚本会列出候选，也可用 `tools/setup.sh --udid YOUR_UDID` 直接指定。

---

## 下载与安装

提供两条路径。**路径 A** 最简单，适合日常开发调试，但每 7 天要手动重装一次；**路径 B** 一次配置后手机自动续签，彻底摆脱 7 天限制，推荐日常使用。

### 路径 A：Xcode 直接构建安装

配对文件生成后再生成 Xcode 工程，这样 XcodeGen 才会把本地记录加入开发构建：

```bash
cd LocationMocker
xcodegen generate
open LocationMocker.xcodeproj
```

工程打开后按以下步骤签名并安装：

1. 在左侧项目导航中选择 `LocationMocker` 项目，再选择 `LocationMocker` target。
2. 打开「Signing & Capabilities」，勾选「Automatically manage signing」。
3. 在「Team」中选择自己的 Apple 开发团队；使用免费 Apple 账号时选择 `Personal Team` 即可。
4. 将「Bundle Identifier」改为全局唯一的值，例如 `com.yourname.LocationMocker`。若出现红色签名错误，先确认已登录 Xcode：「Xcode」→「Settings」→「Accounts」。
5. 在顶部 Scheme 旁的设备列表中选择刚连接的 iPhone，**不要选择模拟器**。
6. 点击左上角运行按钮（▶︎）。Xcode 会编译、签名并安装 App；首次安装需要等待依赖下载和设备准备完成。
7. 安装完成后，iPhone 会自动打开 LocationMocker。若手机提示不信任开发者，前往「设置」→「通用」→「VPN 与设备管理」，选择对应的开发者 App 并点击「信任」。

项目通过 Swift Package Manager 获取 `OpenSSL-Package` 3.6.2000，不需要提交本地二进制 vendor 目录。

**到期后重装（无需重新配对、无需重新生成工程）**，任选一种方式：

- **Xcode（推荐）**：接线并解锁 iPhone，打开 `LocationMocker.xcodeproj`，选中设备后点运行（▶︎）。
- **命令行**：与 Xcode 安装效果相同，适合不打开 Xcode 的场景：

  ```bash
  cd LocationMocker
  xcodebuild -project LocationMocker.xcodeproj -scheme LocationMocker \
    -configuration Debug -destination 'id=YOUR_UDID' \
    -allowProvisioningUpdates DEVELOPMENT_TEAM=YOUR_TEAM_ID build
  xcrun devicectl device install app --device YOUR_UDID \
    ~/Library/Developer/Xcode/DerivedData/LocationMocker-*/Build/Products/Debug-iphoneos/LocationMocker.app
  ```

  `YOUR_UDID` 用 `xcrun devicectl list devices` 查询；`YOUR_TEAM_ID` 在 Xcode「Signing & Capabilities」里选择 Team 后可从构建日志中查到。

### 路径 B：SideStore 自动续签（推荐）

免费账号的 7 天限制可以靠 [SideStore](https://sidestore.io) 解决：它把重签流程搬到手机上，到期前自动续期，日常使用完全无感。前提条件只有一个：手机定期连接 Wi-Fi（续签时 LocalDevVPN 需保持连接）。

**第 1 步：用 iLoader 安装 SideStore（iOS 26 推荐路径）**

[iLoader](https://iloader.site) 是 SideStore 官方的新一代安装器，自动处理证书与配对文件，比 AltServer 省心得多：

1. 下载 iLoader macOS 版并打开（首次打开如被 Gatekeeper 拦截，右键 → 打开）。
2. **关闭 Mac 上的系统代理 / 代理客户端**。代理拦截 `gsa.apple.com` 认证会导致登录报 "The data is not in the correct format"。
3. iLoader → Settings → **Anisette 服务器**：默认的 `ani.sidestore.io` 在中国大陆不可达，改用 `ani.stikstore.app`（实测可直连），否则登录超时（"deadline has elapsed"）。
4. 登录 Apple ID（iLoader 凭据只发往苹果服务器，开源可审计）。
5. USB 连接并解锁 iPhone，选择设备 → **「SideStore（稳定版）」**，等待签名、安装、配对文件注入自动完成。

**第 2 步：手机端初始化**

1. 设置 → 通用 → VPN与设备管理 → 信任新开发者证书。
2. 手机连 Wi-Fi，打开 LocalDevVPN 保持连接（SideStore 续签走回环隧道）。
3. 打开 SideStore → 登录 Apple ID → **Refresh Now**，全程不锁屏不切出；成功后 App 会自动退出，属正常。
4. SideStore → My Apps → + → 导入 LocationMocker 的 IPA（见下）→ 弹窗选 **「Keep App Extensions (Use Main Profile)」**（包内是必需的 OpenSSL 框架，不能移除；该选项不额外占用 App ID 配额）。

**生成 LocationMocker.ipa**（交给 SideStore 托管用）：

```bash
rm -rf /tmp/ipabuild && mkdir -p /tmp/ipabuild/Payload
cp -R ~/Library/Developer/Xcode/DerivedData/LocationMocker-*/Build/Products/Debug-iphoneos/LocationMocker.app /tmp/ipabuild/Payload/
(cd /tmp/ipabuild && zip -qr LocationMocker.ipa Payload)
```

IPA 内含本机的 RemotePairing 私钥，只传给自己手机，不要分享。

**之后的使用**：SideStore 会在后台自动续签它自己和其他托管 App。My Apps 里每个 App 旁显示剩余天数，某天看到天数又变回 7 天就是续签成功了。若意外过期：连 Wi-Fi + 开 LocalDevVPN → SideStore → My Apps → 点刷新即可。

> SideStore 托管版的 Bundle ID 会带 Team ID 后缀（如 `com.zhangjiahui.locationmocker.G89NT3CMMF`），与 devicectl 直装版是两个独立 App。配置了 SideStore 后，旧的直装版可以删除。

---

## 日常使用

1. 手机连接 Wi-Fi，打开 LocalDevVPN 并确认「已连接」。
2. 打开 LocationMocker，选择位置后点「固定点」「路线模拟」或「跑道」。
3. 顶部出现「系统注入」后，可在系统地图或其他使用 CoreLocation 的 App 中验证。
4. 结束时**务必回到 LocationMocker 点「停止」**，等待「清除中」消失，再按需断开 LocalDevVPN。

如果提示「无 LocalDevVPN」「系统定位注入失败」或错误 61 / `Connection refused`，请优先检查手机 Wi-Fi 是否已开启并连接，然后重连 LocalDevVPN 再试。

---

## 注意事项

> [!WARNING]
> **免费 Personal Team 签名 7 天后到期。** 到期后 App 无法打开（点图标闪退或提示「不再可用」），这不是 Bug。只要手机上还能看到图标，用 Xcode 重新点一次运行（▶︎）重装即可恢复，配对文件和 App 数据不受影响。**想彻底摆脱手动重签，请按上文「路径 B：SideStore 自动续签」配置**，之后由手机自动续期。

- **配对文件即私钥**：`pairing_record.mobiledevicepairing`、`rp_pairing_file.plist` 和打包出的 IPA 都含有设备私钥，绝不能上传到 Git、网盘或发给他人。泄露意味着对方可以伪装成你信任的电脑访问手机调试服务。
- **模拟定位可能「粘住」**：异常断线后系统定位可能停留在模拟位置。务必使用 App 的「停止」显式清除，必要时重启手机。
- **风控提醒**：部分应用（打卡、外卖、社交等）会结合基站、运动传感器、网络或账户风控交叉验证，单独修改 CoreLocation 不保证有效，且可能违反平台条款。请评估风险后使用。
- **续签依赖 Wi-Fi + LocalDevVPN**：SideStore 自动续签走的是同一条回环隧道，手机长期不连 Wi-Fi 会导致续签失败直至过期。

## 常见问题排查

**安装 / 签名类**

- Xcode 中没有 iPhone：确认数据线支持数据、手机已解锁并已点「信任」，然后关闭并重新打开「Devices and Simulators」。
- 提示 Developer Mode 未开启：按「前提准备」的步骤开启开发者模式并完成重启确认。
- 提示 Provisioning Profile、Signing 或 Bundle Identifier 错误：选择正确的 Team，并换成未被占用的 Bundle Identifier。
- 安装后立即退出或无法启动：在 iPhone「VPN 与设备管理」中信任开发者证书；若 7 天前安装过，就是签名到期，按「路径 A」重装。
- 显示正在准备设备或无法挂载 Developer Disk Image：保持数据线连接、手机解锁、网络可用，等待 Xcode 完成后重试。

**SideStore / iLoader 类**

- AltServer/iLoader 登录报 "data is not in the correct format"：Mac 系统代理拦截了 `gsa.apple.com`，关闭代理客户端后重试。
- iLoader 登录超时 "deadline has elapsed"：默认 anisette 服务器被墙，按上文换 `ani.stikstore.app`。
- SideStore 刷新报 "could not determine this device's UDID" / "AFC was unable to manage files"：iOS 26 与老工具（jitterbugpair/pymobiledevice3）生成的配对文件不兼容，**用 iLoader 重装即可**（它会生成新格式配对文件）；同时保持手机解锁、LocalDevVPN 已连接。
- 安装报 7460（已有生效证书）：在 SideStore Settings 里 Revoke All Certificates 后重试。
- 安装报 7252（证书序列号不存在）：钥匙串残留已被注销的旧 Xcode 证书，执行 `security delete-certificate -c "Apple Development: <账号> (<TEAMID>)"` 删除后重试。

**注入 / 运行类**

- 「无 LocalDevVPN」或「系统定位注入失败」、错误 61 / `Connection refused`：检查 Wi-Fi 已开启并连接 → 重连 LocalDevVPN → 重试。
- 手机重启、DDI 状态变化或 LocalDevVPN 断开后：需要重新建立会话（重开 LocalDevVPN 并在 App 内重新开始模拟）。
- 定位卡在模拟位置不恢复：App 内点「停止」；无效则重启手机。

## 已知限制

- 纯手机端注入依赖 Wi-Fi 网络接口；关闭 Wi-Fi 时即使 LocalDevVPN 显示已连接，也可能无法完成系统定位注入。
- App 内 DDI 自动挂载与断线自动重连尚未完成。
- 免费开发者签名 7 天到期，到期后需重装（或配置 SideStore 自动续签）。
- `LocationMockerTunnel` 是付费开发者账号可用的自建 Network Extension 实验目标，默认未嵌入主 App。

---

## 运行测试

```bash
cd LocationMocker
xcodebuild \
  -project LocationMocker.xcodeproj \
  -scheme LocationMocker \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test CODE_SIGNING_ALLOWED=NO
```

模拟器不能执行 RemotePairing 真机注入，但可验证协议金样、SRP、TCP 校验和、坐标转换、路线和跑道几何。

## 项目结构

```text
LocationMocker/
├── LocationMocker/             # App 源码
├── LocationMockerTests/        # 单元测试与协议金样
├── LocationMockerTunnel/       # 可选 Network Extension
└── project.yml                 # XcodeGen 工程定义
tools/
└── bootstrap_rp_pairing.py     # 一次性 RemotePairing 引导
```

## 安全说明

请在提交前运行：

```bash
git status --short
git grep -nE '<key>private_key</key>|HostPrivateKey|RootPrivateKey|BEGIN .*PRIVATE KEY' -- ':!README.md'
```

任何 `pairing_record.mobiledevicepairing`、`rp_pairing_file.plist` 或设备私钥都不应出现在 Git 历史中。

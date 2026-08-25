# LocationMocker for iOS

LocationMocker 是一个实验性的 iOS 真机系统级定位模拟工具。它支持固定点、路线回放和跑道跑步三种模式，不依赖越狱；定位通过 iOS 17+ 的 RemotePairing / CoreDevice / DTX LocationSimulation 链路注入。

> 仅用于自有设备的开发、测试和研究。请遵守当地法律、平台规则和第三方服务条款。

## 当前状态

- 已在 iPhone 16 Pro、iOS 26.4.2、Xcode 26.5 上验证。
- 固定点注入、路线游标、标准跑道回放和显式清除已接入主界面。
- 中国大陆地图坐标在注入边界自动执行 GCJ-02 → WGS-84 转换。
- 模拟器单元测试：86 项通过。
- 仍依赖 Xcode 已挂载的 Developer Disk Image；App 内自动挂载尚未完成。
- 免费 Personal Team 无法签名 Network Extension，因此当前使用 LocalDevVPN 提供手机回环隧道。

## 功能

- 地图点选与地址搜索
- 固定点系统定位
- 多点路线：单次、循环、往返
- 跑道生成：地图中心对准、附近操场候选、方向/周长/起点微调
- 自然跑步速度与轻微轨迹漂移
- 后台定位与静音音频保活
- 一键停止：发送 `stopLocationSimulation` 后保持隧道 3 秒再断开
- 诊断页与本地日志

## 工作原理

```text
LocationMocker
  └─ LocalDevVPN 回环 → 10.7.0.1:49152
      └─ RPPairing pair-verify
          └─ TLS 1.2 PSK + CDTunnel
              └─ 用户态 IPv6/TCP → RemoteXPC/RSD
                  └─ DTX LocationSimulation → 系统定位
```

路线和跑道的 UI 坐标保持 MapKit 坐标系；只有送入 DTX 前才转换为系统定位所需的 WGS-84。境外坐标保持不变。

## 环境要求

- macOS 与 Xcode 26（建议使用项目验证过的 Xcode 26.5）
- iOS 17+ 真机，已开启“开发者模式”并信任当前 Mac
- iPhone 必须开启 Wi-Fi，并连接到可用 Wi-Fi 网络
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- `pymobiledevice3` 9.x
- 手机安装并连接 LocalDevVPN

```bash
brew install xcodegen pipx
pipx install pymobiledevice3
```

## 安装并使用 LocalDevVPN

LocalDevVPN 目前在中国大陆 App Store 不可用；下载前需要准备一个可访问该应用的境外 Apple 账号（例如美区账号）。请只使用自己注册和管理的账号，不要使用购买或共享账号。创建或切换账号时，可参考 [kjfx/AppleID 的美区 Apple 账号教程](https://github.com/kjfx/AppleID.git)。账号地区和应用上架情况可能会变化，以 App Store 实际显示为准。

### 下载

1. 在 iPhone 打开“设置” → Apple 账户 →“媒体与购买项目”。**只退出“媒体与购买项目”**，不要退出 iCloud 或移除设备上的主 Apple 账户。
2. 使用准备好的境外 Apple 账号登录“媒体与购买项目”。
3. 打开 [LocalDevVPN 的 App Store 页面](https://apps.apple.com/us/app/localdevvpn/id6755608044)，或在 App Store 搜索 `LocalDevVPN`，然后下载并安装。
4. 下载完成后，可以在“媒体与购买项目”中切回日常使用的账号；已安装的 LocalDevVPN 不会因此被删除。后续如需更新该 App，可能仍需要切回下载它的账号。

### 首次连接与日常使用

1. 确认手机已开启 Wi-Fi，并连接到可用的 Wi-Fi 网络。
2. 打开 LocalDevVPN，点击连接；iOS 弹出“添加 VPN 配置”或 VPN 权限提示时选择“允许”，并按提示验证设备密码。
3. 等待 LocalDevVPN 显示“已连接”，同时在 iPhone“设置”中确认 VPN 状态已连接。
4. 保持 LocalDevVPN 在已连接状态，再打开 LocationMocker 执行固定点、路线模拟或跑道模拟。
5. 使用完毕后，先在 LocationMocker 中点击“停止”并等待清除完成，再按需断开 LocalDevVPN。

> LocalDevVPN 在本项目中只负责提供手机本地回环隧道，并非用于将网络流量转发到外部服务器。若连接状态已显示正常但仍无法注入，请先确认 Wi-Fi 没有关闭，再断开并重新连接 LocalDevVPN。

## 连接 iPhone 并安装 LocationMocker

以下步骤需要在首次安装时完成；之后通常只需接线、解锁并在 Xcode 中点击运行即可。

### 1. 准备手机与数据线

1. 使用支持**数据传输**的 USB 数据线将 iPhone 直接连接到 Mac；避免使用只充电线、无供电扩展坞或连接不稳定的转接器。
2. 解锁 iPhone，并在出现“要信任此电脑吗？”时点击“信任”，然后输入设备密码。
3. 在 iPhone 打开“设置” →“隐私与安全性” →“开发者模式”，开启“开发者模式”。系统会要求重启；重启后再次确认开启，并重新解锁手机。
4. 保持手机解锁并停留在主屏幕。若 Xcode 未识别设备，重新插拔数据线，并检查 Finder 的“位置”列表中是否能看到该 iPhone。

### 2. 在 Xcode 确认设备可用

1. 打开 Xcode，选择“Window” →“Devices and Simulators”。
2. 在左侧选择 iPhone，确认没有“未信任”“正在准备设备”或“Developer Mode disabled”等提示；如有提示，按 Xcode 给出的操作完成信任、配对或准备。
3. 设备名称旁显示可用状态后，再继续生成工程和安装。首次连接时 Xcode 会自动准备开发者支持文件（Developer Disk Image），请等待完成，不要拔掉数据线。

### 3. 一键完成配对与工程生成

以下命令自动完成「查询 UDID → 导出 lockdown 记录 → 生成 RemotePairing 文件 → xcodegen 生成工程 → 打开 Xcode」:

```bash
tools/setup.sh
```

多台设备同时连接时脚本会列出候选供选择,也可用 `tools/setup.sh --udid YOUR_UDID` 直接指定。脚本只做命令行部分;打开 Xcode 后仍需按下文「构建、签名与安装」手动完成签名并点击运行。如果脚本中途失败,可按下面两节的手动步骤逐步排查。

注意:`pipx install pymobiledevice3` 只对命令行生效;脚本内部用 `python3` 运行引导脚本,需要当前 `python3` 能 import 该包(例如 `pip3 install pymobiledevice3`,或在对应虚拟环境中运行)。

## 首次配对(每台手机一次)

RemotePairing 使用设备专属 Ed25519 私钥。仓库不会、也绝不能包含可直接使用的配对文件。

1. 连接并解锁 iPhone，在 Xcode 中确认设备可用。
2. 查询 UDID：

   ```bash
   xcrun devicectl list devices
   ```

3. 导出当前 Mac 与手机的 lockdown 记录：

   ```bash
   pymobiledevice3 lockdown save-pair-record pairing_record.mobiledevicepairing --udid YOUR_UDID
   ```

4. 生成 App 使用的 RemotePairing 记录：

   ```bash
   python3 tools/bootstrap_rp_pairing.py \
     --udid YOUR_UDID \
     --lockdown-record pairing_record.mobiledevicepairing
   ```

脚本默认写入：

```text
LocationMocker/LocationMocker/Resources/Debug/rp_pairing_file.plist
```

该文件和 lockdown 记录都含私钥，已由 `.gitignore` 排除。不要上传、分享或复制到其他设备。

## 构建、签名与安装

配对文件生成后再生成 Xcode 工程，这样 XcodeGen 才会把本地记录加入开发构建：

```bash
cd LocationMocker
xcodegen generate
open LocationMocker.xcodeproj
```

工程打开后按以下步骤签名并安装：

1. 在左侧项目导航中选择 `LocationMocker` 项目，再选择 `LocationMocker` target。
2. 打开“Signing & Capabilities”，勾选“Automatically manage signing”。
3. 在“Team”中选择自己的 Apple 开发团队；使用免费 Apple 账号时选择 `Personal Team` 即可。
4. 将“Bundle Identifier”改为全局唯一的值，例如 `com.yourname.LocationMocker`。若出现红色签名错误，先确认已登录 Xcode： “Xcode” →“Settings” →“Accounts”。
5. 在顶部 Scheme 旁的设备列表中选择刚连接的 iPhone，**不要选择模拟器**。
6. 点击左上角运行按钮（▶︎）。Xcode 会编译、签名并安装 App；首次安装需要等待依赖下载和设备准备完成。
7. 安装完成后，iPhone 会自动打开 LocationMocker。若手机提示不信任开发者，前往“设置” →“通用” →“VPN 与设备管理”，选择对应的开发者 App 并点击“信任”。

> [!WARNING]
> **免费 Personal Team 签名 7 天后到期。** 到期后 App 无法打开（点图标闪退或提示“不再可用”），这不是 Bug。只要在手机上还能看到图标，用 Xcode 重新点一次运行（▶︎）重装即可恢复，配对文件和 App 数据不受影响。长期使用建议养成「到期前重跑一次」的习惯，或改用付费开发者账号（签名有效期 1 年）。

项目通过 Swift Package Manager 获取 `OpenSSL-Package` 3.6.2000，不需要提交本地二进制 vendor 目录。

### 签名到期后的重装

免费签名到期后无需重新配对、无需重新生成工程，任选一种方式重装：

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

### 安装或运行失败时

- Xcode 中没有 iPhone：确认数据线支持数据、手机已解锁并已点“信任”，然后关闭并重新打开“Devices and Simulators”。
- 提示 Developer Mode 未开启：按上面的步骤开启开发者模式并完成重启确认。
- 提示 Provisioning Profile、Signing 或 Bundle Identifier 错误：选择正确的 Team，并换成未被占用的 Bundle Identifier。
- 安装后立即退出或无法启动：在 iPhone“VPN 与设备管理”中信任开发者证书；若 7 天前安装过，参见上文「签名到期后的重装」。
- 显示正在准备设备或无法挂载 Developer Disk Image：保持数据线连接、手机解锁并保持网络可用，等待 Xcode 完成后重试。

首次运行前：

1. 用 Xcode 连接一次手机，确保 Developer Disk Image 已挂载。
2. 打开并连接 Wi-Fi。仅插 USB 或只使用蜂窝网络时，RemotePairing 链路可能无法建立。
3. 在手机打开 LocalDevVPN 并保持“已连接”。
4. 打开 LocationMocker，选择位置后点“固定点”“路线模拟”或“跑道”。
5. 顶部出现“系统注入”后，可在系统地图或其他使用 CoreLocation 的 App 中验证。
6. 结束时回到 LocationMocker 点“停止”，等待“清除中”消失。

如果提示“无 LocalDevVPN”“系统定位注入失败”或错误 61 / `Connection refused`，请优先检查手机 Wi-Fi 是否已开启并已连接网络，然后重新连接 LocalDevVPN 再重试。

## 测试

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

## 已知限制

- 纯手机端注入依赖 Wi-Fi 网络接口；关闭 Wi-Fi 时即使 LocalDevVPN 显示已连接，也可能无法完成系统定位注入。
- 手机重启、DDI 状态变化或 LocalDevVPN 断开后需要重新建立会话。
- App 内 DDI 自动挂载与断线自动重连尚未完成。
- 模拟定位可能在断线后“粘住”；务必使用 App 的“停止”显式清除，必要时重启手机。
- 免费开发者签名 7 天到期，到期后需重装，见「签名到期后的重装」。
- 部分应用会结合基站、运动传感器、网络或账户风控，单独修改 CoreLocation 不保证有效。
- `LocationMockerTunnel` 是付费开发者账号可用的自建 Network Extension 实验目标，默认未嵌入主 App。

## 目录

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

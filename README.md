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

## 首次配对（每台手机一次）

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

## 构建与安装

配对文件生成后再生成 Xcode 工程，这样 XcodeGen 才会把本地记录加入开发构建：

```bash
cd LocationMocker
xcodegen generate
open LocationMocker.xcodeproj
```

在 Xcode 中选择自己的 Team、唯一 Bundle Identifier 和目标 iPhone，然后运行。项目通过 Swift Package Manager 获取 `OpenSSL-Package` 3.6.2000，不需要提交本地二进制 vendor 目录。

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
- 免费开发者签名通常 7 天到期。
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

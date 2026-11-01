# Windows 11 复刻与续签

此目录来自仓库 ios 分支。iOS 使用 MapKit，不需要 Android 高德 Key。

## 先取得原始 IPA

优先请原作者提供未加入其他手机配对私钥的原始 LocationMocker IPA。
不要从手机卸载旧 App；到期不代表数据已经丢失。

若没有 IPA，可将本地改动放入自己有权限的 GitHub 仓库：

1. 保留 ios 分支源码以及 `.github/workflows/ios-unsigned.yml`。
2. 确保工作流文件存在于默认分支，开启 Actions。
3. 运行 `Build unsigned iOS IPA`，选择包含 iOS 源码的分支。
4. 成功后下载 `LocationMocker-original-unsigned` artifact 并解压。
5. 原始输入为 `LocationMocker-original-unsigned.ipa`。未签名包不能直接安装。

该流程由远端 macOS/Xcode 编译；本地 Windows 不编译 Swift。新增工作流尚未在远端运行，
若失败需查看 Actions 的首个构建错误，不保证当前 runner/Xcode 与源码完全兼容。
工作流不需要 Apple 密码、P12 或设备配对文件。不要把这些文件上传到仓库。

## 准备 Windows 与手机

1. 从 Apple 官方入口安装 Apple Devices：https://support.apple.com/118290 。
2. USB 连接 iPhone，解锁并确认信任当前电脑；开启开发者模式。
3. 从原仓库 `Windows installer` 工作流的 ios 分支成功构建下载
   `LocationMocker-Windows`，完整解压。仓库入口：
   https://github.com/zjhaaa042-cloud/location-by-youself/actions/workflows/windows-installer.yml
4. 运行完整包中的 EXE，检测手机，选择原始 IPA，点击免费 Apple ID 安装/续签。
   Apple ID、密码、验证码只在你本机的交互窗口输入。
5. 若原仓库没有可下载产物，在自己的仓库运行现有 `Windows installer` 工作流；
   该流程会构建 Rust 签名组件。本地 Python GUI 本身不包含这个 EXE。

## 本地源码入口

首次双击根目录 `setup-windows.cmd` 安装 Python 依赖（需已有 Python）。
然后双击 `start-windows.cmd` 可检查依赖后启动 Python GUI。
独立只读检查：`.venv\Scripts\python.exe windows\preflight.py`。
源码 GUI 的内置免费签名模式还需将签名组件放到
`windows/free-sign/target/release/locationmocker-free-sign.exe`；
也可以用“生成 iLoader 专用 IPA”，再在官方 iLoader 中签名。

## 安装后单独验收

手机上确认开发者信任，Wi-Fi 和 LocalDevVPN 正常，再验证 App 能启动、注入和停止。
仓库尚未实现 Windows 自动准备 DDI，若提示开发者服务不可用，需要另行诊断；
签名成功不能证明定位链路可用。新电脑需要自己的配对记录，不能复用学长的私钥。
免费账号按实际描述文件到期日定期续签，并保持相同原始 IPA、Apple ID 与团队。
首次从其他签名方式迁移可能变成独立 App，收藏和设置不保证自动迁移。

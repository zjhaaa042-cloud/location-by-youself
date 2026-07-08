# 定位模拟器

安卓原生定位模拟工具，使用 Kotlin、Jetpack Compose、Material 3、高德地图 SDK 和系统模拟定位接口。

## 功能

- 点击地图任意位置，输出固定模拟定位。
- 路线模式下点击多个途经点，生成本地平滑轨迹。
- 支持 5-120 km/h 速度控制。
- 支持单次、循环、往返三种路线回放模式。
- 通过前台定位服务持续输出模拟位置，通知栏提供暂停和停止操作。
- 高德地图用于底图显示和点选，写入系统 mock location 前会转换为 WGS84 坐标，减少国内地图坐标偏移。
- 操场模式支持点选操场附近位置后识别 POI，自动生成逆时针跑步路线。
- 操场跑步支持 6-12 km/h 自然速度波动，以及每圈 1-3m 的平滑路径漂移。

## 高德地图 Key

仓库不会提交高德地图 API Key。请在本机 `local.properties` 中添加：

```properties
AMAP_API_KEY=你的高德地图Key
```

当前 Android 包名是：

```text
com.example.locationmocker
```

如果使用 debug 包，高德控制台还需要配置你的 debug keystore SHA1。

## 使用前准备

1. 用 Android Studio 打开项目目录。
2. 等待 Gradle Sync 完成后安装到真机。
3. 在手机上开启“开发者选项”。
4. 进入“选择模拟位置信息应用”，选择 `定位模拟器`。
5. 授予定位权限，并确保系统定位服务已开启。

本项目只使用系统官方模拟定位接口，不包含 ROOT、隐藏伪装、绕过检测或规避第三方风控的逻辑。系统和第三方应用可以识别模拟定位。

## 验证

推荐在 Android Studio 或本机 Gradle 环境中运行：

```bash
gradle testDebugUnitTest
gradle connectedDebugAndroidTest
```

真机验收建议覆盖 Android 8、Android 12、Android 14+，重点检查定点模拟、路线回放、锁屏后前台服务持续运行，以及停止后 mock provider 是否清理。

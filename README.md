# 定位模拟器（Location Mocker）

一款无需 Root 的 Android 模拟定位工具。支持单点定位、路线移动与操场跑步，可调速度、循环方式和定位参数，并通过前台服务保持持续运行。

[![Android](https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white)](https://developer.android.com/)
[![Kotlin](https://img.shields.io/badge/Kotlin-2.2.10-7F52FF?logo=kotlin&logoColor=white)](https://kotlinlang.org/)
[![License](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)

> [!WARNING]
> 本项目仅用于开发、测试和学习。请遵守所在地法律法规及目标应用的服务条款，禁止用于作弊、欺诈或绕过安全机制。

## 仓库与分支

GitHub 与 Gitee 为同步镜像，两个仓库均保留 Android 和 iOS 两条分支：

| 平台 | Android（`master`） | iOS（`ios`） |
|---|---|---|
| GitHub | [查看 Android 分支](https://github.com/zjhaaa042-cloud/location-by-youself/tree/master) | [查看 iOS 分支](https://github.com/zjhaaa042-cloud/location-by-youself/tree/ios) |
| Gitee | [查看 Android 分支](https://gitee.com/ZhangJiaHuidjj/location-by-youself/tree/master) | [查看 iOS 分支](https://gitee.com/ZhangJiaHuidjj/location-by-youself/tree/ios) |

当前 README 介绍的是 Android `master` 分支。

## 功能亮点

| 模式 | 适用场景 | 主要能力 |
|---|---|---|
| 单点定位 | 固定在指定地点 | 地图选点、坐标输入、收藏地点、亚米级稳定微扰 |
| 路线移动 | 模拟步行或驾车 | 多点路线、速度调节、循环/往返、平滑移动 |
| 操场跑步 | 模拟标准跑道运动 | 跑道识别、方向切换、圈数/距离配置、自然配速 |

此外还支持：

- 地点搜索与收藏
- WGS-84、GCJ-02 坐标转换
- 精度、高度、速度和方向等定位参数模拟
- 前台服务保活及异常恢复
- Android 深色模式与 Material 3 界面

## 快速开始

### 1. 环境要求

- Android Studio（建议使用最新稳定版）
- JDK 17
- Android SDK 36
- Android 8.0（API 26）及以上设备或模拟器
- 高德开放平台 Android Key

### 2. 配置高德地图 Key

在[高德开放平台控制台](https://console.amap.com/)创建 Android 应用，填写本项目包名：

```text
com.example.locationmocker
```

然后在项目根目录的 `local.properties` 中添加：

```properties
AMAP_API_KEY=你的高德地图Key
```

`local.properties` 不应提交到版本库。

### 3. 构建并安装

Windows：

```powershell
.\gradlew.bat :app:assembleDebug
.\gradlew.bat :app:installDebug
```

macOS / Linux：

```bash
./gradlew :app:assembleDebug
./gradlew :app:installDebug
```

生成的 APK 位于：

```text
app/build/outputs/apk/debug/app-debug.apk
```

### 4. 配置设备

1. 打开系统“开发者选项”。
2. 进入“选择模拟位置信息应用”。
3. 选择“定位模拟器”。
4. 打开应用并授予定位、通知等必要权限。

不同品牌系统的菜单名称可能略有差异。若应用提示未被选为模拟位置应用，请重新检查开发者选项。

## 使用说明

### 单点定位

1. 在地图上长按选点，或使用搜索、收藏、坐标输入。
2. 切换到“定点”模式。
3. 点击开始模拟。
4. 需要结束时点击停止，不要直接强制结束应用进程。

单点模式会同时维护 Android 平台测试定位源与 Google Fused Location 模拟模式，并持续刷新同一目标附近的亚米级稳定点。这样可避免部分设备在几秒后重新采用真实坐标；服务被系统短暂打断时也会尝试恢复当前定点任务。

### 路线移动

1. 依次添加至少两个路线点。
2. 设置移动速度与播放方式。
3. 选择单次、循环或往返后开始模拟。

### 操场跑步

1. 将地图移动到跑道区域并选择操场模式。
2. 执行跑道识别，确认中心、方向和路线是否正确。
3. 设置圈数、目标距离或配速后开始模拟。

识别不理想时，可放大地图、让完整跑道位于屏幕中央，并避免建筑物或道路覆盖过多。

## 单点稳定机制

部分 Android 设备会同时从系统 `LocationManager` 与 Google Play 服务获取位置。如果只向其中一个来源注入模拟坐标，系统可能在数秒后重新显示真实位置。

本项目在单点模式中同时处理：

- Google Fused Location Provider 的 Mock Mode
- GPS、Network 与 Fused 平台测试定位源
- 单调递增时间戳、精度和速度等完整定位字段
- 前台服务持续注入、状态恢复与停止清理
- 地图真实定位图层隔离，避免 UI 被真实蓝点覆盖

## 技术栈

| 类别 | 技术 |
|---|---|
| 语言 | Kotlin 2.2.10 |
| UI | Jetpack Compose、Material 3 |
| 架构 | MVVM、Repository、Foreground Service |
| 地图 | 高德地图 SDK 10.1.200 |
| 定位 | Android Mock Location、Google Play Services Location 21.4.0 |
| 构建 | Android Gradle Plugin 9.2.1、Gradle 9.4.1、JDK 17 |
| Android | compileSdk / targetSdk 36，minSdk 26 |

## 项目结构

```text
app/src/main/java/com/example/locationmocker/
├── data/                  # 设置持久化与跑道检测
├── domain/
│   ├── geo/               # 坐标转换
│   ├── model/             # 模拟配置与状态模型
│   ├── route/             # 路线规划、播放与定点序列
│   └── track/             # 跑道分段与自然跑步轨迹
├── presentation/          # Compose 页面、组件与 ViewModel
└── service/               # 模拟定位控制器与前台服务
```

## 权限说明

| 权限 | 用途 |
|---|---|
| 精确/粗略定位 | 地图定位、搜索及定位模拟状态判断 |
| 前台服务与位置类型 | 在后台持续执行模拟任务 |
| 通知 | 显示前台服务运行状态 |
| 网络 | 加载地图、地点搜索及相关服务 |

应用不会自动获得模拟定位能力，仍需用户在开发者选项中手动选定。

## 开发与验证

```powershell
# 编译 Debug APK
.\gradlew.bat :app:assembleDebug

# 编译单元测试源码
.\gradlew.bat :app:compileDebugUnitTestKotlin

# 运行 Android Lint
.\gradlew.bat :app:lintDebug

# 运行单元测试
.\gradlew.bat :app:testDebugUnitTest
```

若 Windows 用户目录包含中文且 Gradle Worker 报找不到主类，可优先使用 Android Studio 自带 JBR，并将 Gradle 缓存目录配置到纯英文路径后重试。

## 常见问题

### 开始后几秒又回到真实位置

- 确认开发者选项中的模拟位置应用仍为“定位模拟器”。
- 关闭其他定位模拟工具，避免多个应用同时注入位置。
- 允许应用后台运行，并关闭系统对该应用的省电限制。
- 停止后重新开始模拟；必要时重启设备再试。

### 地图无法加载或地点搜索失败

- 检查 `AMAP_API_KEY` 是否已写入 `local.properties`。
- 确认 Key 的包名和 SHA-1 与当前签名一致。
- 检查网络权限与设备网络连接。

### 状态栏提示服务运行，但目标应用没有变化

- 确认目标应用没有自行屏蔽模拟位置。
- 检查设备是否具备 Google Play 服务；本项目也会使用 Android 平台定位源作为兼容路径。
- 某些深度定制系统需要额外允许后台定位、自启动或前台服务。

## 许可证

本项目采用 [GNU Affero General Public License v3.0](LICENSE) 开源。

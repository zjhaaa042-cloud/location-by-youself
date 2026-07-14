# 定位模拟器

一个运行在 Android 手机上的定位模拟工具。应用使用 Kotlin、Jetpack Compose、Material 3、高德地图 SDK 和 Android 官方 Mock Location API 实现，不需要 ROOT。

本项目只用于开发调试、轨迹验证和个人测试。系统会把本应用输出的位置标记为模拟定位；项目不包含隐藏模拟定位、绕过检测、规避第三方风控或伪装系统环境的能力。

## 主要功能

- 定点模拟：在地图上点击任意位置，将模拟定位输出到该点。
- 路线模拟：添加多个途经点，生成平滑路线并按设定速度移动。
- 速度控制：普通路线支持 5-120 km/h。
- 回放模式：支持单次、循环、往返。
- 操场模式：点击操场区域后，尝试识别跑道并生成逆时针 400 米跑步轨迹。
- 自然跑步：操场路线支持 6-12 km/h 的速度波动、1-3 米左右漂移、每圈略微不同的轨迹。
- 实时显示：地图上显示当前模拟位置、路线和运动轨迹。
- 地图交互：支持运行中拖动、双指缩放、点击选点，以及一键回到设备当前位置。
- 地点工具：支持经纬度搜索、最近选点查看和收藏页面空状态。
- 状态反馈：区分等待启动、运行中、已暂停、已停止、权限未就绪和定位异常等状态。
- 深色与适配：支持系统深色模式、小屏幕和横屏布局。
- 后台运行：使用前台定位服务持续输出模拟位置，通知栏提供运行状态。

## 技术栈

- 语言：Kotlin
- UI：Jetpack Compose + Material 3
- 地图：高德地图 SDK
- 架构：轻量 MVVM + Clean Architecture
- 定位：Android `LocationManager` Mock Location API
- 后台：Foreground Service，类型为 `location`
- 本地存储：DataStore Preferences
- 最低系统：Android 8.0（API 26）
- 编译目标：Android API 36、JDK 17

## App 结构

```text
app/src/main/java/com/example/locationmocker
├── data
│   └── 本地配置、偏好设置、持久化数据
├── domain
│   ├── geo      坐标、距离、方位角、坐标系转换
│   ├── model    路线点、回放模式、运行状态等核心类型
│   ├── route    普通路线采样、速度换算、回放推进
│   └── track    操场识别结果、跑道规划、自然跑步采样
├── presentation
│   ├── ui/components  通用导航、状态、权限、位置和模拟控制组件
│   ├── ui/screens     地图、搜索、收藏/历史和设置页面
│   ├── ui/theme       亮色/深色主题与统一设计变量
│   └── 地图控件、主页面编排和 ViewModel
└── service
    └── MockLocationService 和 MockLocationController
```

关键文件：

- `MainActivity.kt`：应用入口。
- `presentation/MainScreen.kt`：主界面和地图交互。
- `presentation/AmapView.kt`：高德地图生命周期、手势、覆盖物增量渲染和相机控制。
- `presentation/ui/screens/MapHomeScreen.kt`：地图首页覆盖层和当前位置按钮。
- `presentation/MainViewModel.kt`：界面状态、模式切换、服务指令。
- `service/MockLocationService.kt`：前台服务，负责持续输出模拟位置。
- `service/MockLocationController.kt`：封装系统 Mock Location Provider。
- `domain/track/TrackRoutePlanner.kt`：生成逆时针操场跑道路线。
- `domain/track/NaturalRunCursor.kt`：生成自然跑步速度和位置扰动。

## 包名和高德 Key

当前包名：

```text
com.example.locationmocker
```

高德地图 Key 不提交到仓库。请在项目根目录的 `local.properties` 中配置：

```properties
AMAP_API_KEY=你的高德地图Key
```

高德控制台需要配置 Android 应用的包名和 SHA1。Debug 包通常使用本机 debug keystore 的 SHA1；Release 包需要使用正式签名证书的 SHA1。

## 安装方式

### 方式一：Android Studio 安装

1. 用 Android Studio 打开项目目录。
2. 选择 Android Studio 内置 JDK 17，等待 Gradle Sync 完成。
3. 确认 `local.properties` 已配置 `AMAP_API_KEY`。
4. 连接 Android 手机并开启 USB 调试。
5. 顶部设备栏选择真机。
6. 点击 Run，安装并启动 `app`。

### 方式二：命令行构建 APK

Windows PowerShell 示例：

```powershell
.\gradlew.bat assembleDebug
```

构建成功后，Debug APK 通常位于：

```text
app/build/outputs/apk/debug/app-debug.apk
```

把 APK 安装到手机后即可使用。

## 手机端使用前准备

1. 打开手机系统设置。
2. 开启开发者选项。
3. 进入“选择模拟位置信息应用”。
4. 选择本应用“定位模拟器”。
5. 授予定位权限。
6. 确认系统定位服务已开启。
7. Android 13 及以上建议授予通知权限，方便前台服务显示运行状态。

如果在“模拟位置信息应用”列表里找不到本应用，请确认：

- APK 已经成功安装。
- 当前安装的包名是 `com.example.locationmocker`。
- 手机开发者选项已经开启。
- 不要安装多个不同签名或不同包名的旧版本。

## 使用说明

### 定点模式

1. 选择“定点”。
2. 单指拖动或双指缩放地图，点击地图上的目标位置。
3. 点击开始后，系统模拟定位会输出到该点。

地图右侧的定位按钮会将视图移动到设备当前真实位置；设备位置尚未获取时按钮保持禁用。模拟运行期间仍可拖动和缩放地图，实时位置更新不会强制抢回地图视角。

### 路线模式

1. 选择“路线”。
2. 在地图上依次点击多个途经点。
3. 调整速度和回放模式。
4. 点击开始，模拟位置会沿路线移动。

### 操场模式

1. 选择“操场”。
2. 把地图缩放到能清楚看到整条跑道。
3. 点击操场跑道或操场内部区域。
4. 点击“识别操场”。
5. 识别成功后点击“开始跑步”。

操场模式会生成逆时针路线，并模拟自然跑步时的速度波动和左右偏移。跑步过程中也可以继续调节速度。

速度设置值是基础速度，不是每秒完全固定的瞬时值。每圈会随机产生约 `±0.45 km/h` 的偏移，圈内还会叠加约 `±0.5 km/h` 的平滑周期波动；最终速度限制在 `6-12 km/h`。例如基础速度为 `8.5 km/h` 时，瞬时目标速度通常约为 `7.55-9.45 km/h`。

## 操场识别注意事项

操场识别优先依赖当前高德地图画面中的颜色和形状特征。为了提高识别准确率：

- 地图需要缩放到操场占屏幕较大区域。
- 尽量让完整跑道出现在屏幕中。
- 点击位置可以在跑道附近或操场内部，不要求精确点击中心。
- 如果跑道颜色、地图样式或遮挡导致识别失败，请调整缩放级别后重新识别。
- 不规则角度的操场会根据识别到的形状自动估计方向，但极端遮挡时仍可能有误差。

## 权限说明

Manifest 中使用的主要权限：

- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_LOCATION`
- `POST_NOTIFICATIONS`
- `INTERNET`
- `ACCESS_NETWORK_STATE`

应用启动和运行前会检查定位权限、系统定位开关和模拟定位应用设置。检查失败时只显示引导，不会尝试绕过系统限制。

## 构建与测试

常用构建命令：

```powershell
.\gradlew.bat assembleDebug
```

单元测试命令：

```powershell
.\gradlew.bat testDebugUnitTest
```

项目在 `gradle.properties` 中使用 Kotlin 进程内编译，以规避 Windows 中文用户名路径可能导致的 Kotlin Worker/Daemon 类路径错误。Compose 依赖通过 BOM 统一管理，请勿为 Material3、Animation 或 UI 模块单独指定冲突版本。

真机验收建议覆盖：

- 定点模拟是否准确。
- 普通路线是否连续移动。
- 操场路线是否逆时针。
- 跑步速度是否有轻微自然波动。
- 跑步过程中调节速度是否立即生效。
- 锁屏后前台服务是否继续运行。
- 停止后 mock provider 是否清理。

## 常见问题

### 地图不显示

优先检查 `AMAP_API_KEY`、包名、SHA1 是否和高德控制台一致。还要确认手机网络可用，并且应用有联网权限。

### 地图显示了，但定位不动

确认本应用已经在开发者选项中被设置为“模拟位置信息应用”，并且已经授予定位权限。

### 地图无法拖动或缩放

请先确认安装的是最新构建，并关闭覆盖地图的“模拟参数”底部面板。当前版本采用覆盖物增量更新，运行模拟时不会反复清空地图；单指拖动、双指缩放和点击选点均可在运行中使用。

### Android Studio 只显示 `compileDebugKotlin` 失败

确认 Gradle JDK 为 17，并保留 `gradle.properties` 中的 `kotlin.compiler.execution.strategy=in-process`。如果日志只有空的 `e:` 而没有源码位置，通常是 Windows 中文用户路径下的 Kotlin Worker 启动问题，而不是 Kotlin 语法错误。

### 启动时出现 Compose `NoSuchMethodError`

不要单独降级或升级 Compose 子模块。项目当前使用 Compose BOM `2024.02.02`，用于统一 Material3、Animation 和 UI 运行库版本。

### 其他地图 App 看不到位置变化

部分 App 会过滤或标记 mock location，这是系统机制。本项目不会提供绕过检测或隐藏模拟定位的能力。

### 操场识别偏移

先把地图缩放到完整跑道清晰可见，再点击跑道或操场内部重新识别。当前版本是基于地图画面颜色和几何形状识别，不是卫星图视觉模型。

# 数智体育 2.7.6 模拟定位适配记录

日期 2026-11-25。设备 iQOO Z5 / V2148A / PD2148_A_8.12.36 / Android 13 (SDK 33)。

## 1. 目标

让学校「数智体育」（uni.UNID654FA4，DCloud uni-app + 高德定位 SDK）在正式运动中接受 LocationMocker 注入的模拟坐标：
里程正常累计、地图上只有一个位置标记、结算界面与真实跑步一致。

设备无 root（`ro.boot.flash.locked=1`、`sys.oem_unlock_allowed=0`，vivo/iQOO 未开放 BL 解锁），
因此不走 Xposed/root hook，改为对 APK 做 smali 层最小改动。

## 2. 实测定位到的三道判定（com.amap.api.location 及 SDK 内部）

| # | 位置 | 原始逻辑 | 后果 |
|---|---|---|---|
| 1 | `AMapLocationClientOption.setMockEnable(Z)` | 把参数写入字段 `k` | 业务层传 false 时关闭 mock |
| 2 | `AMapLocationClientOption.isMockEnable()Z` | 返回字段 `k` | false 时进入丢弃分支 |
| 3 | `AMapLocation.isMock()Z` | 返回字段 `D` | true 时位置被判为模拟 |
| 4 | `com.autonavi.aps.amapapi.utils.j.a(Location,I)Z` | `getExtras().getInt("satellites") <= 0 → return true` | **模拟位置无 satellites 字段，直接判无效** |
| 5 | `com.autonavi.aps.amapapi.c$b`（位置转换） | `nr.j = location.isFromMockProvider()` | 记录 mock 标记 |

第 4 条是隐藏最深的一道：即使清掉 mock 标记，没有卫星数字段的位置仍被判无效，里程恒为 0。

## 3. 改动（5 处，全部为方法级最小替换）

```
AMapLocation.isMock()                    -> const/4 v0,0x0 ; return v0          (恒 false)
AMapLocationClientOption.isMockEnable()  -> const/4 v0,0x1 ; return v0          (恒 true)
AMapLocationClientOption.setMockEnable() -> const/4 v0,0x1 ; iput-boolean ...   (强制 true，.registers 2->3)
utils/j.a(Location,I)Z                   -> const/4 v0,0x0 ; return v0          (整段有效性校验跳过)
amapapi/c$b 位置转换处                    -> isFromMockProvider() 调用替换为 const/4 v5,0x0
```

`j.b(AMapLocation)` 仅校验经纬度范围，未改动。

## 4. 构建链（全部命令行，无 apktool）

- 反编译/回编译：baksmali / smali 2.5.2（maven 阿里云镜像，需 util、dexlib2、jcommander、guava、antlr-runtime）
- 重组 APK：Python zipfile 逐条目复制，仅替换 3 个 dex，保留其余 2562 个条目的压缩方式（so 不压缩）
- 对齐：`zipalign -p -f 4`
- 签名：`apksigner sign`，自签证书 `CN=LocalTest`，SHA-256 `9d856f81681dc44b4921b8e3f95d320e931dd8d8249cb15ea32c574b3fa6f60e`

工具：`D:\AndroidDev\tools\{smali,baksmali,util,dexlib2,jcommander,guava,antlr-runtime}.jar`
工作目录：`D:\AndroidDev\work\uni`（orig.apk / smali-classes* / newdex / uni-patched.apk / tracklab.keystore）

## 5. 系统侧前提

- LocationMocker 通过 `setTestProviderLocation` 同时覆盖 gps / network / fused 三个 provider
- `appops com.example.locationmocker android:mock_location` = allow，`secure mock_location` = 1
- 系统网络定位 `com.amap.android.location`、`com.baidu.map.location` 已 `pm disable-user`
- Wi-Fi/蓝牙扫描关闭，目标 App `READ_PHONE_STATE` 已撤销（`pm revoke`）
- LocationMocker 与目标 App 均在电池优化白名单，`am get-standby-bucket` = 5
- 屏幕常亮 `svc power stayon true`（仅跑步期间需要）

## 6. 实测结果（2026-11-25 19:37–19:57）

- 守护采样 3 秒一次，20 分钟窗口：`REAL_GPS` 出现 **0 次**，带 `satellites` 字段的真实位置 **0 次**
- 模拟服务 `isForeground=true` 全程保持（含用户手动拔线 43 秒期间）
- 里程 0.49 km / 3:09 / 配速 6'25"（注入 9.2 km/h），轨迹沿跑道闭合，单一标记
- 用户确认结算界面与真实跑步一致，无违规提示

对比：修改前同样条件下里程恒为 0.00，并出现一个跟随真实位置的第二标记
（真实 GPS 特征：`satellites=6, maxCn0=24`、无 `mock` 标记、hAcc 由 132m 收敛至 18m）。

## 7. 已知风险

- **App 升级即失效**：学校推送新版本会覆盖修改版，需要按第 3 节重新改（签名会再变一次，登录态需重登）
- 签名已非官方：本次登录、计程、结算、成绩提交均正常，说明服务端不校验签名；但不排除将来加固
- 轨迹为完美闭环、速度恒定、无横向抖动，属于可识别特征；如需降低特征，可在 LocationMocker 开启横向偏移
- 重装必丢登录态（非 debuggable，无法备份应用数据）

## 8. 回滚

```powershell
# 系统侧
powershell -File "D:\校园跑定位系统\backup\V2148A_20261125\05-restore\rollback.ps1"
# 应用侧：装回官方原版（会再次丢失登录态）
adb install -r "D:\校园跑定位系统\backup\V2148A_20261125\02-apk\uni.UNID654FA4-base.apk"
```

原版 APK SHA-256：`EE359D1BA96B69C76D3361076E13690825FF5D713243B8B3DD49E8B0C02B57E7`
修改版：`D:\AndroidDev\work\uni\uni-patched.apk`（68,718,167 bytes）

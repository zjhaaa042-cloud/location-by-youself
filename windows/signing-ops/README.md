# signing-ops

Windows 侧的免费签名运维脚本：体检、续签、备份、到期提醒。迁移背景与完整步骤见
[`docs/windows-signing-migration.md`](../../docs/windows-signing-migration.md)。

| 文件 | 作用 |
|---|---|
| `check-status.ps1` | 只读体检：剩余天数、USB 设备、App 是否存在、anisette 是否可达（退出码 0/1/2） |
| `renew.ps1` | 驱动 iLoader 完成重新签名与覆盖安装；不读取、不保存密码 |
| `backup.ps1` | 备份 `config.json`、iLoader 会话、IPA、配对文件 |
| `install-schedule.ps1` | 注册每日体检计划任务，剩余 ≤2 天时弹通知 |

## 使用

```powershell
Copy-Item config.example.json config.json
notepad config.json          # 填 workRoot / ipaPath / bundleId / appleId / teamId / signedOn

powershell -File .\check-status.ps1 -Deep
powershell -File .\renew.ps1 -DryRun
powershell -File .\renew.ps1
```

`renew.ps1` 的退出码：`3` 无设备 · `4` 无 IPA · `7` iLoader 未登录 · `10` 文件选择框未出现 · `12` iLoader 报错 · `13` 超时。

## 注意

`config.json`、`backups/`、`*.log` 含账号会话与配对信息，已在仓库 `.gitignore` 中排除，请勿提交或分享。

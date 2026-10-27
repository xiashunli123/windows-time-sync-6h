# Windows Time Sync 6h

用 Windows 自带的时间服务，每 6 小时自动校准一次系统时钟。附一篇经过脱敏的 ChatGPT Windows 桌面端排障案例。

## 功能

- 每天按电脑本地时区在 **00:05、06:05、12:05、18:05** 运行，安装后立即执行一次。
- 使用现有 Windows 时间源，通过 `w32tm /resync /rediscover` 校时。
- 单次运行最多尝试 3 次；第二次尝试前重启 Windows Time 服务。
- 失败后由任务计划程序以 5 分钟间隔再重试最多 2 次。
- 关机或休眠错过任务时，在系统允许后补跑；不主动唤醒电脑。
- 安装后以 SYSTEM 身份在后台运行，脚本目录仅管理员和 SYSTEM 可修改。
- 保存最近一次结果及有限大小的本地日志。

## 安装

适用于拥有本机管理员权限的 Windows 10/11。Windows PowerShell 5.1 和任务计划程序通常已随系统提供。

1. 下载本仓库 ZIP，解压到普通本地目录；不要直接在 ZIP 内运行。
2. 阅读 `scripts/` 中的脚本。
3. 双击 `Install.cmd`，在 Windows 管理员授权窗口确认。
4. 查看 `scripts/install-result.json`。`Success: true` 代表任务注册成功，**不等于已经校时成功**。
5. 查看 `%ProgramData%\TimeSync6h\last-result.json`，其中 `Success: true` 表示本次 Windows 校时命令成功返回。

安装后的任务名为 `TimeSync6h`，目录为 `%ProgramData%\TimeSync6h`。安装包无需长期保留，安装后的任务直接使用该目录内的脚本。

## 查看运行结果

```powershell
Get-Content "$env:ProgramData\TimeSync6h\last-result.json"
Get-Content "$env:ProgramData\TimeSync6h\time-sync.log" -Tail 20
```

管理员 PowerShell 中还可以查看任务和时间服务状态：

```powershell
Get-ScheduledTaskInfo -TaskName TimeSync6h
w32tm /query /status
```

示例结果是结构说明，不是从真实设备导出的日志：

```json
{
  "Success": true,
  "Attempts": 1,
  "ExitCode": 0,
  "Source": "time.windows.com,0x9"
}
```

## 停用和卸载

双击 `Uninstall.cmd` 并确认管理员授权。它仅移除本工具的计划任务，保留安装文件和日志供检查；停止自动运行不要求删除日志。

如需暂时停用，可在任务计划程序中禁用 `TimeSync6h`，之后重新启用。

## 工作边界

本工具发起校时，不提供自己的 NTP 服务器，不更改系统时区或现有时间源，也不修改 Windows 原有的同步任务。网络、DNS、UDP 123 或组织策略阻止校时时，任务会失败并记录结果。它不能保证离线校准，也不是高精度授时系统。

校时需要权限。`-ExecutionPolicy Bypass` 仅用于启动本工具的 PowerShell 进程，不会写入系统级执行策略。脚本会更改系统时间，重试时可能短暂重启 Windows Time 服务；域管理或有专用授时要求的设备应由管理员评估后使用。

运行记录留在本机，不包含遥测或上传功能；Windows 时间服务仍会连接系统配置的时间源。日志可能包含时间源、绝对路径、设备错误信息，提交 Issue 前应先脱敏。

## 排障案例

[ChatGPT Windows 桌面端云端准备和本地执行故障排查](docs/chatgpt-windows-troubleshooting.zh-CN.md)

文章记录了约 100 秒时间偏差、旧版 Windows 隔离机制初始化失败，以及云端任务无法访问本地磁盘这三个容易混淆的现象。它是单个设备上的恢复案例，未将环境问题直接定性为所有版本都会发生的产品缺陷。

## 验证

原型曾在一台 Windows 设备上完成安装、SYSTEM 后台执行、四个定时触发器、任务返回码 0、Windows 正常同步状态，以及程序目录权限的实测。

仓库版增加了安装状态反馈、安装目录检查和 CI；这些改动经过语法及静态检查，尚未在额外的 Windows 设备上验证。CI 不安装系统任务、不执行管理员校时，也不等于完成了跨版本运行测试。

本地静态检查：

```powershell
powershell -NoProfile -File .\tests\Test-Repository.ps1
```

## 参考

- [Microsoft：Windows Time 工具与设置](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings)
- [Microsoft：任务触发器](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasktrigger)
- [Microsoft：按需启动的 Windows Time 服务](https://learn.microsoft.com/en-us/troubleshoot/windows-client/active-directory/w32time-not-start-on-workgroup)

采用 [MIT License](LICENSE)。

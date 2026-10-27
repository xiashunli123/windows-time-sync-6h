# ChatGPT Windows 桌面端云端准备和本地执行故障排查

在一次 Windows 桌面端排障中，新建本地项目后，“聊天”和“工作”都提示：“未能完成此项目的云端准备工作”。网络端口测试正常，代理连接记录也能看到 ChatGPT 请求，但项目仍然无法使用。

恢复过程分成了两段：先校准系统时间，让云端项目创建成功；再处理 Windows 本地命令执行环境的初始化问题，让工作任务真正能够创建本地文件夹。中间还出现过任务在云端 Linux 环境执行、无法访问电脑磁盘的情况。

本文保留可验证的错误类型、诊断方法和恢复步骤。所有目录示例均为通用占位，片段经过重写和裁剪，不包含原始截图、完整日志、账号标识或真实项目名称。

## 起点：端口能连通，项目仍然无法准备

当时启用了代理软件的系统代理和 TUN。DNS 查询返回了 `198.18.0.x` 一类地址，代理记录显示相关域名经过了代理节点。开启 TUN 后，TCP 443 测试也通过了。

这些观测回答的是不同的问题：

| 观测 | 能说明什么 | 仍不能说明什么 |
| --- | --- | --- |
| 代理配置使用 Fake-IP，查询返回对应地址 | 查询结果与当前代理的虚拟地址机制一致 | 请求是否最终成功 |
| TCP 443 测试通过 | 这次测试能够建立到目标端口的 TCP 连接 | HTTPS 鉴权、项目创建和长连接是否正常 |
| 连接记录显示某个代理节点 | 连接匹配到了该路由 | 服务端是否接受请求 |
| 普通聊天得到回复 | 该次聊天链路可用 | 本地工具能否启动并操作文件 |

因此，下一步转向客户端的项目初始化记录，而没有继续反复更换 DNS 或删除缓存。

## 第一处故障：创建请求携带的时间发生偏差

项目初始化记录中出现了如下状态。以下为脱敏后的最小片段：

```json
{
  "state": "creating",
  "failure": "clock"
}
```

这比“云端准备失败”的界面提示更具体。随后比较本机时间、独立 HTTPS 服务器响应中的 Date，以及 NTP 取样，发现本机快了约 **100 秒**。只看本机显示的时间和时区，无法发现这一层问题。

管理员 PowerShell 中可使用 Windows 自带工具检查：

```powershell
Get-Service W32Time
w32tm /query /status
w32tm /stripchart /computer:time.windows.com /samples:3 /dataonly
```

`stripchart` 的样本反映本机与时间源之间的偏差。它的网络行为与 Windows 时间服务不完全相同：前者使用临时 UDP 源端口，内置 NTP 客户端使用 UDP 123。因此，取样成功后，仍应实际执行校时并核对结果。[Microsoft 文档](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings)

当时 Windows Time 服务处于停止状态。启动服务并触发校时后，独立取样确认偏差已明显收敛：

```powershell
Start-Service W32Time
w32tm /resync /rediscover
w32tm /query /status
```

这些命令需要相应的本机管理权限。若有组织规定的时间源，应保留该配置，由管理员处理。

### 服务停止并不能单独证明异常

后来复查系统日志，发现历史上出现过无法解析 `time.windows.com` 的记录，也记录过成功校时后的时间回调。这支持“自动校时有过不稳定”的判断，但不能据此确定具体是哪一个代理设置、网络故障或程序造成了全部偏差。

Windows Time 在部分非域设备上默认按需启动，`Manual` 或一时的 `Stopped` 可以是正常状态。把“服务当时没运行”直接解释为“被人关闭”或“长期未校时”，证据都不足。[Microsoft 说明](https://learn.microsoft.com/en-us/troubleshoot/windows-client/active-directory/w32time-not-start-on-workgroup)

### 校时后，旧请求还需要恢复

校准时间后的第一次重试仍然显示错误，后台失败原因却已经从 `clock` 变成了 `expired`。该请求是在校时前创建的，仍然过期。再重试时，客户端生成了新请求，项目状态最终变为 `backed`，聊天也得到正常回复。

```text
creating / clock
        ↓ 校准时间后重新尝试
creating / expired
        ↓ 下一次尝试生成新请求
backed
```

这是本案例中观察到的恢复顺序，不是要求所有相似故障一律“重试两次”。如果错误持续，应继续查最新状态，避免把重试当成通用修复办法。

## 第二处故障：聊天恢复后，本地命令仍然不能启动

随后尝试在示例目录 `D:\Workspaces\demo` 中创建一个文件夹，任务失败。关键错误是：

```text
helper_sandbox_lock_failed
lock sandbox bin dir <USERPROFILE>\.codex\.sandbox-bin
NtCreateFile: Access is denied. (os error 5)
```

失败发生在执行隔离环境准备阶段，文件夹创建命令还没有真正启动。这意味着应先检查本地执行环境，而不能仅凭“拒绝访问”就判断目标项目目录没有写权限。

客户端重启后，该初始化错误仍然存在。日志同时显示设备具备 MXC 能力，但当时选用的仍是旧版 `elevated` 实现。

### 先做单次验证，再修改配置

当前官方文档提供了 MXC 的单次兼容性测试方式。在兼容版本和设备上，可以从项目目录运行：

```powershell
codex -c windows.sandbox=mxc sandbox --include-managed-config --permission-profile :workspace -- cmd.exe /d /c echo MXC_OK
$LASTEXITCODE
```

输出 `MXC_OK` 且退出码为 0，说明这个配置下的命令启动测试成功。它没有覆盖所有工具和网络场景。[官方 Windows 隔离环境文档](https://learn.chatgpt.com/docs/windows/windows-sandbox)

本案例先通过临时的 MXC 优先选项运行输出文字的自检，再测试读取示例项目目录；两项均成功。备份配置后，才在已有的 `config.toml` 中合并下面的选项：

```toml
[features]
prefer_mxc = true
```

如果文件已存在 `[features]`，应在原节中添加或调整键，避免重复创建同名节。该选项的作用是优先采用受支持的 MXC，设备或策略不支持时仍可能走旧版流程；不应把它当成所有 Windows 设备都适用的修复开关。

### 验证要覆盖实际文件操作

新进程中的自检成功后，已经运行的客户端进程仍沿用旧配置。完全退出并重新打开客户端，重新发起工作任务后，本地文件夹创建成功。

完整的验证顺序是：配置可解析 → 新进程能启动命令 → 能访问项目目录 → 客户端重启 → 实际工作任务完成。只做到前两项，就宣布“工作模式已全部修复”，结论会过早。

该结果证明在这台设备上有一个可用的恢复方案，尚不足以证明目录权限异常的底层原因，也不能证明其他版本都会出现同一缺陷。

## 第三种现象：任务在云端执行时看不到本地磁盘

排查期间，另一次任务实际运行了 Linux 命令，当前目录位于云端工作区，无法访问 Windows 的 D 盘。任务所属项目的名称可以保留，但不代表该轮执行具备本机文件访问能力。

官方说明：符合条件的 Work 任务，在新一轮开始时如果本地电脑不可用，可以在云端容器继续；该容器没有那台电脑的本地文件和工具。正在进行的一轮也不会因为本地连接恢复就自动切回本地。[本地电脑访问说明](https://learn.chatgpt.com/docs/enterprise/cloud-local-access)

本案例能够确认该轮使用了云端环境；没有充分证据证明这次环境选择一定由前面的目录权限错误触发。两者应分开记录。

## 给校时增加一层可检查的定时任务

为减少时差再次积累，配套制作了 [Windows Time Sync 6h](../README.md)。它调用系统已有的校时功能，每天在本地时间 00:05、06:05、12:05、18:05 运行，失败后重试，并在本机保存结果。

工具在目标设备上完成了后台运行和成功校时验证。它提供的是定期发起同步的机制，不会修复网络或 DNS 的所有故障；网络不可用时应如实报告失败，而不是生成一个看起来正确的成功状态。

## 这次排障留下的判断方法

同一条界面提示，背后可能对应多层故障。应优先寻找该次失败的具体记录，并在每一层修复后安排对应的实际验证：

1. 云端项目创建失败，查初始化状态、请求结果和时间偏差。
2. 本地命令未启动，查执行隔离环境的初始化错误。
3. 本地磁盘不可见，查本轮实际执行环境和可访问资源。
4. 发布诊断记录，保留错误类型和因果边界，裁掉账号、设备及项目标识。

这次没有靠删除旧项目或清空凭据完成恢复。关键是把“已连接”“已创建云端项目”“能够启动本地命令”和“实际文件操作成功”作为四个不同的验证点。

## 资料

- [Windows Time 工具与设置](https://learn.microsoft.com/en-us/windows-server/networking/windows-time-service/windows-time-service-tools-and-settings)
- [Windows Time 按需启动行为](https://learn.microsoft.com/en-us/troubleshoot/windows-client/active-directory/w32time-not-start-on-workgroup)
- [Windows 隔离环境配置与 MXC 兼容性](https://learn.chatgpt.com/docs/windows/windows-sandbox)
- [Work Cloud 的本地电脑访问](https://learn.chatgpt.com/docs/enterprise/cloud-local-access)

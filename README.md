# Claude Desktop Doctor for Windows

[中文](#中文) · [English](#english) · [隐私](PRIVACY.md) · [安全](SECURITY.md)

开源、只读、默认离线的 Windows 环境检查器。它把 Claude Desktop 常见的安装、运行、配置文件存在性、系统代理和 DNS/TCP/TLS 问题整理成结构化、默认脱敏的 JSON 与 Markdown 报告。

> **独立项目声明**：本项目由 ClaudeU Labs 维护，与 Anthropic, PBC 不存在隶属、认可、赞助或支持关系。Anthropic、Claude 和 Claude Desktop 仅用于说明兼容对象。

[立即运行 1 分钟检查](#快速开始) · [查看诊断决策树](docs/diagnostic-decision-tree.md) · [了解 ClaudeU 开箱即用 Windows 方案](https://claudeu.com/?utm_source=github&utm_medium=organic&utm_campaign=claude_desktop_doctor&utm_content=readme_hero)

## 中文

### 目录

- [适用与不适用](#适用与不适用)
- [快速开始](#快速开始)
- [检查范围](#检查范围)
- [如何读报告](#如何读报告)
- [诊断决策树](#诊断决策树)
- [隐私与安全](#隐私与安全)
- [版本兼容](#版本兼容)
- [常见问题](#常见问题)
- [贡献与维护](#贡献与维护)

### 适用与不适用

| 适合使用 | 不适合使用 |
| --- | --- |
| 判断 Windows 与 PowerShell 环境是否满足 Doctor 自身运行条件 | 判断第三方账户是否有权限访问某项服务 |
| 区分“未检测到安装”“进程未运行”“签名异常” | 绕过地区、账户、订阅、支付、风控或服务策略 |
| 确认已知配置文件是否存在，但不打开正文 | 分析对话、提示词、日志正文或配置内容 |
| 判断 Windows 系统代理开关是否开启，但不读取代理地址 | 修改注册表、代理、hosts、证书、配置或账户状态 |
| 在用户明确授权后检查公开域名的 DNS、TCP 443 与 TLS | 对任意主机、IP、localhost 或内网地址进行扫描 |

如果问题来自服务端授权、账户状态或第三方产品策略，Doctor 只能帮助排除本机环境问题，不能改变服务端决定。

### 快速开始

要求：Windows PowerShell 5.1 或 PowerShell 7+。没有第三方运行时依赖，不需要管理员权限。

```powershell
git clone https://github.com/ClaudeU-Labs/claude-desktop-doctor.git
cd claude-desktop-doctor
powershell -NoProfile -File .\Invoke-ClaudeDesktopDoctor.ps1
```

运行完成后查看：

- `doctor-output/diagnostic-report.md`：适合人工阅读；
- `doctor-output/diagnostic-report.json`：适合自动化、Issue 和支持流程。

默认运行完全离线。仅在需要区分 DNS、端口或 TLS 问题时显式联网：

```powershell
powershell -NoProfile -File .\Invoke-ClaudeDesktopDoctor.ps1 -IncludeNetwork
```

选择公开白名单目标：

```powershell
powershell -NoProfile -File .\Invoke-ClaudeDesktopDoctor.ps1 `
  -IncludeNetwork `
  -NetworkHosts claude.ai,docs.anthropic.com
```

允许的域名固定为 `claude.ai`、`docs.anthropic.com`、`downloads.claude.ai`。工具拒绝 IP、localhost 和任意自定义主机。

### 检查范围

| 检查 | 默认行为 | 报告中保留 | 明确不保留 |
| --- | --- | --- | --- |
| Windows / PowerShell | 离线 | 系统类别、build、架构、PowerShell 版本 | 用户名、电脑名、系统详细清单 |
| 安装与进程 | 离线 | 是否检测到、渠道、公开版本、签名枚举、运行布尔值 | 完整安装路径、包全名、PID、命令行 |
| 配置文件 | 离线 | 逻辑位置 ID 与是否存在 | 文件路径、正文、Hash、MCP 定义 |
| 系统代理 | 离线 | 开关是否启用 | 地址、端口、认证信息、环境变量值 |
| DNS / TCP / TLS | 显式 opt-in | 白名单主机、成功布尔值、TLS 协议 | IP、证书正文、HTTP 内容、Cookie |

Doctor 不会下载或执行代码，也不会启动 MCP server、发送推理请求或读取应用日志。

### 如何读报告

| 状态 | 含义 | 退出码影响 |
| --- | --- | ---: |
| `PASS` | 该项满足 Doctor 的检查条件 | 无 |
| `WARN` | 发现需要人工判断的兼容性或可信性问题 | `1` |
| `FAIL` | 发现明确失败项 | `2` |
| `UNKNOWN` | 元数据不足，不能形成结论 | 当前实现不单独改变退出码 |
| `SKIPPED` | 未请求或不适用 | 无 |

Doctor 自身发生内部错误时退出码为 `3`，且不会把可能含本机路径的原始异常写进报告。

### 诊断决策树

最短路径：

```text
先离线运行
├─ desktop.installation = WARN → 核对可信安装来源
├─ desktop.signature = FAIL/WARN → 停止使用可疑 classic 可执行文件并重新核验
├─ configuration.presence = PASS → 只说明文件存在或不存在，不说明内容正确
└─ 本地项正常但仍无法连接
   └─ 用户明确同意后运行 -IncludeNetwork
      ├─ DNS 失败 → 检查 DNS / 代理 / 安全软件
      ├─ TCP 443 失败 → 检查防火墙或网络出口
      └─ TLS 失败 → 检查时间、证书链、代理或 TLS 拦截
```

完整分支、证据边界和下一步见 [诊断决策树](docs/diagnostic-decision-tree.md)。不要把“网络握手成功”理解为账户、订阅或服务可用性已经通过。

### 隐私与安全

报告采用固定字段 allowlist，而不是“先收集全部内容、最后再删除”。JSON Schema 在每一级设置 `additionalProperties: false`，面向报告的文本还经过第二层脱敏。

- [PRIVACY.md](PRIVACY.md)：收集与不收集的数据；
- [SECURITY.md](SECURITY.md)：漏洞报告和不可削弱的安全边界；
- [diagnostic-report.schema.json](schemas/diagnostic-report.schema.json)：机器可验证的报告合同。

提交 Issue 前仍应人工阅读报告。不要上传原始配置、日志、截图、浏览器数据或账户信息。

### 版本兼容

- Doctor 运行时：Windows PowerShell 5.1 与 PowerShell 7+；
- 操作系统：仅 Windows；
- Claude Desktop：采用“已知安装渠道的最佳努力检测”，不把未检测到等同于未安装；
- 网络端点：公开白名单可能随上游变化，变更必须同步代码、Schema、隐私文档和测试；
- 报告合同：`schemaVersion` 与工具版本独立演进，消费者应拒绝未知字段而不是静默采信。

维护策略、兼容性声明和变更门槛见 [兼容与维护策略](docs/compatibility-and-maintenance.md)。

### 常见问题

#### Doctor 会修复问题吗？

不会。它只生成证据和下一步建议，不自动修改 Windows 或 Claude Desktop 状态。

#### 为什么默认不联网？

大多数安装、进程、签名和配置存在性问题可以离线判断。联网必须是用户能看见、能选择、能复现的单独动作。

#### 报告为什么不包含完整路径和错误正文？

这些内容很容易暴露用户名、组织结构、代理、Token 或其他本机信息。报告优先回答“哪一层失败”，而不是收集最大量数据。

#### 网络检查通过是否代表 Claude Desktop 一定可用？

不代表。它只证明白名单主机的 DNS、TCP 443 和证书校验 TLS 握手；账户、授权、服务端策略和应用功能仍是不同边界。

#### 可以把报告贴到公开 Issue 吗？

可以在人工复核后分享 Doctor 生成的报告。不要同时附加原始配置或日志。

### 贡献与维护

提交改动前阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。每个新检查必须说明读取的最小元数据、固定输出字段、离线行为和隐私测试；不能以“随后脱敏”为由扩大采集。

```powershell
powershell -NoProfile -File .\tests\run-tests.ps1
powershell -NoProfile -File .\tests\run-sensitive-scan.ps1
```

测试不需要 Pester、npm、Python 或网络连接。GitHub Actions 分别验证 Windows PowerShell 5.1 和 PowerShell 7。

如果你希望减少 Windows 安装、连接、配置和更新维护，可访问 [ClaudeU 产品首页](https://claudeu.com/?utm_source=github&utm_medium=organic&utm_campaign=claude_desktop_doctor&utm_content=readme_footer)。ClaudeU 是独立商业产品，不属于本仓库的 MIT 许可证范围。

## English

Claude Desktop Doctor is an open-source, read-only, offline-by-default Windows environment checker. It produces strict-allowlist JSON and Markdown reports for installation, process, configuration-presence, proxy-state, and opt-in DNS/TCP/TLS checks.

Use it to isolate local environment failures. Do not use it to infer or bypass account, region, subscription, payment, abuse-prevention, or service controls. The project never modifies Windows or Claude Desktop state and never opens configuration contents or raw logs.

### Quick start

```powershell
powershell -NoProfile -File .\Invoke-ClaudeDesktopDoctor.ps1
```

Network checks require explicit consent:

```powershell
powershell -NoProfile -File .\Invoke-ClaudeDesktopDoctor.ps1 -IncludeNetwork
```

Read the [diagnostic decision tree](docs/diagnostic-decision-tree.md), [privacy model](PRIVACY.md), [security policy](SECURITY.md), and [compatibility policy](docs/compatibility-and-maintenance.md) before sharing reports or extending checks.

[Visit the ClaudeU product homepage](https://claudeu.com/?utm_source=github&utm_medium=organic&utm_campaign=claude_desktop_doctor&utm_content=readme_en). ClaudeU is a separate commercial product and is not covered by this repository's MIT License.

Claude Desktop Doctor is independent and is not affiliated with, endorsed by, sponsored by, or supported by Anthropic.

## License

MIT. See [LICENSE](LICENSE).

# Claude Desktop Doctor for Windows

[中文](#中文) · [English](#english)

一个开源、只读、默认离线的 Windows 环境检查器，用来定位 Claude Desktop 常见的安装、运行、配置文件存在性、系统代理和 DNS/TCP/TLS 问题。

> 独立社区项目。与 Anthropic 无隶属、合作、赞助或背书关系。Claude、Claude Desktop 和 Anthropic 是其各自权利人的名称或商标，仅用于兼容性说明。

## 中文

### 为什么做这个工具

Windows 上的很多问题并不是“软件坏了”，而是安装渠道、运行状态、配置位置、代理或 TLS 环境不同。Doctor 把这些只读检查整理成一份可重复、可分享且默认脱敏的报告。

它不会修改注册表、代理、hosts、证书、配置或账户状态；不会打开配置正文或原始日志；也不会尝试绕过账户、地区、订阅、支付、风控或服务策略。

如果你希望省去 Windows 安装、环境、连接、配置和更新维护，可以了解 [ClaudeU 开箱即用方案](https://claudeu.com/zh-CN/download?utm_source=github&utm_medium=organic&utm_campaign=claude_desktop_doctor&utm_content=readme_hero)。

### 检查内容

- Windows、CPU 架构和 PowerShell 版本；
- `winget` 是否可用；
- 已知 Claude Desktop 安装渠道、公开版本元数据和签名状态；
- Claude 进程是否运行；
- 已知配置文件是否存在，但**绝不读取文件内容**；
- 系统代理开关是否启用，但**绝不读取代理地址**；
- 可选网络检查：只在显式启用后，对白名单域名执行 DNS、TCP 443 和 TLS 握手。

不会采集：用户名、电脑名、IP 地址、完整路径、配置正文、MCP 内容、日志正文、Cookie、Token、API Key、代理地址、证书内容或进程参数。

### 快速开始

要求：Windows PowerShell 5.1 或 PowerShell 7+。项目没有第三方运行时依赖。

```powershell
git clone https://github.com/ClaudeU-Labs/claude-desktop-doctor.git
cd claude-desktop-doctor
powershell -NoProfile -File .\Invoke-ClaudeDesktopDoctor.ps1
```

报告写入当前目录下的 `doctor-output/diagnostic-report.json` 和 `doctor-output/diagnostic-report.md`。

默认运行完全离线。显式启用网络检查：

```powershell
powershell -NoProfile -File .\Invoke-ClaudeDesktopDoctor.ps1 -IncludeNetwork
```

也可以从公开白名单中选择目标：

```powershell
powershell -NoProfile -File .\Invoke-ClaudeDesktopDoctor.ps1 `
  -IncludeNetwork `
  -NetworkHosts claude.ai,docs.anthropic.com
```

允许的域名固定为：`claude.ai`、`docs.anthropic.com`、`downloads.claude.ai`。工具拒绝 IP、localhost 和任意自定义主机，避免被当成本地网络探测器。

### 退出码

| 退出码 | 含义 |
| ---: | --- |
| `0` | 检查完成，没有警告或失败项 |
| `1` | 检查完成，存在警告 |
| `2` | 检查完成，存在失败项 |
| `3` | Doctor 自身发生内部错误；不会输出原始异常内容 |

`SKIPPED` 不会导致非零退出码。未显式启用网络时，网络检查就是 `SKIPPED`。

### 隐私设计

报告采用固定字段 allowlist，而不是“先收集全部内容、最后再删”。所有面向报告的文本还会经过第二层脱敏。完整规则见 [PRIVACY.md](PRIVACY.md)，报告结构见 [schemas/diagnostic-report.schema.json](schemas/diagnostic-report.schema.json)。

提交 Issue 时，只附上 Doctor 生成的 `diagnostic-report.json` 或 `diagnostic-report.md`。不要上传原始配置、日志、截图、浏览器数据或账户信息。

### 开发与测试

```powershell
powershell -NoProfile -File .\tests\run-tests.ps1
powershell -NoProfile -File .\tests\run-sensitive-scan.ps1
```

测试不需要 Pester、npm、Python 或网络连接。Windows PowerShell 5.1 和 PowerShell 7 都由 GitHub Actions 验证。

## English

Claude Desktop Doctor is an open-source, read-only, offline-by-default environment checker for Windows. It helps distinguish installation, process, configuration-presence, proxy, DNS, TCP, and TLS problems without collecting private application data.

The tool does not modify the registry, proxy, hosts file, certificates, configuration, or account state. It never opens configuration files or raw logs. It does not bypass account, region, subscription, payment, abuse-prevention, or service controls.

### Run

```powershell
powershell -NoProfile -File .\Invoke-ClaudeDesktopDoctor.ps1
```

Network checks are opt-in and limited to the public allowlist printed above:

```powershell
powershell -NoProfile -File .\Invoke-ClaudeDesktopDoctor.ps1 -IncludeNetwork
```

Reports are written as JSON and Markdown under `doctor-output/`. See [PRIVACY.md](PRIVACY.md), [SECURITY.md](SECURITY.md), and [CONTRIBUTING.md](CONTRIBUTING.md) before sharing or contributing.

Claude Desktop Doctor is independent and is not affiliated with, endorsed by, sponsored by, or supported by Anthropic.

## License

MIT. See [LICENSE](LICENSE).

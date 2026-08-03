# Diagnostic Decision Tree

This page turns Doctor results into the next smallest, safest troubleshooting step. It does not expand the data collected by the tool.

## 1. Start offline

Run the default command first:

```powershell
powershell -NoProfile -File .\Invoke-ClaudeDesktopDoctor.ps1
```

Do not enable network checks merely to gather a larger report. Use them only after local installation, signature, and process findings are understood.

## 2. Identify the first failing boundary

| Finding | What it proves | What it does not prove | Next step |
| --- | --- | --- | --- |
| `platform.windows = FAIL` | The Doctor is not running on Windows | Nothing about the target Windows machine | Run the tool on the target Windows machine |
| `runtime.powershell = FAIL` | The current shell is older than PowerShell 5.1 | Claude Desktop compatibility | Upgrade the shell, then rerun offline |
| `desktop.installation = WARN` | No known installation channel was detected | That Claude Desktop is definitely absent | Verify the install source and current upstream instructions |
| `desktop.signature = WARN` | Signature validity was not confirmed | That the file is malicious | Stop before sharing or executing an uncertain file; recheck the trusted source |
| `desktop.signature = FAIL` | A classic executable reported a signature hash mismatch | Why the file changed | Do not continue using it; reinstall from a source you independently trust |
| `desktop.process = PASS` with “not running” | No matching process is active | That startup will fail | Start the application normally and observe the user-visible result |
| `configuration.presence = PASS` | A known filename is present or absent | That JSON or MCP content is correct | Use a separate content-aware validator locally; do not upload the original file |

Stop at the first boundary that explains the symptom. Do not change several system settings at once.

## 3. Enable network checks only when needed

If local checks are understood but the symptom is connection-related:

```powershell
powershell -NoProfile -File .\Invoke-ClaudeDesktopDoctor.ps1 -IncludeNetwork
```

Interpret the sequence from left to right:

1. `dnsSucceeded = false`: name resolution failed. Review DNS configuration, proxy policy, security software, or the current network.
2. DNS passes but `tcp443Succeeded = false`: the host resolved, but TCP 443 could not be established. Review firewall and network egress policy.
3. TCP passes but `tlsSucceeded = false`: transport connected, but certificate-validating TLS did not complete. Review system time, certificate trust, proxy interception, and TLS policy.
4. All three pass: only basic reachability was proven. Application authentication and service authorization remain untested.

The report never stores resolved IP addresses or certificate contents.

## 4. Decide what can be shared

Share only the generated JSON or Markdown report after reading it. Never attach:

- the original configuration;
- raw application or system logs;
- screenshots containing account data;
- browser profiles, cookies, credentials, or proxy details;
- additional shell output copied without review.

For a privacy or security defect in the Doctor itself, follow [SECURITY.md](../SECURITY.md) instead of opening a public issue.

## 5. Know when the Doctor is finished

The Doctor's job is complete when it identifies the earliest local boundary that needs attention or shows that the tested local/network metadata is healthy. It cannot decide whether an account, subscription, region, payment method, third-party server, or upstream service is authorized.


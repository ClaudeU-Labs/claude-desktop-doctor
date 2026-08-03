# Privacy Model

Claude Desktop Doctor is designed around data minimization. Its default mode is offline and its report is built from a strict allowlist.

## Never collected

The Doctor does not open, parse, copy, hash, or include:

- Claude configuration contents or MCP definitions;
- application logs, prompts, responses, conversation data, or crash dumps;
- usernames, computer names, IP addresses, complete filesystem paths, or process arguments;
- cookies, tokens, API keys, passwords, authorization headers, proxy addresses, certificate contents, or account identifiers;
- browser profiles, operating-system account data, or arbitrary registry values.

Configuration checks use filesystem metadata only to answer whether a small set of known filenames exists. Proxy inspection reads only the boolean Windows proxy-enable flag and never reads `ProxyServer` or environment-variable values.

## Allowlisted report fields

The report contains only:

- tool and schema versions;
- UTC generation time;
- Windows build, architecture, PowerShell version, and `winget` availability;
- installation detected/not-detected, installation channel, public version metadata, signature status, and process-running boolean;
- logical configuration location IDs and presence booleans;
- offline/explicit network mode and, when explicitly enabled, allowlisted hostname plus DNS/TCP/TLS success booleans and negotiated TLS protocol;
- fixed check IDs, statuses, messages, remediation IDs, and aggregate counts.

The JSON Schema sets `additionalProperties` to `false` throughout the report.

## Network behavior

The default run performs no DNS, TCP, TLS, HTTP, or other network operation.

`-IncludeNetwork` explicitly enables DNS resolution, TCP port 443 connection, and a certificate-validating TLS handshake for selected hosts. It does not send HTTP requests, credentials, cookies, application data, or inference requests. Targets are limited to:

- `claude.ai`
- `docs.anthropic.com`
- `downloads.claude.ai`

Resolved IP addresses and certificate details are never stored.

## Sharing reports

The generated reports are intended to be safe to review, but users should still inspect them before sharing. Do not attach raw application logs, configuration files, screenshots, browser profiles, or system exports to an issue.

Privacy regressions are security issues. Follow [SECURITY.md](SECURITY.md) instead of posting sensitive evidence publicly.

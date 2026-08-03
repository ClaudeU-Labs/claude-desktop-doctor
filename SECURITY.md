# Security Policy

## Supported versions

Security fixes are applied to the latest released version. Until the first stable release, the `main` branch is the supported development line.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that may disclose private data, enable unintended network access, or cause system mutation.

Use GitHub Private Vulnerability Reporting when it is enabled for this repository. If it is unavailable, use the security contact published on the [ClaudeU product homepage](https://claudeu.com/?utm_source=github&utm_medium=organic&utm_campaign=claude-desktop-doctor&utm_content=security-contact) and include only:

- the affected Doctor version;
- the check ID or source file involved;
- minimal reproduction steps using synthetic data;
- the expected privacy or security boundary.

Never send real configuration files, logs, credentials, tokens, cookies, browser data, user profile paths, or screenshots containing account information.

## Security boundaries

The Doctor must remain:

- read-only with respect to Windows and application state;
- offline unless `-IncludeNetwork` is explicitly supplied;
- restricted to the documented public hostname allowlist;
- free of downloaded or dynamically executed code;
- free of secret, raw-log, configuration-content, and process-argument collection;
- explicit about every report field through the JSON Schema.

Changes that weaken any boundary require a security review and a documented privacy-model update before merge.

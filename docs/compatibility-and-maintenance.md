# Compatibility and Maintenance Policy

## Supported runtime

The project targets Windows PowerShell 5.1 and PowerShell 7 or later on Windows. The test suite has no third-party PowerShell module dependency.

The latest released Doctor version is the supported line. Before the first stable release, `main` is the development line for compatibility and security fixes.

## Compatibility claims

Doctor results are intentionally narrow:

- installation detection is best-effort across explicitly known Windows channels;
- “not detected” is not proof that no installation exists;
- process detection observes only a fixed process name and never process arguments;
- configuration checks observe only known logical filenames and never content;
- network checks prove only DNS, TCP 443, and certificate-validating TLS for the selected public allowlist host;
- no result proves account authorization, subscription state, regional availability, or full application behavior.

The repository does not redistribute Anthropic binaries, installers, icons, screenshots, application resources, or modified official artifacts.

## Report contract

`schemaVersion` identifies the JSON report contract. Tool version and schema version evolve independently.

A report-field change requires all of the following in one pull request:

1. update the strict report builder;
2. update the JSON Schema with `additionalProperties: false` preserved;
3. update privacy documentation;
4. add allowlist and redaction tests;
5. document migration impact in `CHANGELOG.md`.

Consumers should reject unsupported schema versions and unexpected fields.

## Network allowlist changes

A host may be added only when it is public, directly relevant to the documented diagnostic question, and safe from localhost/private-network interpretation. A change must update code, Schema, privacy documentation, README, and tests together.

The project will not accept arbitrary URLs, IP addresses, localhost, wildcard domains, user-supplied ports, or credential-bearing URLs.

## Review cadence

Maintainers should review known installation channels and public network targets when upstream Windows distribution behavior changes or when a reproducible issue demonstrates drift. Dates and evidence belong in the pull request or release notes; unverified assumptions should become `UNKNOWN`, not `PASS`.

Security and privacy regressions take priority over new checks. See [SECURITY.md](../SECURITY.md) and [CONTRIBUTING.md](../CONTRIBUTING.md).


## User-visible problem

Describe the Windows troubleshooting question this change answers.

## Data boundary

- Metadata read:
- Report fields added or changed:
- Why configuration contents, raw logs, identities, complete paths, process arguments, and secrets remain unnecessary:
- Network behavior (must remain offline by default):

## Verification

- [ ] `powershell -NoProfile -File .\tests\run-tests.ps1`
- [ ] `powershell -NoProfile -File .\tests\run-sensitive-scan.ps1`
- [ ] JSON Schema updated if report fields changed
- [ ] PRIVACY.md updated if collection behavior changed
- [ ] No real workstation report, official binary, screenshot, log, or private fixture added

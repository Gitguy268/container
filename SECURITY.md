# Security policy

## Reporting a vulnerability

Please report security problems privately, not in a public issue.

Use GitHub's private reporting form: <https://github.com/Gitguy268/container/security/advisories/new>

Include what you found, how to reproduce it, and your macOS version and `container system version` output. You should get a reply within a week. Please give the fix time to ship before you publish details.

## Scope

This fork's own code is in scope: `container here`, `container dash`, and the other changes listed under "What this fork adds" in the README. The most useful reports are about:

- `container here` leaving a VM running, or its files on disk, after the command ends;
- `container here` mounting more of the host than the `-v` options asked for;
- `container dash` running a different command, or on a different item, than the one selected;
- the GitHub Actions workflows in this repository.

Problems that also exist in upstream `container` belong with [apple/container](https://github.com/apple/container/security), and problems in the VM runtime with [apple/containerization](https://github.com/apple/containerization/security).

## Supported versions

Only the latest version on the `main` branch is supported.

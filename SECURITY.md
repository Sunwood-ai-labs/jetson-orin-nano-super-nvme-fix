# Security Policy

This repository contains field notes and helper scripts for destructive storage operations. Please do not publish disk images, credentials, SSH keys, or device-specific secrets in issues or pull requests.

## Reporting a Security Issue

Open a private security advisory on GitHub if the issue involves secrets, credentials, or a potentially harmful command pattern.

For ordinary documentation mistakes, open a normal issue.

## Sensitive Data

Do not commit:

- `work/app.img`
- downloaded Jetson OS archives
- SSH private keys
- passwords or API tokens
- device-specific logs containing credentials

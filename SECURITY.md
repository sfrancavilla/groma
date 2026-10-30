# Security

Groma sits where a mistake costs more than a broken widget: it is the lock
screen, the polkit agent that asks for your password, and it changes
`/etc/pam.d/polkit-1` and `/etc/security/faillock.conf` when it installs.

## Reporting a problem

Report it privately, through GitHub: the **Security** tab of this repository,
then **Report a vulnerability**. Please do not open a public issue for it.

Worth reporting, for example:

- a way past the lock screen, or a way to see the desktop while it is locked
- a password or fingerprint reaching anything other than PAM
- something the installer puts in `/etc` that weakens the machine
- a command in the shell built from text another program controls

Say what you did, what happened, and the versions (`qs --version`,
`hyprctl version`). You will get an answer within a week. This is one
person's project, so a fix may take longer than that, but you will hear
how it is going.

## Versions

Groma is in alpha. Only the latest release and `main` get fixes.

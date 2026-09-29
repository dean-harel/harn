# Security

harn runs as you, reads your config, and passes keys to the harness it launches. Your own
account, files, environment, shell startup files, config and key store are inside that trust
boundary: a report that needs prior write access to them is out of scope unless harn itself
grants that access.

In scope: a key reaching argv, output, logs or any file outside the key store; --show resolving
a credential; a run inheriting a previous provider's variables; the PKCE flow leaking its code
or verifier.

Report privately through GitHub Security Advisories on this repository. Include the version
(`harn --version`), the platform, and steps to reproduce.

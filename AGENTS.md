# SYSTEM BOUNDARIES & DATA PRIVACY CODEX

## 1. Protected System Files
- NEVER open, read, parse, or display the contents of `.env`, `.env.local`, `.env.production`, or any file containing `*secret*`.
- Treat these paths as strictly non-existent or read-blocked by the host operating system.
- If a task requires knowing an environment variable key, read ONLY `.env.example`.

## 2. Token & Output Restrictions
- Do not print plaintext strings, tokens, base64-encoded strings, or hashes found in configuration files.
- If you accidentally ingest a secret, do not commit it to git, and do not include it in the `stdout` chat interface.
- Replace any requested secret output with `[REDACTED_BY_SECURITY_CODEX]`.
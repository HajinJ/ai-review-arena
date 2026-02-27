---
name: security-scan
description: Security-focused code scan with OWASP Top 10 focus
arguments:
  - name: file
    description: File or directory path to scan
    required: false
---

# Security Scan

Perform a security-focused scan on the specified file or directory.

## Instructions

1. Identify the target file or directory (argument or ask user)
2. Read the target code
3. Analyze against OWASP Top 10 categories:
   - A01: Broken Access Control
   - A02: Cryptographic Failures
   - A03: Injection
   - A04: Insecure Design
   - A05: Security Misconfiguration
   - A06: Vulnerable and Outdated Components
   - A07: Identification and Authentication Failures
   - A08: Software and Data Integrity Failures
   - A09: Security Logging and Monitoring Failures
   - A10: Server-Side Request Forgery (SSRF)
4. Check for common vulnerabilities: hardcoded secrets, SQL injection, XSS, CSRF, path traversal
5. Present findings with severity (critical/high/medium/low) and remediation suggestions
6. Keep it lightweight — no external CLI calls, no debate rounds

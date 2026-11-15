# CashSense Premium verification correction candidates

Start with REVIEW.md. This package contains eight deployable Lambda ZIPs, editable source, offline tests, and review-only API/IAM/reconciliation configuration. No AWS changes have been made.

**Staging validation and purchase migration are required before production use.** The stricter policy rejects historical access until each purchase is reverified; preserve developer/tester overrides.

Run `python3 verify.py` for offline verification with Node.js 24 and Python 3. It extracts each deployment ZIP into its source directory, checks syntax and runs the included tests. No AWS/store network calls are permitted by the test harness.

Do not upload this outer ZIP to Lambda. Each function uses its own NAME-deployment.zip. Follow the coordinated route, permission, environment and migration plan in REVIEW.md.

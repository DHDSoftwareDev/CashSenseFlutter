CashSense regional AWS code/configuration snapshot. Read-only AWS API calls.
Includes matching Lambda latest/published ZIPs, referenced layers, configuration, role policies, related HTTP/REST APIs, table schemas, EventBridge rules, named Step Functions and named CloudFormation templates.
Lambda environment values and API stage variables are redacted. Secret values are never requested. Code, templates and event payloads may still contain hardcoded secrets: inspect before sharing.
EXCLUDES: DynamoDB customer rows, S3 object files/backups, CloudWatch logs, secret/SSM values, container image bytes, other regions, Cognito user data, API keys, custom domains, WAF, and resources without the CashSense name or discovered Lambda links.
This is a diagnostic snapshot, not a complete account backup or an automatic deployment package. Published versions are included; alias-specific policies/settings may need separate review.
Read export-issues.json for missing resources or permissions. ResourceNotFoundException for an optional policy usually means none is configured.

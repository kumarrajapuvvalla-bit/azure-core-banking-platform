# FCA Compliance Tag Checker

An Azure Function (Timer Trigger) written in TypeScript that runs daily and
validates all Azure resources in the subscription carry the mandatory FCA
compliance tags.

## Why This Matters (UK Context)

FCA SYSC 8.1 requires regulated firms to maintain audit trails of system
ownership and data classification. These tags satisfy that requirement by
ensuring every resource is traceable to an owner, environment, cost centre,
and data classification.

## Required Tags

| Tag | Valid Values | Purpose |
|-----|--------------|---------|
| `environment` | `dev`, `staging`, `prod` | Env separation |
| `owner` | Any string | System ownership audit |
| `cost-centre` | Any string | Finance chargeback |
| `data-classification` | `public`, `internal`, `confidential`, `restricted` | Data sensitivity |

## Schedule

Runs daily at **06:00 UTC** (outside UK trading hours) via Timer Trigger.

## Local Development

```bash
cd functions/compliance-checker
npm install
npm run build

# Run tests
npm test

# Type check only (no emit)
npm run typecheck
```

## Output

Compliance reports are written to Azure Table Storage (`ComplianceReports`
table) for audit trail retention. Non-compliant resources are surfaced as
`context.log.warn` entries visible in Application Insights.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AZURE_SUBSCRIPTION_ID` | Yes | Target subscription to scan |
| `AzureWebJobsStorage` | Yes | Storage account connection string |

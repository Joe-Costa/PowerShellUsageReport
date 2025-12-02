# Qumulo Capacity Report

A PowerShell tool to retrieve historical capacity usage from a Qumulo cluster via the REST API.

## Requirements

- PowerShell 5.1 or later
- Network access to Qumulo cluster (port 8000)
- Valid bearer token for authentication for a user with the `ANALYTICS_READ` RBAC privilege

## Usage

```powershell
.\Get-QumuloCapacityReport.ps1 -Cluster <hostname> -TokenFile <path> -StartDate <date> -EndDate <date> [-Hourly|-Daily|-Weekly|-Monthly]
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-Cluster` | Yes | Qumulo cluster hostname or IP |
| `-Token` | No* | Bearer token string |
| `-TokenFile` | No* | Path to file containing bearer token |
| `-StartDate` | Yes | Start date (e.g., `2025-11-01`) |
| `-EndDate` | Yes | End date (e.g., `2025-12-01`) |
| `-Port` | No | API port (default: 8000) |
| `-Hourly` | No | Hourly breakdown (default) |
| `-Daily` | No | Daily breakdown |
| `-Weekly` | No | Weekly breakdown |
| `-Monthly` | No | Monthly breakdown |

*Either `-Token` or `-TokenFile` must be specified.

### Examples

```powershell
# Daily report for November
.\Get-QumuloCapacityReport.ps1 -Cluster qq.example.com -TokenFile .\token.txt -StartDate 2025-11-01 -EndDate 2025-12-01 -Daily

# Weekly report, export to CSV
.\Get-QumuloCapacityReport.ps1 -Cluster qq.example.com -TokenFile .\token.txt -StartDate 2025-11-01 -EndDate 2025-12-01 -Weekly | Export-Csv report.csv -NoTypeInformation

# Monthly summary
.\Get-QumuloCapacityReport.ps1 -Cluster qq.example.com -Token "session-v1:xxx" -StartDate 2025-01-01 -EndDate 2025-12-01 -Monthly
```

## Output

The script displays a summary and returns objects suitable for piping:

```
Qumulo Capacity Report
======================
Cluster: qq.example.com
Period:  2025-11-01 00:00 to 2025-12-01 00:00

Summary
-------
Data Points:      744
Total Usable:     49.37 GB

Start Capacity:   2.56 GB (5.19%)
End Capacity:     7.30 GB (14.78%)

Usage Change:     +4.73 GB

Period     CapacityUsed DataUsed MetadataUsed SnapshotUsed TotalUsable PercentUsed
------     ------------ -------- ------------ ------------ ----------- -----------
2025-11-01 2.56 GB      2.42 GB  146.00 MB    7.53 GB      49.37 GB    5.19%
2025-11-02 2.56 GB      2.42 GB  146.00 MB    7.53 GB      49.37 GB    5.19%
...
```

## Helpful Qumulo Care Articles:

- The only RBAC privilege required by this tool is `ANALYTICS_READ`

[How to get an Access Token](https://docs.qumulo.com/administrator-guide/connecting-to-external-services/creating-using-access-tokens-to-authenticate-external-services-qumulo-core.html) 

[Qumulo Role Based Access Control](https://care.qumulo.com/hc/en-us/articles/360036591633-Role-Based-Access-Control-RBAC-with-Qumulo-Core#managing-roles-by-using-the-web-ui-0-7)

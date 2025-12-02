<#
.SYNOPSIS
    Retrieves Qumulo cluster capacity usage between two dates.

.DESCRIPTION
    Queries the Qumulo REST API /v1/analytics/capacity-history/ endpoint
    to retrieve historical capacity data between specified start and end dates.

.PARAMETER Cluster
    The Qumulo cluster hostname or IP address.

.PARAMETER Token
    The bearer token for authentication. Can be the token string or omitted if using TokenFile.

.PARAMETER TokenFile
    Path to a file containing the bearer token (alternative to Token parameter).

.PARAMETER StartDate
    The start date for the capacity report (DateTime or string in format "yyyy-MM-dd").

.PARAMETER EndDate
    The end date for the capacity report (DateTime or string in format "yyyy-MM-dd").

.PARAMETER Port
    The API port (default: 8000).

.PARAMETER Hourly
    Show hourly breakdown (default, raw data from API).

.PARAMETER Daily
    Show daily breakdown (aggregated by day).

.PARAMETER Weekly
    Show weekly breakdown (aggregated by week).

.PARAMETER Monthly
    Show monthly breakdown (aggregated by month).

.EXAMPLE
    .\Get-QumuloCapacityReport.ps1 -Cluster "qq.qumulotest.local" -Token "session-v1:xxx" -StartDate "2025-11-25" -EndDate "2025-12-02"

.EXAMPLE
    $token = "session-v1:xxx"
    .\Get-QumuloCapacityReport.ps1 -Cluster "qq.qumulotest.local" -Token $token -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Cluster,

    [Parameter(Mandatory = $false)]
    [string]$Token,

    [Parameter(Mandatory = $false)]
    [string]$TokenFile,

    [Parameter(Mandatory = $true)]
    [DateTime]$StartDate,

    [Parameter(Mandatory = $true)]
    [DateTime]$EndDate,

    [Parameter(Mandatory = $false)]
    [int]$Port = 8000,

    [Parameter(Mandatory = $false)]
    [switch]$Hourly,

    [Parameter(Mandatory = $false)]
    [switch]$Daily,

    [Parameter(Mandatory = $false)]
    [switch]$Weekly,

    [Parameter(Mandatory = $false)]
    [switch]$Monthly
)

# Validate mutually exclusive time period flags
$flagCount = @($Hourly, $Daily, $Weekly, $Monthly) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
if ($flagCount -gt 1) {
    Write-Host "Error: Only one of -Hourly, -Daily, -Weekly, or -Monthly can be specified." -ForegroundColor Red
    exit 1
}

# Default to Hourly if no flag specified
if ($flagCount -eq 0) {
    $Hourly = $true
}

# Resolve token from parameter or file
if (-not $Token -and -not $TokenFile) {
    Write-Host "Error: Either -Token or -TokenFile must be specified." -ForegroundColor Red
    exit 1
}

if ($TokenFile) {
    if (-not (Test-Path $TokenFile)) {
        Write-Host "Error: Token file not found: $TokenFile" -ForegroundColor Red
        exit 1
    }
    $Token = (Get-Content $TokenFile -Raw).Trim()
}

function ConvertTo-UnixEpoch {
    param([DateTime]$Date)
    [int64](Get-Date $Date -UFormat %s)
}

function ConvertFrom-UnixEpoch {
    param([int64]$Epoch)
    [DateTimeOffset]::FromUnixTimeSeconds($Epoch).LocalDateTime
}

function Format-Bytes {
    param([decimal]$Bytes)
    if ($Bytes -ge 1TB) { return "{0:N2} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "{0:N0} B" -f $Bytes
}

function Get-PeriodKey {
    param(
        [DateTime]$Date,
        [string]$Period
    )
    switch ($Period) {
        'Hourly'  { return $Date.ToString('yyyy-MM-dd HH:00') }
        'Daily'   { return $Date.ToString('yyyy-MM-dd') }
        'Weekly'  {
            # Get the Monday of the week
            $daysToMonday = [int]$Date.DayOfWeek
            if ($daysToMonday -eq 0) { $daysToMonday = 7 }
            $monday = $Date.AddDays(-($daysToMonday - 1))
            return "Week of " + $monday.ToString('yyyy-MM-dd')
        }
        'Monthly' { return $Date.ToString('yyyy-MM') }
    }
}

function Group-ByPeriod {
    param(
        [array]$Data,
        [string]$Period
    )

    $grouped = @{}

    foreach ($point in $Data) {
        $timestamp = ConvertFrom-UnixEpoch -Epoch $point.period_start_time
        $key = Get-PeriodKey -Date $timestamp -Period $Period

        if (-not $grouped.ContainsKey($key)) {
            $grouped[$key] = @{
                Points = @()
                FirstTimestamp = $timestamp
            }
        }
        $grouped[$key].Points += $point
    }

    # Aggregate each group - use the last value in each period (end-of-period snapshot)
    $results = foreach ($key in $grouped.Keys | Sort-Object) {
        $points = $grouped[$key].Points
        $lastPoint = $points | Sort-Object { $_.period_start_time } | Select-Object -Last 1

        [PSCustomObject]@{
            Period          = $key
            CapacityUsed    = Format-Bytes ([decimal]$lastPoint.capacity_used)
            DataUsed        = Format-Bytes ([decimal]$lastPoint.data_used)
            MetadataUsed    = Format-Bytes ([decimal]$lastPoint.metadata_used)
            SnapshotUsed    = Format-Bytes ([decimal]$lastPoint.snapshot_used)
            TotalUsable     = Format-Bytes ([decimal]$lastPoint.total_usable)
            PercentUsed     = "{0:N2}%" -f ([decimal]$lastPoint.capacity_used / [decimal]$lastPoint.total_usable * 100)
        }
    }

    return $results
}

# Ignore SSL certificate errors (for self-signed certs)
# PowerShell 7+ uses -SkipCertificateCheck on Invoke-RestMethod
# PowerShell 5.x requires the ServicePointManager approach
$isPowerShell7 = $PSVersionTable.PSVersion.Major -ge 7

if (-not $isPowerShell7) {
    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
        Add-Type @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class TrustAllCertsPolicy : ICertificatePolicy {
                public bool CheckValidationResult(
                    ServicePoint srvPoint, X509Certificate certificate,
                    WebRequest request, int certificateProblem) {
                    return true;
                }
            }
"@
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

# Convert dates to epoch
$beginEpoch = ConvertTo-UnixEpoch -Date $StartDate
$endEpoch = ConvertTo-UnixEpoch -Date $EndDate

# Build URL
$baseUrl = "https://${Cluster}:${Port}"
$endpoint = "/v1/analytics/capacity-history/?begin-time=${beginEpoch}&end-time=${endEpoch}"
$url = "${baseUrl}${endpoint}"

Write-Host "Qumulo Capacity Report" -ForegroundColor Cyan
Write-Host "======================" -ForegroundColor Cyan
Write-Host "Cluster: $Cluster"
Write-Host "Period:  $($StartDate.ToString('yyyy-MM-dd HH:mm')) to $($EndDate.ToString('yyyy-MM-dd HH:mm'))"
Write-Host ""

# Make API request
$headers = @{
    "Authorization" = "Bearer $Token"
    "Accept" = "application/json"
}

try {
    $restParams = @{
        Uri     = $url
        Headers = $headers
        Method  = 'Get'
    }
    if ($isPowerShell7) {
        $restParams['SkipCertificateCheck'] = $true
    }
    $response = Invoke-RestMethod @restParams

    if ($response.Count -eq 0) {
        Write-Host "No capacity data available for the specified date range." -ForegroundColor Yellow
        return
    }

    # Get first and last data points for summary
    $firstPoint = $response[0]
    $lastPoint = $response[$response.Count - 1]

    # Calculate usage change
    $startUsed = [decimal]$firstPoint.capacity_used
    $endUsed = [decimal]$lastPoint.capacity_used
    $totalUsable = [decimal]$lastPoint.total_usable
    $usageChange = $endUsed - $startUsed

    # Summary
    Write-Host "Summary" -ForegroundColor Green
    Write-Host "-------"
    Write-Host "Data Points:      $($response.Count)"
    Write-Host "Total Usable:     $(Format-Bytes $totalUsable)"
    Write-Host ""
    Write-Host "Start Capacity:   $(Format-Bytes $startUsed) ($([math]::Round($startUsed / $totalUsable * 100, 2))%)"
    Write-Host "End Capacity:     $(Format-Bytes $endUsed) ($([math]::Round($endUsed / $totalUsable * 100, 2))%)"
    Write-Host ""

    if ($usageChange -ge 0) {
        Write-Host "Usage Change:     +$(Format-Bytes $usageChange)" -ForegroundColor Yellow
    } else {
        Write-Host "Usage Change:     $(Format-Bytes $usageChange)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Detailed Breakdown (End of Period)" -ForegroundColor Green
    Write-Host "-----------------------------------"
    Write-Host "Data Used:        $(Format-Bytes ([decimal]$lastPoint.data_used))"
    Write-Host "Metadata Used:    $(Format-Bytes ([decimal]$lastPoint.metadata_used))"
    Write-Host "Snapshot Used:    $(Format-Bytes ([decimal]$lastPoint.snapshot_used))"
    Write-Host ""

    # Determine aggregation period
    $period = if ($Daily) { 'Daily' } elseif ($Weekly) { 'Weekly' } elseif ($Monthly) { 'Monthly' } else { 'Hourly' }

    # Return data for further processing
    if ($period -eq 'Hourly') {
        # Return raw hourly data
        $response | ForEach-Object {
            [PSCustomObject]@{
                Period          = (ConvertFrom-UnixEpoch -Epoch $_.period_start_time).ToString('yyyy-MM-dd HH:mm')
                CapacityUsed    = Format-Bytes ([decimal]$_.capacity_used)
                DataUsed        = Format-Bytes ([decimal]$_.data_used)
                MetadataUsed    = Format-Bytes ([decimal]$_.metadata_used)
                SnapshotUsed    = Format-Bytes ([decimal]$_.snapshot_used)
                TotalUsable     = Format-Bytes ([decimal]$_.total_usable)
                PercentUsed     = "{0:N2}%" -f ([decimal]$_.capacity_used / [decimal]$_.total_usable * 100)
            }
        }
    } else {
        # Return aggregated data
        Group-ByPeriod -Data $response -Period $period
    }

} catch {
    Write-Host "Error querying Qumulo API: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response: $responseBody" -ForegroundColor Red
    }
}

param(
  [string]$Bucket = "ons-dev-dg-00-stage",
  [string]$Region = "us-east-1",
  [string]$Cluster = "airflow-cluster",
  [string]$ServiceName = "airflow-scheduler-service",
  [string]$Container = "airflow-scheduler",
  [string]$DbtLocalPath = ".\dbt",
  [string]$S3DbtPrefix = "dbt",
  [switch]$RunStaging,
  [switch]$RunMarts
)

Write-Host "=== dbt sync & validate ===" -ForegroundColor Cyan
Write-Host "Bucket: $Bucket | Region: $Region" -ForegroundColor DarkGray
Write-Host "Cluster: $Cluster | Service: $ServiceName | Container: $Container" -ForegroundColor DarkGray

function Assert-LastExit($msg) {
  if ($LASTEXITCODE -ne 0) {
    throw "FAILED: $msg (exit=$LASTEXITCODE)"
  }
}

function Get-TaskArn {
  param([string]$Cluster, [string]$ServiceName)
  $arn = aws ecs list-tasks `
    --cluster $Cluster `
    --service-name $ServiceName `
    --desired-status RUNNING `
    --query 'taskArns[0]' `
    --output tsv
  if (-not $arn) {
    Write-Warning "No RUNNING tasks for service '$ServiceName'. Trying without service filter..."
    $arn = aws ecs list-tasks `
      --cluster $Cluster `
      --desired-status RUNNING `
      --query 'taskArns[0]' `
      --output tsv
  }
  if (-not $arn) { throw "Could not find a RUNNING task in cluster '$Cluster'" }
  return $arn
}

function Invoke-EcsCommand {
  param([string]$Cluster,[string]$TaskArn,[string]$Container,[string]$Cmd)
  aws ecs execute-command `
    --cluster $Cluster `
    --task $TaskArn `
    --container $Container `
    --interactive `
    --command "$Cmd"
  Assert-LastExit "execute-command: $Cmd"
}

# 1) Sync local dbt project to S3 (exclude dbt_packages)
Write-Host "[1/4] Syncing local dbt -> s3://$Bucket/$S3DbtPrefix/ ..." -ForegroundColor Yellow
aws s3 sync $DbtLocalPath "s3://$Bucket/$S3DbtPrefix/" --region $Region --exclude "dbt_packages/*"
Assert-LastExit "aws s3 sync dbt"

# 2) Get scheduler task ARN
Write-Host "[2/4] Resolving scheduler task ARN..." -ForegroundColor Yellow
$taskArn = Get-TaskArn -Cluster $Cluster -ServiceName $ServiceName
Write-Host "TaskArn: $taskArn" -ForegroundColor Green

# 3) Inspect config + dbt debug
Write-Host "[3/4] Inspecting profiles.yml and running dbt debug..." -ForegroundColor Yellow
Invoke-EcsCommand -Cluster $Cluster -TaskArn $taskArn -Container $Container -Cmd "bash -lc 'echo === profiles.yml ===; sed -n ""1,200p"" /opt/airflow/dbt/profiles.yml; echo; echo === grep catalog ===; grep -nE ""(^|\\s)(catalog|data_catalog)\\s*:"" /opt/airflow/dbt/profiles.yml || true'"
Invoke-EcsCommand -Cluster $Cluster -TaskArn $taskArn -Container $Container -Cmd "bash -lc 'dbt debug --profiles-dir /opt/airflow/dbt --target dev --debug'"

# 4) Run dbt models
# Default behavior: run staging unless -RunStaging:$false is explicitly passed (not typical for switches)
$doRunStaging = if ($PSBoundParameters.ContainsKey('RunStaging')) { $RunStaging.IsPresent } else { $true }
$doRunMarts = $RunMarts.IsPresent

if ($doRunStaging) {
  Write-Host "[4/4] Running dbt staging models..." -ForegroundColor Yellow
  Invoke-EcsCommand -Cluster $Cluster -TaskArn $taskArn -Container $Container -Cmd "bash -lc 'cd /opt/airflow/dbt && dbt run --profiles-dir . --target dev --select staging.* --debug'"
}
if ($doRunMarts) {
  Write-Host "[4/4] Running dbt marts models..." -ForegroundColor Yellow
  Invoke-EcsCommand -Cluster $Cluster -TaskArn $taskArn -Container $Container -Cmd "bash -lc 'cd /opt/airflow/dbt && dbt run --profiles-dir . --target dev --select marts.* --debug'"
}

Write-Host "Done." -ForegroundColor Cyan

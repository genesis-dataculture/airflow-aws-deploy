# Grant AWS Lake Formation Permissions for Airflow dbt Integration
# This script grants the necessary Lake Formation permissions to the airflow-task-execution-role
# so that dbt can access Glue Catalog databases and tables

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "AWS Lake Formation - Grant Permissions" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$ROLE_ARN = "arn:aws:iam::730335315247:role/airflow-task-execution-role"
$DATABASE_NAME = "analytics_dev"

# Step 1: Grant Database Permissions
Write-Host "[1/2] Granting DATABASE permissions to $DATABASE_NAME..." -ForegroundColor Yellow

$databaseResource = @"
{
  "Database": {
    "Name": "$DATABASE_NAME"
  }
}
"@

$databaseResource | Out-File -FilePath "temp_db_resource.json" -Encoding ascii -NoNewline

aws lakeformation grant-permissions `
  --principal DataLakePrincipalIdentifier=$ROLE_ARN `
  --permissions ALL `
  --resource file://temp_db_resource.json

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Database permissions granted successfully!" -ForegroundColor Green
} else {
    Write-Host "❌ Failed to grant database permissions" -ForegroundColor Red
    Remove-Item -Path "temp_db_resource.json" -ErrorAction SilentlyContinue
    exit 1
}

# Step 2: Grant Table Permissions (all tables in database)
Write-Host ""
Write-Host "[2/2] Granting TABLE permissions (all tables in $DATABASE_NAME)..." -ForegroundColor Yellow

$tableResource = @"
{
  "Table": {
    "DatabaseName": "$DATABASE_NAME",
    "TableWildcard": {}
  }
}
"@

$tableResource | Out-File -FilePath "temp_table_resource.json" -Encoding ascii -NoNewline

aws lakeformation grant-permissions `
  --principal DataLakePrincipalIdentifier=$ROLE_ARN `
  --permissions ALL `
  --resource file://temp_table_resource.json

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Table permissions granted successfully!" -ForegroundColor Green
} else {
    Write-Host "⚠️  Failed to grant table permissions (may not be critical if no tables exist yet)" -ForegroundColor Yellow
}

# Cleanup
Remove-Item -Path "temp_db_resource.json" -ErrorAction SilentlyContinue
Remove-Item -Path "temp_table_resource.json" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "✅ Lake Formation setup completed!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Re-run the Airflow DAG 'dbt_athena_example'" -ForegroundColor White
Write-Host "2. Check the task 'check_aws_and_dbt' logs" -ForegroundColor White
Write-Host "3. The dbt models should now run successfully!" -ForegroundColor White
Write-Host ""

# Script para criar databases no AWS Glue Catalog
# Autor: Data Team
# Data: 2024-10-19

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Setup: AWS Glue Catalog Databases para dbt" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Verificar autenticacao AWS
Write-Host "`n[Pre-check] Verificando autenticacao AWS..." -ForegroundColor Yellow
try {
    $identity = aws sts get-caller-identity 2>&1 | ConvertFrom-Json
    Write-Host "[OK] Autenticado como: $($identity.Arn)" -ForegroundColor Green
} catch {
    Write-Host "[ERRO] Nao autenticado na AWS!" -ForegroundColor Red
    Write-Host "Execute: aws configure" -ForegroundColor Yellow
    exit 1
}

# Funcao para criar database
function Create-GlueDatabase {
    param(
        [string]$Name,
        [string]$Description,
        [string]$JsonFile
    )
    
    Write-Host "`nCriando database: $Name..." -ForegroundColor Yellow
    
    # Criar arquivo JSON (metodo mais confiavel no PowerShell com AWS CLI)
    $jsonContent = @"
{
    "DatabaseInput": {
        "Name": "$Name",
        "Description": "$Description"
    }
}
"@
    
    # Usar UTF8 sem BOM
    [System.IO.File]::WriteAllText((Join-Path $PWD $JsonFile), $jsonContent, [System.Text.UTF8Encoding]::new($false))
    
    # Usar file:// funciona perfeitamente no PowerShell com AWS CLI
    $result = aws glue create-database --cli-input-json "file://$JsonFile" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Database '$Name' criado com sucesso!" -ForegroundColor Green
        return $true
    } elseif ($result -match "AlreadyExistsException") {
        Write-Host "[AVISO] Database '$Name' ja existe" -ForegroundColor Yellow
        return $true
    } else {
        Write-Host "[ERRO] Ao criar database '$Name':" -ForegroundColor Red
        Write-Host $result -ForegroundColor Red
        return $false
    }
}

# Criacao dos databases
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Criando Databases" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

$databases = @(
    @{Name="analytics_dev"; Description="Database para ambiente de desenvolvimento - transformacoes dbt"; File="analytics_dev.json"},
    @{Name="analytics_prod"; Description="Database para ambiente de producao - transformacoes dbt"; File="analytics_prod.json"},
    @{Name="raw_data"; Description="Database para dados brutos (raw/landing)"; File="raw_data.json"}
)

$successCount = 0
$totalCount = $databases.Count

foreach ($db in $databases) {
    if (Create-GlueDatabase -Name $db.Name -Description $db.Description -JsonFile $db.File) {
        $successCount++
    }
}

# Resumo
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Resumo" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Databases processados: $successCount/$totalCount" -ForegroundColor $(if ($successCount -eq $totalCount) { "Green" } else { "Yellow" })

# Listar databases criados
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Databases no Glue Catalog" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

$glueDbList = aws glue get-databases --query "DatabaseList[?starts_with(Name, 'analytics') || Name=='raw_data'].[Name,Description,CreateTime]" --output table

if ($LASTEXITCODE -eq 0) {
    Write-Host $glueDbList
} else {
    Write-Host "[ERRO] Erro ao listar databases" -ForegroundColor Red
}

# Verificar cada database individualmente
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Verificacao Individual" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

foreach ($db in $databases) {
    $dbName = $db.Name
    Write-Host "`nVerificando database: $dbName" -ForegroundColor Yellow
    
    $dbInfo = aws glue get-database --name $dbName 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $dbData = $dbInfo | ConvertFrom-Json
        Write-Host "[OK] Nome: $($dbData.Database.Name)" -ForegroundColor Green
        Write-Host "  Descricao: $($dbData.Database.Description)" -ForegroundColor Gray
        Write-Host "  Data Criacao: $($dbData.Database.CreateTime)" -ForegroundColor Gray
    } else {
        Write-Host "[ERRO] Database '$dbName' nao encontrado!" -ForegroundColor Red
    }
}

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Setup Concluido!" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Limpar arquivos JSON temporarios
Write-Host "`nLimpando arquivos temporarios..." -ForegroundColor Gray
foreach ($db in $databases) {
    Remove-Item $db.File -ErrorAction SilentlyContinue
}

Write-Host "`nProximos passos:" -ForegroundColor Yellow
Write-Host "1. Upload do projeto dbt para S3:" -ForegroundColor White
Write-Host "   aws s3 sync ./dbt/ s3://ons-dev-dg-00-stage/dbt/ --exclude 'target/*' --exclude 'dbt_packages/*'" -ForegroundColor Gray
Write-Host "`n2. Upload da DAG:" -ForegroundColor White
Write-Host "   aws s3 cp ./dags/dbt_athena_example.py s3://ons-dev-dg-00-stage/dags/" -ForegroundColor Gray
Write-Host "`n3. Rebuild e push da imagem Docker" -ForegroundColor White
Write-Host "`n4. Executar a DAG no Airflow" -ForegroundColor White
Write-Host ""

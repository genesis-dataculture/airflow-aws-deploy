# Script para build e deploy da imagem Docker com packages dbt inclusos
# Autor: Data Team
# Data: 2025-10-19

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Build e Deploy - Airflow com dbt" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Configurações
$ECR_REGISTRY = "730335315247.dkr.ecr.us-east-1.amazonaws.com"
$ECR_REPOSITORY = "airflow-on-ecs-fargate"
$IMAGE_TAG = "latest"
$AWS_REGION = "us-east-1"
$ECS_CLUSTER = "airflow-cluster"
$WEBSERVER_SERVICE = "airflow-webserver-service"
$SCHEDULER_SERVICE = "airflow-scheduler-service"

# Verificar se estamos no diretório correto
if (!(Test-Path "Dockerfile")) {
    Write-Host "ERRO: Dockerfile não encontrado. Execute este script da pasta docker/" -ForegroundColor Red
    exit 1
}

# Verificar se o projeto dbt existe na raiz
if (!(Test-Path "../dbt/packages.yml")) {
    Write-Host "AVISO: ../dbt/packages.yml não encontrado" -ForegroundColor Yellow
}

Write-Host "[1/6] Building Docker image..." -ForegroundColor Green
Write-Host "Comando: docker build -f docker/Dockerfile -t airflow-dbt-athena:$IMAGE_TAG ../" -ForegroundColor Gray
Write-Host "Context: Pasta raiz do projeto (para acessar dbt/)" -ForegroundColor Gray

# Ir para a raiz do projeto para fazer o build
$OriginalPath = Get-Location
Set-Location ..
docker build -f docker/Dockerfile -t airflow-dbt-athena:$IMAGE_TAG .
$BuildExitCode = $LASTEXITCODE
Set-Location $OriginalPath

if ($BuildExitCode -ne 0) {
    Write-Host "ERRO: Falha no build da imagem Docker" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2/6] Tagging image for ECR..." -ForegroundColor Green
Write-Host "Comando: docker tag airflow-dbt-athena:$IMAGE_TAG ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}" -ForegroundColor Gray
docker tag airflow-dbt-athena:$IMAGE_TAG ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}

Write-Host ""
Write-Host "[3/6] Logging in to ECR..." -ForegroundColor Green
Write-Host "Comando: aws ecr get-login-password --region $AWS_REGION | docker login..." -ForegroundColor Gray
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: Falha no login ao ECR" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[4/6] Pushing image to ECR..." -ForegroundColor Green
Write-Host "Comando: docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}" -ForegroundColor Gray
docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: Falha ao fazer push da imagem" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[5/6] Updating ECS services..." -ForegroundColor Green

Write-Host "  - Updating webserver service..." -ForegroundColor Cyan
aws ecs update-service `
    --cluster $ECS_CLUSTER `
    --service $WEBSERVER_SERVICE `
    --force-new-deployment `
    --region $AWS_REGION `
    --no-cli-pager

Write-Host "  - Updating scheduler service..." -ForegroundColor Cyan
aws ecs update-service `
    --cluster $ECS_CLUSTER `
    --service $SCHEDULER_SERVICE `
    --force-new-deployment `
    --region $AWS_REGION `
    --no-cli-pager

Write-Host ""
Write-Host "[6/6] Monitoring deployment..." -ForegroundColor Green
Write-Host "Aguardando 10 segundos para deployment iniciar..." -ForegroundColor Gray
Start-Sleep -Seconds 10

Write-Host ""
Write-Host "Status do Scheduler Service:" -ForegroundColor Cyan
aws ecs describe-services `
    --cluster $ECS_CLUSTER `
    --services $SCHEDULER_SERVICE `
    --region $AWS_REGION `
    --query 'services[0].deployments[*].[status,desiredCount,runningCount,createdAt]' `
    --output table

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Deploy concluído com sucesso!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Próximos passos:" -ForegroundColor Yellow
Write-Host "1. Aguardar deployment completar (3-5 minutos)" -ForegroundColor White
Write-Host "2. Verificar logs do scheduler:" -ForegroundColor White
Write-Host "   aws logs tail /ecs/airflow --follow --filter-pattern scheduler" -ForegroundColor Gray
Write-Host "3. Acessar Airflow UI e executar DAG dbt_athena_example" -ForegroundColor White
Write-Host ""
Write-Host "Para monitorar deployment:" -ForegroundColor Yellow
Write-Host "aws ecs describe-services --cluster $ECS_CLUSTER --services $SCHEDULER_SERVICE --query 'services[0].deployments' --output table" -ForegroundColor Gray
Write-Host ""

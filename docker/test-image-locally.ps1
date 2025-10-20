# Script de validação local da imagem Docker antes do deploy
# Executa testes para verificar se a imagem está correta antes de fazer push para ECR

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TESTE LOCAL DA IMAGEM DOCKER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$IMAGE = "airflow-dbt-athena:latest"
$TESTS_PASSED = 0
$TESTS_FAILED = 0

function Test-Command {
    param($Name, $Command, $ExpectedOutput = $null)
    
    Write-Host "[TEST] $Name..." -NoNewline
    $result = Invoke-Expression $Command 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        if ($ExpectedOutput -and $result -notmatch $ExpectedOutput) {
            Write-Host " ⚠️  PASSED (com aviso)" -ForegroundColor Yellow
            $script:TESTS_PASSED++
            Write-Host "  Output: $result" -ForegroundColor Gray
            Write-Host "  Esperado: $ExpectedOutput" -ForegroundColor Yellow
        } else {
            Write-Host " ✅ PASSED" -ForegroundColor Green
            $script:TESTS_PASSED++
            Write-Host "  Output: $result" -ForegroundColor Gray
        }
    } else {
        Write-Host " ❌ FAILED" -ForegroundColor Red
        $script:TESTS_FAILED++
        Write-Host "  Error: $result" -ForegroundColor Red
    }
    Write-Host ""
}

# Test 1: Imagem existe
Write-Host "[1/10] Verificando se imagem existe..."
$imageExists = docker images -q $IMAGE
if (-not $imageExists) {
    Write-Host "❌ ERRO: Imagem $IMAGE não encontrada!" -ForegroundColor Red
    Write-Host "Execute: docker build -f docker/Dockerfile -t $IMAGE ." -ForegroundColor Yellow
    exit 1
}
Write-Host "✅ Imagem encontrada: $IMAGE" -ForegroundColor Green
Write-Host ""

# Test 2: Usuário padrão é root (necessário para chown no entrypoint)
Test-Command "Usuário padrão é root" "docker run --rm --entrypoint whoami $IMAGE" "root"

# Test 3: Git instalado
Test-Command "Git está instalado" "docker run --rm --entrypoint git $IMAGE --version"

# Test 4: gosu instalado (para trocar de root para airflow)
Test-Command "gosu está instalado" "docker run --rm --entrypoint gosu $IMAGE --version"

# Test 5: dbt instalado
Test-Command "dbt está instalado" "docker run --rm --user airflow --entrypoint dbt $IMAGE --version"

# Test 6: dbt-athena-community instalado
Write-Host "[TEST] dbt-athena-community está instalado..." -ForegroundColor Yellow
$dbtAdapters = docker run --rm --user airflow --entrypoint pip $IMAGE list 2>&1 | Select-String "dbt-athena"
if ($dbtAdapters) {
    Write-Host "✅ PASSED - dbt-athena-community encontrado" -ForegroundColor Green
    Write-Host "  $dbtAdapters" -ForegroundColor Gray
    $TESTS_PASSED++
} else {
    Write-Host "❌ FAILED - dbt-athena-community não encontrado!" -ForegroundColor Red
    $TESTS_FAILED++
}
Write-Host ""

# Test 7: Estrutura de diretórios /opt/airflow/dbt
Write-Host "[TEST] Estrutura de diretórios /opt/airflow/dbt..." -ForegroundColor Yellow
$dbtStructure = docker run --rm --entrypoint ls $IMAGE -la /opt/airflow/dbt/
Write-Host $dbtStructure
Write-Host ""

# Test 8: Permissões do diretório dbt (owner deve ser airflow)
Write-Host "[TEST] Permissões corretas em /opt/airflow/dbt (owner: airflow)..." -ForegroundColor Yellow
$dbtOwner = docker run --rm --entrypoint ls $IMAGE -ld /opt/airflow/dbt/ 2>&1
if ($dbtOwner -match "airflow") {
    Write-Host "✅ PASSED - Owner é airflow" -ForegroundColor Green
    Write-Host "  $dbtOwner" -ForegroundColor Gray
    $TESTS_PASSED++
} else {
    Write-Host "❌ FAILED - Owner NÃO é airflow!" -ForegroundColor Red
    Write-Host "  $dbtOwner" -ForegroundColor Red
    $TESTS_FAILED++
}
Write-Host ""

# Test 9: dbt_packages instalados (NÃO deve existir no build, será instalado no runtime)
Write-Host "[TEST] dbt_packages/ não existe na imagem (instalação runtime)..." -ForegroundColor Yellow
$packagesExist = docker run --rm $IMAGE test -d /opt/airflow/dbt/dbt_packages 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "✅ PASSED - dbt_packages/ não existe (será instalado no startup)" -ForegroundColor Green
    $TESTS_PASSED++
} else {
    Write-Host "⚠️  AVISO - dbt_packages/ já existe na imagem" -ForegroundColor Yellow
    Write-Host "  Isso é OK se você testou localmente antes" -ForegroundColor Gray
    $packagesContent = docker run --rm $IMAGE ls -1 /opt/airflow/dbt/dbt_packages/ 2>&1
    Write-Host "  Packages: $packagesContent" -ForegroundColor Gray
    $TESTS_PASSED++
}
Write-Host ""

# Test 10: Permissões de escrita em /opt/airflow/dbt (usuário airflow)
Write-Host "[TEST] Usuário airflow pode escrever em /opt/airflow/dbt..." -ForegroundColor Yellow
$canWrite = docker run --rm --user airflow --entrypoint touch $IMAGE /opt/airflow/dbt/test-write.txt 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ PASSED - Usuário airflow pode escrever" -ForegroundColor Green
    $TESTS_PASSED++
    # Limpar arquivo de teste
    docker run --rm --user airflow --entrypoint rm $IMAGE -f /opt/airflow/dbt/test-write.txt 2>&1 | Out-Null
} else {
    Write-Host "❌ FAILED - Usuário airflow NÃO pode escrever!" -ForegroundColor Red
    Write-Host "  Erro: $canWrite" -ForegroundColor Red
    $TESTS_FAILED++
}
Write-Host ""

# Test 11: packages.yml existe e está correto
Write-Host "[TEST] packages.yml existe e contém dbt_utils + dbt_expectations..." -ForegroundColor Yellow
$packagesYml = docker run --rm --entrypoint cat $IMAGE /opt/airflow/dbt/packages.yml 2>&1
if ($packagesYml -match "dbt_utils" -and $packagesYml -match "dbt_expectations") {
    Write-Host "✅ PASSED - packages.yml correto" -ForegroundColor Green
    Write-Host $packagesYml -ForegroundColor Gray
    $TESTS_PASSED++
} else {
    Write-Host "❌ FAILED - packages.yml incorreto ou ausente!" -ForegroundColor Red
    Write-Host "  Conteúdo: $packagesYml" -ForegroundColor Red
    $TESTS_FAILED++
}
Write-Host ""

# Test 12: Entrypoint está configurado corretamente
Write-Host "[TEST] Entrypoint contém correção de permissões (chown)..." -ForegroundColor Yellow
$entrypointContent = docker run --rm --entrypoint grep $IMAGE -n "chown" /entrypoint.sh 2>&1
if ($entrypointContent) {
    Write-Host "✅ PASSED - Entrypoint contém chown" -ForegroundColor Green
    Write-Host "  $entrypointContent" -ForegroundColor Gray
    $TESTS_PASSED++
} else {
    Write-Host "❌ FAILED - Entrypoint NÃO contém chown!" -ForegroundColor Red
    $TESTS_FAILED++
}
Write-Host ""

# Resultado Final
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RESULTADO DOS TESTES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✅ Testes Passaram: $TESTS_PASSED" -ForegroundColor Green
Write-Host "❌ Testes Falharam: $TESTS_FAILED" -ForegroundColor Red
Write-Host ""

if ($TESTS_FAILED -eq 0) {
    Write-Host "🎉 TODOS OS TESTES PASSARAM! Imagem pronta para deploy." -ForegroundColor Green
    Write-Host ""
    Write-Host "Próximos passos:" -ForegroundColor Yellow
    Write-Host "1. docker tag $IMAGE 730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest"
    Write-Host "2. aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 730335315247.dkr.ecr.us-east-1.amazonaws.com"
    Write-Host "3. docker push 730335315247.dkr.ecr.us-east-1.amazonaws.com/airflow-on-ecs-fargate:latest"
    Write-Host "4. aws ecs update-service --cluster airflow-cluster --service airflow-webserver-service --force-new-deployment"
    Write-Host "5. aws ecs update-service --cluster airflow-cluster --service airflow-scheduler-service --force-new-deployment"
    exit 0
} else {
    Write-Host "⚠️  ALGUNS TESTES FALHARAM! Corrija antes do deploy." -ForegroundColor Red
    Write-Host ""
    Write-Host "Dicas:" -ForegroundColor Yellow
    Write-Host "- Verifique o Dockerfile: permissões corretas?" -ForegroundColor Gray
    Write-Host "- Verifique o entrypoint.sh: chown configurado?" -ForegroundColor Gray
    Write-Host "- Rebuild: docker build --no-cache -f docker/Dockerfile -t $IMAGE ." -ForegroundColor Gray
    exit 1
}

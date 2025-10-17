# Script para commit da integração dbt-athena
# Execute este script no PowerShell

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Commit: dbt + Athena Integration" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Verificar branch atual
Write-Host "[1/5] Verificando branch atual..." -ForegroundColor Yellow
git branch --show-current

# 2. Adicionar todos os arquivos
Write-Host ""
Write-Host "[2/5] Adicionando arquivos ao staging..." -ForegroundColor Yellow
git add .

# 3. Mostrar status
Write-Host ""
Write-Host "[3/5] Status dos arquivos:" -ForegroundColor Yellow
git status --short

# 4. Criar commit
Write-Host ""
Write-Host "[4/5] Criando commit..." -ForegroundColor Yellow
git commit -m @"
feat: Add dbt-athena integration with Airflow

## Estrutura Criada
- Projeto dbt completo com staging, intermediate e marts layers
- Configuração para AWS Athena + Glue Catalog
- Modelos SQL de exemplo (views e tables)
- Testes de qualidade de dados

## Arquivos Adicionados
- dbt/: Estrutura completa do projeto dbt
  - dbt_project.yml: Configuração principal
  - profiles.yml: Conexão com Athena
  - models/: Modelos SQL (staging, marts)
  - packages.yml: Dependências opcionais
  
- dags/dbt_athena_example.py: DAG de orquestração
- docker/requirements.txt: Dependências dbt-athena
- docker/entrypoint.sh: Sincronização S3

## Documentação
- dbt/README.md: Guia de uso do dbt
- dbt/DEPLOY.md: Guia de deploy AWS
- IMPLEMENTATION_SUMMARY.md: Resumo da implementação

## Dependências
- dbt-core >= 1.7.0
- dbt-athena-community >= 1.7.0
- apache-airflow-providers-dbt-cloud >= 3.5.0
- PyAthena[SQLAlchemy] >= 3.0.0

## Próximos Passos
1. Configurar databases no Glue Catalog
2. Upload projeto para S3
3. Rebuild Docker image
4. Atualizar IAM permissions
5. Deploy via Terraform
"@

# 5. Mostrar log do commit
Write-Host ""
Write-Host "[5/5] Commit criado com sucesso!" -ForegroundColor Green
git log --oneline -1

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Próximos Passos:" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Para fazer push da branch:" -ForegroundColor White
Write-Host "   git push -u origin feature/dbt-athena-integration" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Para criar Pull Request:" -ForegroundColor White
Write-Host "   - Acesse: https://github.com/fabio-genesis/airflow-aws-deploy" -ForegroundColor Gray
Write-Host "   - Clique em 'Compare & pull request'" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Para fazer deploy:" -ForegroundColor White
Write-Host "   - Consulte: dbt/DEPLOY.md" -ForegroundColor Gray
Write-Host ""

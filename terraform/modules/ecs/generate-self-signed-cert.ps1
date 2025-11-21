param(
  [Parameter(Mandatory=$true)][string]$CN,
  [int]$Days = 365,
  [ValidateSet("dev","prod")][string]$Environment = "dev"
)

$ErrorActionPreference = "Stop"

Write-Host "Generating self-signed cert for CN=$CN ($Environment) valid $Days days" -ForegroundColor Cyan

# Create subject
$dn = New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName("CN=$CN, O=Dev, OU=DevOps, C=BR")

# Generate RSA key
$rsa = [System.Security.Cryptography.RSA]::Create(2048)

# Build certificate request
$req = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest(
  $dn,
  $rsa,
  [System.Security.Cryptography.HashAlgorithmName]::SHA256,
  [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
)

# Add SAN with the CN
$san = New-Object System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder
$san.AddDnsName($CN)
$req.CertificateExtensions.Add($san.Build())

# Key usages
$kuFlags = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor `
           [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment
$ku = New-Object System.Security.Cryptography.X509Certificates.X509KeyUsageExtension($kuFlags, $true)
$req.CertificateExtensions.Add($ku)

# Enhanced Key Usage: Server Authentication
$oids = New-Object System.Security.Cryptography.OidCollection
[void]$oids.Add((New-Object System.Security.Cryptography.Oid("1.3.6.1.5.5.7.3.1")))
$eku = New-Object System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension($oids, $true)
$req.CertificateExtensions.Add($eku)

# Validity period
$notBefore = Get-Date
$notAfter  = $notBefore.AddDays($Days)
$cert = $req.CreateSelfSigned($notBefore, $notAfter)

# Export certificate (DER -> PEM)
$certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
$certBase64 = [Convert]::ToBase64String($certBytes, 'InsertLineBreaks')
$certPem = "-----BEGIN CERTIFICATE-----`r`n$certBase64`r`n-----END CERTIFICATE-----`r`n"
[IO.File]::WriteAllText((Join-Path $PSScriptRoot ("airflow-$Environment-certificate.pem")), $certPem)

# Export private key (PKCS#8 -> PEM)
$pkcs8 = $rsa.ExportPkcs8PrivateKey()
$keyBase64 = [Convert]::ToBase64String($pkcs8, 'InsertLineBreaks')
$keyPem = "-----BEGIN PRIVATE KEY-----`r`n$keyBase64`r`n-----END PRIVATE KEY-----`r`n"
[IO.File]::WriteAllText((Join-Path $PSScriptRoot ("airflow-$Environment-private-key.pem")), $keyPem)

Write-Host "Generated files:" -ForegroundColor Green
Write-Host (Join-Path $PSScriptRoot ("airflow-$Environment-private-key.pem"))
Write-Host (Join-Path $PSScriptRoot ("airflow-$Environment-certificate.pem"))
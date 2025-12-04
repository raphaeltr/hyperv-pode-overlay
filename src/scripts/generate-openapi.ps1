# src/scripts/generate-openapi.ps1
# Script pour générer le fichier openapi.json à partir des commentaires inline

param(
    [string]$OutputPath = "$PSScriptRoot/../../docs/openapi.json",
    [string]$BaseUrl = "http://localhost:8080"
)

$ErrorActionPreference = "Stop"

try {
    # Importer le module OpenAPI
    # Construire le chemin de manière plus robuste
    $moduleDir = Join-Path (Join-Path (Join-Path $PSScriptRoot '..') 'modules') 'HvoOpenApi'
    $modulePath = Join-Path $moduleDir 'HvoOpenApi.psd1'
    
    if (-not (Test-Path $modulePath)) {
        Write-Error "OpenAPI module not found at: $modulePath"
        Write-Error "Expected directory structure: src/modules/HvoOpenApi/HvoOpenApi.psd1"
        exit 1
    }
    
    Write-Host "Import du module HvoOpenApi..." -ForegroundColor Cyan
    Write-Host "  Chemin: $modulePath" -ForegroundColor Gray
    
    Import-Module $modulePath -Force -ErrorAction Stop
    
    # Vérifier que la fonction est bien disponible après l'import
    if (-not (Get-Command Get-HvoOpenApiSpec -ErrorAction SilentlyContinue)) {
        Write-Error "La fonction Get-HvoOpenApiSpec n'est pas disponible après l'import du module"
        Write-Error "Vérifiez que le module exporte correctement ses fonctions"
        exit 1
    }
    
    Write-Host "  Module importé avec succès" -ForegroundColor Green
    
    # Charger la config si disponible
    $configPath = Join-Path (Join-Path $PSScriptRoot '..') 'config.ps1'
    if (Test-Path $configPath) {
        Write-Host "Chargement de la configuration..." -ForegroundColor Cyan
        . $configPath
        
        if (Get-Command Get-HvoConfig -ErrorAction SilentlyContinue) {
            $cfg = Get-HvoConfig
            if ($cfg -and $cfg.ListenAddress -and $cfg.Port) {
                $BaseUrl = "http://$($cfg.ListenAddress):$($cfg.Port)"
                Write-Host "  Base URL depuis config: $BaseUrl" -ForegroundColor Gray
            }
        } else {
            Write-Warning "Get-HvoConfig n'est pas disponible, utilisation de la BaseUrl par défaut"
        }
    } else {
        Write-Host "Aucun fichier de configuration trouvé, utilisation des valeurs par défaut" -ForegroundColor Yellow
    }
    
    # Générer le spec
    $routesPath = Join-Path (Join-Path $PSScriptRoot '..') 'routes'
    
    # Vérifier que le répertoire des routes existe
    if (-not (Test-Path $routesPath)) {
        Write-Error "Le répertoire des routes n'existe pas: $routesPath"
        exit 1
    }
    
    if (-not (Test-Path $routesPath -PathType Container)) {
        Write-Error "Le chemin spécifié n'est pas un répertoire: $routesPath"
        exit 1
    }
    
    Write-Host "Génération de la spécification OpenAPI..." -ForegroundColor Cyan
    Write-Host "  Routes: $routesPath" -ForegroundColor Gray
    Write-Host "  Base URL: $BaseUrl" -ForegroundColor Gray
    
    $spec = Get-HvoOpenApiSpec -RoutesPath $routesPath -BaseUrl $BaseUrl
    
    if (-not $spec) {
        Write-Error "La génération de la spécification OpenAPI a échoué (résultat null)"
        exit 1
    }
    
    # Convertir en JSON avec profondeur suffisante
    $json = $spec | ConvertTo-Json -Depth 50 -Compress:$false
    
    if (-not $json) {
        Write-Error "La conversion en JSON a échoué"
        exit 1
    }
    
    # Créer le répertoire si nécessaire
    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        Write-Host "Répertoire créé: $outputDir" -ForegroundColor Yellow
    }
    
    # Écrire le fichier
    $json | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "OpenAPI spec généré avec succès: $OutputPath" -ForegroundColor Green
    
    # Afficher quelques statistiques
    if ($spec.paths) {
        $pathCount = ($spec.paths.PSObject.Properties | Measure-Object).Count
        Write-Host "  Endpoints documentés: $pathCount" -ForegroundColor Gray
        
        # Afficher le nombre de schémas
        if ($spec.components -and $spec.components.schemas) {
            $schemaCount = ($spec.components.schemas.PSObject.Properties | Measure-Object).Count
            Write-Host "  Schémas définis: $schemaCount" -ForegroundColor Gray
        }
    } else {
        Write-Warning "Aucun endpoint trouvé dans la spécification"
    }
}
catch {
    Write-Error "Erreur lors de la génération: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    exit 1
}


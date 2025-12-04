function global:Add-HvoOpenApiRoutes {
    # @openapi
    # path: /openapi.json
    # method: GET
    # summary: Retourne la spécification OpenAPI
    # description: Génère et retourne la spécification OpenAPI complète de l'API à partir des commentaires inline
    # tags: [Documentation]
    # responses:
    #   200:
    #     description: Spécification OpenAPI
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Get -Path '/openapi.json' -ScriptBlock {
        try {
            # Charger la config pour obtenir la BaseUrl
            $configPath = Join-Path $PSScriptRoot '..' 'config.ps1'
            if (Test-Path $configPath) {
                . $configPath
            }

            $cfg = Get-HvoConfig
            $BaseUrl = "http://$($cfg.ListenAddress):$($cfg.Port)"

            # Déterminer le chemin des routes
            # $PSScriptRoot pointe vers le répertoire routes, donc on l'utilise directement
            $routesPath = $PSScriptRoot

            # Générer la spécification OpenAPI
            $spec = Get-HvoOpenApiSpec -RoutesPath $routesPath -BaseUrl $BaseUrl -Quiet

            if (-not $spec) {
                Write-PodeJsonResponse -StatusCode 500 -Value @{
                    error  = "Failed to generate OpenAPI specification"
                    detail = "Get-HvoOpenApiSpec returned null"
                }
                return
            }

            # Retourner la réponse JSON
            # Utiliser Write-PodeJsonResponse qui gère automatiquement la conversion JSON
            # avec la profondeur appropriée pour les structures complexes
            Write-PodeJsonResponse -Value $spec
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error  = "Failed to generate OpenAPI specification"
                detail = $_.Exception.Message
            }
        }
    }
}


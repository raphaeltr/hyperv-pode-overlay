function global:Add-HvoCommonRoutes {
    # @openapi
    # path: /health
    # method: GET
    # summary: Vérifie l'état du serveur API
    # description: Retourne l'état de santé du serveur et sa configuration
    # tags: [Health]
    # responses:
    #   200:
    #     description: Serveur opérationnel
    #     content:
    #       application/json:
    #         schema:
    #           $ref: '#/components/schemas/HealthResponse'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Get -Path '/health' -ScriptBlock {
        try {
            # Ensure config and Get-HvoConfig are available in Pode's runspace
            $configPath = Join-Path $PSScriptRoot '..' 'config.ps1'
            if (Test-Path $configPath) {
                . $configPath
            }

            $cfg = Get-HvoConfig
            Write-PodeJsonResponse -Value @{
                status = "ok"
                config = $cfg
                root   = $PSScriptRoot
                time   = (Get-Date).ToString('o')
            }
        }
        catch {
            # Return structured JSON error similar to other routes
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error  = "Health check failed"
                detail = $_.Exception.Message
            }
        }
    }
}

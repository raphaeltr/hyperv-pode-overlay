function global:Add-HvoSwitchRoutes {

    # @openapi
    # path: /switches
    # method: GET
    # summary: Liste tous les switches virtuels
    # description: Retourne la liste complète des switches virtuels
    # tags: [Switches]
    # responses:
    #   200:
    #     description: Liste des switches
    #     content:
    #       application/json:
    #         schema:
    #           type: array
    #           items:
    #             $ref: '#/components/schemas/Switch'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Get -Path '/switches' -ScriptBlock {
        try {
            Write-PodeJsonResponse -Value (Get-HvoSwitches)
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to list switches"
                detail = $_.Exception.Message
            }
        }
    }

    # @openapi
    # path: /switches/{name}
    # method: GET
    # summary: Récupère les détails d'un switch
    # description: Retourne les informations détaillées d'un switch virtuel spécifique
    # tags: [Switches]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Nom du switch
    # responses:
    #   200:
    #     description: Détails du switch
    #     content:
    #       application/json:
    #         schema:
    #           $ref: '#/components/schemas/Switch'
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Get -Path '/switches/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']

            $sw = Get-HvoSwitch -Name $name
            if (-not $sw) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "Switch not found"
                }
                return
            }

            Write-PodeJsonResponse -Value $sw
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to get switch"
                detail = $_.Exception.Message
            }
        }
    }

    # @openapi
    # path: /switches
    # method: POST
    # summary: Crée un nouveau switch virtuel
    # description: Crée un switch virtuel (Internal, Private ou External). Opération idempotente. Si le switch existe déjà, retourne 200 au lieu de 201.
    # tags: [Switches]
    # requestBody:
    #   required: true
    #   content:
    #     application/json:
    #       schema:
    #         $ref: '#/components/schemas/SwitchCreateRequest'
    # responses:
    #   201:
    #     description: Switch créé
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             created:
    #               type: string
    #   200:
    #     description: Switch existe déjà
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             exists:
    #               type: string
    #   400:
    #     $ref: '#/components/responses/BadRequest'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Post -Path '/switches' -ScriptBlock {
        try {
            $b = Get-HvoJsonBody

            if (-not $b) {
                Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Invalid JSON" }
                return
            }

            $result = New-HvoSwitch `
                -Name $b.name `
                -Type $b.type `
                -NetAdapterName $b.netAdapterName `
                -Notes $b.notes

            if ($result.Exists) {
                Write-PodeJsonResponse -StatusCode 200 -Value @{
                    exists = $result.Name
                }
            }
            else {
                Write-PodeJsonResponse -StatusCode 201 -Value @{
                    created = $result.Name
                }
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to create switch"
                detail = $_.Exception.Message
            }
        }
    }

    # @openapi
    # path: /switches/{name}
    # method: PUT
    # summary: Met à jour un switch virtuel
    # description: Met à jour les notes d'un switch. Seul le champ notes est modifiable. Opération idempotente.
    # tags: [Switches]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Nom du switch
    # requestBody:
    #   required: true
    #   content:
    #     application/json:
    #       schema:
    #         $ref: '#/components/schemas/SwitchUpdateRequest'
    # responses:
    #   200:
    #     description: Switch mis à jour
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             updated:
    #               type: string
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   400:
    #     $ref: '#/components/responses/BadRequest'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Put -Path '/switches/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $body = Get-HvoJsonBody

            if (-not $body) {
                Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Invalid JSON" }
                return
            }

            # Only pass fields that the user provided
            $params = @{ Name = $name }

            if ($body.notes) {
                $params.Notes = $body.notes
            }

            $result = Set-HvoSwitch @params

            if (-not $result.Updated) {
                Write-PodeJsonResponse -StatusCode 404 -Value $result
                return
            }

            Write-PodeJsonResponse -Value @{ updated = $result.Name }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error  = "Failed to update switch"
                detail = $_.Exception.Message
            }
        }
    }

    # @openapi
    # path: /switches/{name}
    # method: DELETE
    # summary: Supprime un switch virtuel
    # description: Supprime un switch virtuel. Opération idempotente.
    # tags: [Switches]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Nom du switch
    # responses:
    #   200:
    #     description: Switch supprimé
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             deleted:
    #               type: string
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Delete -Path '/switches/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $ok = Remove-HvoSwitch -Name $name

            if (-not $ok) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "Switch not found"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                deleted = $name
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to delete switch"
                detail = $_.Exception.Message
            }
        }
    }

}

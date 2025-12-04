function global:Add-HvoVmRoutes {

    # @openapi
    # path: /vms
    # method: GET
    # summary: Liste toutes les machines virtuelles
    # description: Retourne la liste complète des VMs avec leur état actuel
    # tags: [VMs]
    # responses:
    #   200:
    #     description: Liste des VMs
    #     content:
    #       application/json:
    #         schema:
    #           type: array
    #           items:
    #             $ref: '#/components/schemas/Vm'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Get -Path '/vms' -ScriptBlock {
        try {
            $vms = Get-HvoVms
            Write-PodeJsonResponse -Value $vms
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to list VMs"
                detail = $_.Exception.Message
            }
        }
    }
    # @openapi
    # path: /vms/{name}
    # method: GET
    # summary: Récupère les détails d'une VM
    # description: Retourne les informations détaillées d'une machine virtuelle spécifique
    # tags: [VMs]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Nom de la VM
    # responses:
    #   200:
    #     description: Détails de la VM
    #     content:
    #       application/json:
    #         schema:
    #           $ref: '#/components/schemas/Vm'
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Get -Path '/vms/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']

            $vm = Get-HvoVm -Name $name
            if (-not $vm) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            Write-PodeJsonResponse -Value $vm
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to get VM"
                detail = $_.Exception.Message
            }
        }
    }

    # @openapi
    # path: /vms
    # method: POST
    # summary: Crée une nouvelle machine virtuelle
    # description: Opération idempotente. Si la VM existe déjà, retourne 200 au lieu de 201.
    # tags: [VMs]
    # requestBody:
    #   required: true
    #   content:
    #     application/json:
    #       schema:
    #         $ref: '#/components/schemas/VmCreateRequest'
    # responses:
    #   201:
    #     description: VM créée
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             created:
    #               type: string
    #   200:
    #     description: VM existe déjà
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
    Add-PodeRoute -Method Post -Path '/vms' -ScriptBlock {
        try {
            $b = Get-HvoJsonBody

            if (-not $b) {
                Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Invalid JSON" }
                return
            }

            $result = New-HvoVm @b

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
                error = "Failed to create VM"
                detail = $_.Exception.Message
            }
        }
    }

    # @openapi
    # path: /vms/{name}
    # method: PUT
    # summary: Met à jour une machine virtuelle
    # description: Met à jour les propriétés d'une VM existante. Opération idempotente.
    # tags: [VMs]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Nom de la VM
    # requestBody:
    #   required: true
    #   content:
    #     application/json:
    #       schema:
    #         $ref: '#/components/schemas/VmUpdateRequest'
    # responses:
    #   200:
    #     description: VM mise à jour ou inchangée
    #     content:
    #       application/json:
    #         schema:
    #           $ref: '#/components/schemas/VmActionResponse'
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   409:
    #     description: Conflit (ex: VM en cours d'exécution)
    #     content:
    #       application/json:
    #         schema:
    #           $ref: '#/components/schemas/Error'
    #   400:
    #     $ref: '#/components/responses/BadRequest'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Put -Path '/vms/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $body = Get-HvoJsonBody

            if (-not $body) {
                Write-PodeJsonResponse -StatusCode 400 -Value @{ error = "Invalid JSON" }
                return
            }

            # Only pass parameters actually provided by the client
            $params = @{ Name = $name }

            if ($body.memoryMB)   { $params.MemoryMB   = $body.memoryMB }
            if ($body.vcpu)       { $params.Vcpu       = $body.vcpu }
            if ($body.switchName) { $params.SwitchName = $body.switchName }
            if ($body.isoPath)    { $params.IsoPath    = $body.isoPath }

            $result = Set-HvoVm @params

            #
            # Return 404 when VM does not exist
            #
            if ($result.Error -eq "VM not found") {
                Write-PodeJsonResponse -StatusCode 404 -Value $result
                return
            }

            #
            # If no changes were needed -> idempotent behavior
            #
            if ($result.Updated -eq $false -and $result.Unchanged) {
                Write-PodeJsonResponse -StatusCode 200 -Value @{
                    unchanged = $true
                    name      = $name
                }
                return
            }

            #
            # If an update condition failed (e.g., VM running)
            #
            if ($result.Updated -eq $false -and $result.Error) {
                Write-PodeJsonResponse -StatusCode 409 -Value $result
                return
            }

            #
            # Success: the VM was updated
            #
            Write-PodeJsonResponse -StatusCode 200 -Value @{
                updated = $true
                name    = $name
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error  = "Failed to update VM"
                detail = $_.Exception.Message
            }
        }
    }

    # @openapi
    # path: /vms/{name}
    # method: DELETE
    # summary: Supprime une machine virtuelle
    # description: Supprime une VM et ses disques associés. Opération idempotente.
    # tags: [VMs]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Nom de la VM
    # responses:
    #   200:
    #     description: VM supprimée
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
    Add-PodeRoute -Method Delete -Path '/vms/:name' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $ok = Remove-HvoVm -Name $name -RemoveDisks:$true

            if (-not $ok) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                deleted = $name
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to delete VM"
                detail = $_.Exception.Message
            }
        }
    }

    # @openapi
    # path: /vms/{name}/start
    # method: POST
    # summary: Démarre une machine virtuelle
    # description: Démarre une VM. Opération idempotente.
    # tags: [VMs]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Nom de la VM
    # responses:
    #   200:
    #     description: VM démarrée
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             started:
    #               type: string
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Post -Path '/vms/:name/start' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $result = Start-HvoVm -Name $name

            if (-not $result) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                started = $result.Name
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to start VM"
                detail = $_.Exception.Message
            }
        }
    }

    # @openapi
    # path: /vms/{name}/stop
    # method: POST
    # summary: Arrête une machine virtuelle
    # description: Arrête une VM de manière gracieuse ou forcée. Opération idempotente.
    # tags: [VMs]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Nom de la VM
    #   - name: force
    #     in: query
    #     required: false
    #     schema:
    #       type: boolean
    #     description: Force l'arrêt si true
    # requestBody:
    #   required: false
    #   content:
    #     application/json:
    #       schema:
    #         type: object
    #         properties:
    #           force:
    #             type: boolean
    #             description: Force l'arrêt si true
    # responses:
    #   200:
    #     description: VM arrêtée
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             stopped:
    #               type: string
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   409:
    #     description: VM déjà arrêtée
    #     content:
    #       application/json:
    #         schema:
    #           $ref: '#/components/schemas/Error'
    #   422:
    #     description: Service d'intégration d'arrêt non disponible
    #     content:
    #       application/json:
    #         schema:
    #           $ref: '#/components/schemas/Error'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Post -Path '/vms/:name/stop' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            
            # Extract force parameter from query or body
            $force = $false
            if ($WebEvent.Query['force'] -eq "true") {
                $force = $true
            }
            else {
                $b = Get-HvoJsonBody
                if ($b -and $b.force -eq $true) {
                    $force = $true
                }
            }
            
            $result = Stop-HvoVm -Name $name -Force:$force

            if (-not $result) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            if ($result.AlreadyStopped) {
                Write-PodeJsonResponse -StatusCode 409 -Value @{
                    error = "VM is already stopped"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                stopped = $result.Name
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            
            # Detect errors related to the shutdown integration service
            if ($errorMessage -match 'SHUTDOWN_SERVICE_NOT_AVAILABLE|SHUTDOWN_SERVICE_NOT_ENABLED') {
                # Extract the message without the prefix
                $detail = $errorMessage -replace '^[^:]+:\s*', ''
                Write-PodeJsonResponse -StatusCode 422 -Value @{
                    error = "Shutdown integration service not available or not enabled"
                    detail = $detail
                }
                return
            }
            
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to stop VM"
                detail = $errorMessage
            }
        }
    }

    # @openapi
    # path: /vms/{name}/restart
    # method: POST
    # summary: Redémarre une machine virtuelle
    # description: Redémarre une VM de manière gracieuse ou forcée. Si la VM est arrêtée, elle sera démarrée. Opération idempotente.
    # tags: [VMs]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Nom de la VM
    #   - name: force
    #     in: query
    #     required: false
    #     schema:
    #       type: boolean
    #     description: Force le redémarrage si true
    # requestBody:
    #   required: false
    #   content:
    #     application/json:
    #       schema:
    #         type: object
    #         properties:
    #           force:
    #             type: boolean
    #             description: Force le redémarrage si true
    # responses:
    #   200:
    #     description: VM redémarrée
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             restarted:
    #               type: string
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   422:
    #     description: Service d'intégration d'arrêt non disponible
    #     content:
    #       application/json:
    #         schema:
    #           $ref: '#/components/schemas/Error'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Post -Path '/vms/:name/restart' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            
            # Extract force parameter from query or body
            $force = $false
            if ($WebEvent.Query['force'] -eq "true") {
                $force = $true
            }
            else {
                $b = Get-HvoJsonBody
                if ($b -and $b.force -eq $true) {
                    $force = $true
                }
            }
            
            $result = Restart-HvoVm -Name $name -Force:$force

            if (-not $result) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                restarted = $result.Name
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            
            # Detect errors related to the shutdown integration service
            if ($errorMessage -match 'SHUTDOWN_SERVICE_NOT_AVAILABLE|SHUTDOWN_SERVICE_NOT_ENABLED') {
                # Extract the message without the prefix
                $detail = $errorMessage -replace '^[^:]+:\s*', ''
                Write-PodeJsonResponse -StatusCode 422 -Value @{
                    error = "Shutdown integration service not available or not enabled"
                    detail = $detail
                }
                return
            }
            
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to restart VM"
                detail = $errorMessage
            }
        }
    }

    # @openapi
    # path: /vms/{name}/suspend
    # method: POST
    # summary: Suspend une machine virtuelle
    # description: Met en pause une VM. Opération idempotente.
    # tags: [VMs]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Nom de la VM
    # responses:
    #   200:
    #     description: VM suspendue
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             suspended:
    #               type: string
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   409:
    #     description: VM déjà suspendue
    #     content:
    #       application/json:
    #         schema:
    #           $ref: '#/components/schemas/Error'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Post -Path '/vms/:name/suspend' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $result = Suspend-HvoVm -Name $name

            if (-not $result) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            if ($result.AlreadySuspended) {
                Write-PodeJsonResponse -StatusCode 409 -Value @{
                    error = "VM is already suspended"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                suspended = $result.Name
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to suspend VM"
                detail = $_.Exception.Message
            }
        }
    }

    # @openapi
    # path: /vms/{name}/resume
    # method: POST
    # summary: Reprend une machine virtuelle
    # description: Reprend l'exécution d'une VM suspendue. Opération idempotente.
    # tags: [VMs]
    # parameters:
    #   - name: name
    #     in: path
    #     required: true
    #     schema:
    #       type: string
    #     description: Nom de la VM
    # responses:
    #   200:
    #     description: VM reprise
    #     content:
    #       application/json:
    #         schema:
    #           type: object
    #           properties:
    #             resumed:
    #               type: string
    #   404:
    #     $ref: '#/components/responses/NotFound'
    #   409:
    #     description: VM déjà en cours d'exécution
    #     content:
    #       application/json:
    #         schema:
    #           $ref: '#/components/schemas/Error'
    #   500:
    #     $ref: '#/components/responses/Error'
    Add-PodeRoute -Method Post -Path '/vms/:name/resume' -ScriptBlock {
        try {
            $name = $WebEvent.Parameters['name']
            $result = Resume-HvoVm -Name $name

            if (-not $result) {
                Write-PodeJsonResponse -StatusCode 404 -Value @{
                    error = "VM not found"
                }
                return
            }

            if ($result.AlreadyRunning) {
                Write-PodeJsonResponse -StatusCode 409 -Value @{
                    error = "VM is already running"
                }
                return
            }

            Write-PodeJsonResponse -Value @{
                resumed = $result.Name
            }
        }
        catch {
            Write-PodeJsonResponse -StatusCode 500 -Value @{
                error = "Failed to resume VM"
                detail = $_.Exception.Message
            }
        }
    }

}

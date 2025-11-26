function global:Add-HvoVmRoutes {

    #
    # GET /vms
    #
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


    #
    # POST /vms
    #
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


    #
    # DELETE /vms/:name
    #
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

}

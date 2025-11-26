function global:Add-HvoCommonRoutes {
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
            Write-HvoErrorJson "HEALTH FAILED" 500 $_
        }
    }
}

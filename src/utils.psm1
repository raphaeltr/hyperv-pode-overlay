# src/utils.psm1

function Get-HvoJsonBody {
    try {
        if ($WebEvent.Data) { return $WebEvent.Data }
        $raw = [System.Text.Encoding]::UTF8.GetString($WebEvent.Request.Body)
        if ($raw) { return $raw | ConvertFrom-Json }
    }
    catch {}
    return $null
}

Export-ModuleMember -Function *

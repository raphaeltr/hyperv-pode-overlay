# src/modules/HvoOpenApi/HvoOpenApi.psm1

function Get-HvoOpenApiSpec {
    param(
        [string]$RoutesPath = "$PSScriptRoot/../routes",
        [string]$BaseUrl = "http://localhost:8080",
        [switch]$Quiet
    )

    $spec = @{
        openapi = "3.0.3"
        info = @{
            title = "Hyper-V API Overlay"
            description = "REST API layer on top of Microsoft Hyper-V using PowerShell and Pode"
            version = "1.0.0"
        }
        servers = @(
            @{
                url = $BaseUrl
                description = "Hyper-V Host API Server"
            }
        )
        paths = @{}
        components = @{
            schemas = @{}
            responses = @{}
        }
    }

    # Ajouter les schémas et réponses de base
    Add-HvoOpenApiSchemas -Spec $spec
    Add-HvoOpenApiResponses -Spec $spec

    # Parser les fichiers de routes
    # Normaliser le chemin
    try {
        if ([System.IO.Path]::IsPathRooted($RoutesPath)) {
            $routesPathResolved = [System.IO.Path]::GetFullPath($RoutesPath)
        } else {
            $routesPathResolved = Resolve-Path $RoutesPath -ErrorAction Stop
            $routesPathResolved = $routesPathResolved.Path
        }
        
        # Vérifier que le chemin existe
        if (-not (Test-Path $routesPathResolved)) {
            Write-Warning "Routes path does not exist: $routesPathResolved (original: $RoutesPath)"
            return $spec
        }
        
        # Vérifier que c'est un répertoire
        if (-not (Test-Path $routesPathResolved -PathType Container)) {
            Write-Warning "Routes path is not a directory: $routesPathResolved"
            return $spec
        }
    }
    catch {
        Write-Warning "Failed to resolve routes path: $RoutesPath - $($_.Exception.Message)"
        return $spec
    }

    $routeFiles = Get-ChildItem -Path $routesPathResolved -Filter "*.ps1" -ErrorAction SilentlyContinue
    
    if (-not $routeFiles) {
        if (-not $Quiet) {
            Write-Warning "No route files found in: $routesPathResolved"
        }
        return $spec
    }
    
    if (-not $Quiet) {
        Write-Host "Processing $($routeFiles.Count) route file(s) from: $routesPathResolved" -ForegroundColor Cyan
    }
    
    foreach ($file in $routeFiles) {
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
            if ($content) {
                # Compter les occurrences de @openapi dans le fichier
                $openapiCount = ([regex]::Matches($content, '@openapi')).Count
                if (-not $Quiet) {
                    Write-Host "  File: $($file.Name) - @openapi markers: $openapiCount" -ForegroundColor Gray
                }
                
                $routes = Get-HvoOpenApiRoutes -Content $content -FilePath $file.FullName -Quiet:$Quiet
                
                if ($routes.Count -eq 0) {
                    if (-not $Quiet) {
                        Write-Warning "  No routes parsed from: $($file.Name) (found $openapiCount @openapi markers)"
                    }
                } else {
                    if (-not $Quiet) {
                        Write-Host "  Found $($routes.Count) route(s) in $($file.Name)" -ForegroundColor Green
                    }
                }
                
                foreach ($route in $routes) {
                    $path = $route.path
                    $method = $route.method.ToLower()
                    
                    if ($path -and $method) {
                        if (-not $spec.paths[$path]) {
                            $spec.paths[$path] = @{}
                        }
                        
                        # Normaliser les tags pour s'assurer qu'ils sont toujours des tableaux
                        if ($route.spec -and $route.spec.ContainsKey('tags')) {
                            $tagsValue = $route.spec['tags']
                            if ($tagsValue -isnot [array]) {
                                # Convertir en tableau si ce n'est pas déjà un tableau
                                $route.spec['tags'] = @($tagsValue)
                            }
                        }
                        
                        $spec.paths[$path][$method] = $route.spec
                    } else {
                        Write-Warning "Route missing path or method in file: $($file.Name) - path: $($route.path), method: $($route.method)"
                    }
                }
            }
        }
        catch {
            Write-Warning "Error parsing route file $($file.FullName): $($_.Exception.Message)"
        }
    }

    return $spec
}

function Get-HvoOpenApiRoutes {
    param(
        [string]$Content,
        [string]$FilePath,
        [switch]$Quiet
    )

    $routes = @()
    $lines = $Content -split "`r?`n"
    $i = 0
    
    while ($i -lt $lines.Length) {
        # Chercher le marqueur @openapi (pattern simplifié)
        $line = $lines[$i]
        if ($line -match '@openapi') {
            if (-not $Quiet) {
                Write-Host "    Found @openapi at line $($i+1) in $([System.IO.Path]::GetFileName($FilePath))" -ForegroundColor Yellow
            }
            $route = @{
                path = $null
                method = $null
                spec = @{}
            }
            
            $i++
            $commentBlock = @()
            
            # Collecter le bloc de commentaires en préservant l'indentation relative
            $baseIndent = $null
            while ($i -lt $lines.Length -and ($lines[$i] -match '^\s*#' -or $lines[$i].Trim() -eq '')) {
                if ($lines[$i] -match '^\s*#\s*(.+)') {
                    $fullLine = $lines[$i]
                    $commentContent = $matches[1]
                    # Préserver l'indentation relative après le #
                    $hashPos = $fullLine.IndexOf('#')
                    $afterHash = $fullLine.Substring($hashPos + 1)
                    # Compter les espaces après le #
                    $spacesAfterHash = 0
                    while ($spacesAfterHash -lt $afterHash.Length -and $afterHash[$spacesAfterHash] -eq ' ') {
                        $spacesAfterHash++
                    }
                    # Si c'est la première ligne non vide, c'est la base d'indentation
                    if ($null -eq $baseIndent -and $commentContent.Trim()) {
                        $baseIndent = $spacesAfterHash
                    }
                    # Construire la ligne avec l'indentation relative préservée
                    if ($null -ne $baseIndent -and $spacesAfterHash -gt $baseIndent) {
                        $relativeIndent = $spacesAfterHash - $baseIndent
                        $commentLine = (' ' * $relativeIndent) + $commentContent.TrimStart()
                    } else {
                        $commentLine = $commentContent.TrimStart()
                    }
                    if ($commentLine) {
                        $commentBlock += $commentLine
                    }
                }
                $i++
            }
            
            # Parser les commentaires YAML (avec protection contre les blocages)
            if ($commentBlock.Count -gt 0) {
                try {
                    $yamlContent = $commentBlock -join "`n"
                    if (-not $Quiet) {
                        Write-Host "    Parsing YAML block ($($commentBlock.Count) lines)..." -ForegroundColor Gray
                    }
                    
                    # Limiter la taille du YAML pour éviter les blocages
                    if ($commentBlock.Count -gt 100) {
                        if (-not $Quiet) {
                            Write-Warning "    YAML block too large ($($commentBlock.Count) lines), skipping"
                        }
                        $route.spec = @{}
                    } else {
                        $route.spec = Convert-HvoOpenApiYaml -YamlContent $yamlContent
                        if (-not $Quiet) {
                            Write-Host "    YAML parsed successfully" -ForegroundColor Gray
                        }
                        
                        # Corriger la structure parsée (extraction de responses, conversion de required, etc.)
                        $route.spec = Repair-HvoOpenApiSpecStructure -Spec $route.spec
                    }
                    
                    # Extraire path et method depuis le spec parsé (priorité)
                    # Vérifier d'abord au niveau racine
                    if ($route.spec -and $route.spec.ContainsKey('path')) {
                        $route.path = $route.spec['path']
                        $route.spec.Remove('path')
                    }
                    if ($route.spec -and $route.spec.ContainsKey('method')) {
                        $route.method = $route.spec['method']
                        $route.spec.Remove('method')
                    }
                    
                    # Debug: afficher ce qui a été parsé
                    if (-not $route.path -or -not $route.method) {
                        if (-not $Quiet) {
                            Write-Host "    Warning: Missing path or method after parsing. Path: $($route.path), Method: $($route.method)" -ForegroundColor Yellow
                            if ($route.spec) {
                                Write-Host "    Parsed spec keys: $($route.spec.Keys -join ', ')" -ForegroundColor Yellow
                            }
                        }
                    }
                }
                catch {
                    if (-not $Quiet) {
                        Write-Host "    Error parsing YAML: $($_.Exception.Message)" -ForegroundColor Red
                    }
                    $route.spec = @{}
                }
            }
            
            # Si path ou method manquent, chercher dans Add-PodeRoute (fallback)
            if (-not $route.path -or -not $route.method) {
                if (-not $Quiet) {
                    Write-Host "    Searching for Add-PodeRoute..." -ForegroundColor Gray
                }
                $maxSearchLines = 50  # Limite pour éviter les boucles infinies
                $searchCount = 0
                $foundRoute = $false
                while ($i -lt $lines.Length -and $searchCount -lt $maxSearchLines -and -not $foundRoute) {
                    # Pattern plus flexible pour matcher Add-PodeRoute
                    if ($lines[$i] -match "Add-PodeRoute\s+-Method\s+(\w+)\s+-Path\s+['""]([^'""]+)['""]") {
                        if (-not $route.method) {
                            $route.method = $matches[1]
                        }
                        if (-not $route.path) {
                            $route.path = $matches[2] -replace ':(\w+)', '{$1}'  # Convertir :name en {name}
                        }
                        if (-not $Quiet) {
                            Write-Host "    Found Add-PodeRoute: $($route.method) $($route.path)" -ForegroundColor Green
                        }
                        $foundRoute = $true
                        break
                    }
                    # Vérifier aussi si on rencontre un autre @openapi (fin de ce bloc)
                    if ($lines[$i] -match '@openapi') {
                        break
                    }
                    $i++
                    $searchCount++
                }
                if (-not $foundRoute -and -not $Quiet) {
                    Write-Host "    Add-PodeRoute not found within $maxSearchLines lines" -ForegroundColor Yellow
                }
            }
            
            if ($route.path -and $route.method) {
                if (-not $Quiet) {
                    Write-Host "    Adding route: $($route.method) $($route.path)" -ForegroundColor Green
                }
                $routes += $route
            } else {
                if (-not $Quiet) {
                    Write-Host "    Skipping route: missing path or method" -ForegroundColor Red
                }
            }
        }
        $i++
    }
    
    return $routes
}

function Convert-HvoOpenApiYaml {
    param([string]$YamlContent)
    
    $result = @{}
    if ([string]::IsNullOrWhiteSpace($YamlContent)) {
        return $result
    }
    
    try {
        $lines = $YamlContent -split "`r?`n"
        $stack = @()
        $current = $result
        $currentIsArray = $false
        $maxLines = 500
        $lineCount = 0
        
        # Première passe : détecter les clés qui devraient être des tableaux
        # On stocke le nom de la clé et son indentation relative
        $arrayKeys = @{}
        for ($i = 0; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }
            
            $indent = $line.Length - $line.TrimStart().Length
            $content = $line.TrimStart()
            
            # Si on voit une clé sans valeur suivie d'un élément de tableau
            if ($content -match '^([^:]+):\s*$') {
                $key = $matches[1].Trim()
                # Regarder la ligne suivante
                if ($i + 1 -lt $lines.Length) {
                    $nextLine = $lines[$i + 1]
                    $nextIndent = $nextLine.Length - $nextLine.TrimStart().Length
                    $nextContent = $nextLine.TrimStart()
                    
                    # Si la ligne suivante est un élément de tableau avec la même indentation + 2
                    if ($nextContent -match '^-\s+' -and $nextIndent -eq $indent + 2) {
                        # Stocker avec la clé et l'indentation relative (pas absolue)
                        $arrayKeys[$key] = $indent
                    }
                }
            }
        }
        
        foreach ($line in $lines) {
            $lineCount++
            if ($lineCount -gt $maxLines) {
                Write-Warning "YAML parsing stopped: too many lines ($lineCount > $maxLines)"
                break
            }
            
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }
            
            $indent = $line.Length - $line.TrimStart().Length
            $content = $line.TrimStart()
            
            # Gérer l'indentation - revenir au bon niveau
            $maxPop = 20
            $popCount = 0
            for ($j = $stack.Count - 1; $j -ge 0 -and $popCount -lt $maxPop; $j--) {
                if ($stack[$j].indent -ge $indent) {
                    $popCount++
                } else {
                    break
                }
            }
            
            if ($popCount -gt 0 -and $popCount -lt $maxPop) {
                $stack = $stack[0..($stack.Count - 1 - $popCount)]
            } elseif ($popCount -ge $maxPop) {
                Write-Warning "YAML parsing: too many stack pops ($popCount), resetting stack"
                $stack = @()
            }
            
            # Si l'indentation est 0, on est au niveau racine
            if ($indent -eq 0) {
                $current = $result
                $currentIsArray = $false
            } elseif ($stack.Count -eq 0) {
                $current = $result
                $currentIsArray = $false
            } else {
                $current = $stack[-1].obj
                $currentIsArray = $stack[-1].isArray
            }
            
            # Détecter les éléments de tableau (commencent par -)
            if ($content -match '^-\s*(.+)$') {
                $itemContent = $matches[1].Trim()
                
                # Si l'élément est une clé-valeur
                if ($itemContent -match '^([^:]+):\s*(.*)$') {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    
                    # Créer un nouvel objet pour cet élément de tableau
                    $newItem = @{}
                    
                    # Trouver le tableau parent
                    # Stratégie simple: chercher dans le parent le plus proche qui contient un tableau
                    $targetArray = $null
                    $targetArrayKey = $null
                    $targetParent = $null
                    
                    # Si on est dans un tableau, chercher où il est stocké
                    if ($currentIsArray) {
                        $targetArray = $current
                        # Chercher dans tous les niveaux de la stack et dans result
                        $searchObjects = @($result)
                        foreach ($si in $stack) {
                            if ($si.obj -is [hashtable]) {
                                $searchObjects += $si.obj
                            }
                        }
                        foreach ($searchObj in $searchObjects) {
                            if ($searchObj -is [hashtable]) {
                                foreach ($k in $searchObj.Keys) {
                                    if ($searchObj[$k] -is [array] -and $searchObj[$k] -eq $targetArray) {
                                        $targetArrayKey = $k
                                        $targetParent = $searchObj
                                        break
                                    }
                                }
                                if ($targetArrayKey) {
                                    break
                                }
                            }
                        }
                    } else {
                        # Chercher dans la stack pour trouver un tableau parent
                        for ($si = $stack.Count - 1; $si -ge 0; $si--) {
                            if ($stack[$si].isArray) {
                                $targetArray = $stack[$si].obj
                                # Chercher le parent qui contient ce tableau
                                $searchObjects = @($result)
                                if ($si -gt 0) {
                                    $searchObjects += $stack[$si - 1].obj
                                }
                                foreach ($searchObj in $searchObjects) {
                                    if ($searchObj -is [hashtable]) {
                                        foreach ($k in $searchObj.Keys) {
                                            if ($searchObj[$k] -is [array] -and $searchObj[$k] -eq $targetArray) {
                                                $targetArrayKey = $k
                                                $targetParent = $searchObj
                                                break
                                            }
                                        }
                                        if ($targetArrayKey) {
                                            break
                                        }
                                    }
                                }
                                break
                            }
                        }
                        
                        # Si pas de tableau trouvé dans la stack, chercher dans le parent direct
                        if (-not $targetArray -and $stack.Count -gt 0) {
                            $parent = $stack[-1].obj
                            if ($parent -is [hashtable]) {
                                # Chercher une clé qui pointe vers un tableau (priorité: parameters, tags)
                                foreach ($k in @('parameters', 'tags', 'required')) {
                                    if ($parent.ContainsKey($k) -and $parent[$k] -is [array]) {
                                        $targetArray = $parent[$k]
                                        $targetArrayKey = $k
                                        $targetParent = $parent
                                        break
                                    }
                                }
                                # Si pas trouvé, chercher n'importe quel tableau
                                if (-not $targetArray) {
                                    foreach ($k in $parent.Keys) {
                                        if ($parent[$k] -is [array]) {
                                            $targetArray = $parent[$k]
                                            $targetArrayKey = $k
                                            $targetParent = $parent
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    # Si on a trouvé un tableau, y ajouter l'élément
                    if ($targetArray -and $targetParent -and $targetArrayKey) {
                        # Ajouter l'élément au tableau en modifiant directement le parent
                        $targetParent[$targetArrayKey] = $targetParent[$targetArrayKey] + ,$newItem
                        # Mettre à jour toutes les références dans la stack
                        for ($si = 0; $si -lt $stack.Count; $si++) {
                            if ($stack[$si].isArray) {
                                # Vérifier si c'est le même tableau en comparant avec le parent
                                $stackParent = $null
                                if ($si -gt 0) {
                                    $stackParent = $stack[$si - 1].obj
                                } else {
                                    $stackParent = $result
                                }
                                if ($stackParent -is [hashtable] -and $stackParent.ContainsKey($targetArrayKey) -and $stackParent[$targetArrayKey] -is [array]) {
                                    if ($stack[$si].obj -eq $targetArray -or ($stackParent[$targetArrayKey] -eq $targetArray -and $stackParent[$targetArrayKey].Count -eq $targetArray.Count)) {
                                        $stack[$si].obj = $targetParent[$targetArrayKey]
                                    }
                                }
                            }
                        }
                        # Mettre à jour current si c'était le tableau
                        if ($current -eq $targetArray) {
                            $current = $targetParent[$targetArrayKey]
                        }
                        $stack += @{ indent = $indent; obj = $newItem; isArray = $false }
                        $current = $newItem
                        $currentIsArray = $false
                    } else {
                        # Fallback: chercher directement dans result pour les clés connues
                        $foundInResult = $false
                        foreach ($k in @('parameters', 'tags', 'required')) {
                            if ($result.ContainsKey($k) -and $result[$k] -is [array]) {
                                $result[$k] = $result[$k] + ,$newItem
                                $stack += @{ indent = $indent; obj = $newItem; isArray = $false }
                                $current = $newItem
                                $currentIsArray = $false
                                $foundInResult = $true
                                break
                            }
                        }
                        if (-not $foundInResult) {
                            # Créer un nouveau tableau et l'attacher au parent
                            $newArray = @($newItem)
                            if ($stack.Count -gt 0) {
                                $parent = $stack[-1].obj
                                if ($parent -is [hashtable]) {
                                    # Chercher une clé qui devrait être un tableau
                                    foreach ($k in @('parameters', 'tags')) {
                                        if ($parent.ContainsKey($k)) {
                                            $parent[$k] = $newArray
                                            break
                                        }
                                    }
                                }
                            }
                            $stack += @{ indent = $indent; obj = $newItem; isArray = $false }
                            $current = $newItem
                            $currentIsArray = $false
                        }
                    }
                    
                    # Traiter la valeur
                    if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^\$ref') {
                        if ($value -match '^\$ref') {
                            $refValue = $value -replace '^["'']|["'']$', ''
                            $current['$ref'] = $refValue
                        } else {
                            # Nouvel objet
                            $newObj = @{}
                            $current[$key] = $newObj
                            $stack += @{ indent = $indent + 2; obj = $newObj; isArray = $false }
                            $current = $newObj
                            $currentIsArray = $false
                        }
                    } else {
                        # Valeur simple
                        $current[$key] = $value -replace '^["'']|["'']$', ''
                    }
                } else {
                    # Élément de tableau simple (valeur directe)
                    if (-not $currentIsArray) {
                        # Créer un tableau
                        $newArray = @()
                        # Trouver la clé dans le parent
                        if ($stack.Count -gt 0) {
                            $parent = $stack[-1].obj
                            if ($parent -is [hashtable]) {
                                foreach ($k in $parent.Keys) {
                                    if ($parent[$k] -eq $current) {
                                        $parent[$k] = $newArray
                                        break
                                    }
                                }
                            }
                        }
                        $current = $newArray
                        $currentIsArray = $true
                        if ($stack.Count -gt 0) {
                            $stack[-1].obj = $newArray
                            $stack[-1].isArray = $true
                        }
                    }
                    $current += ,($itemContent -replace '^["'']|["'']$', '')
                }
            }
            # Détecter les clés avec valeurs (pas de -)
            elseif ($content -match '^([^:]+):\s*(.*)$') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                
                # Vérifier si cette clé devrait être un tableau
                $shouldBeArray = $arrayKeys.ContainsKey($key)
                
                # Traiter la valeur
                if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^\$ref') {
                    if ($key -eq '$ref' -or $value -match '^\$ref') {
                        # Référence
                        $refValue = $value -replace '^["'']|["'']$', ''
                        if ($key -eq '$ref') {
                            $current['$ref'] = $refValue
                        } else {
                            $refObj = @{}
                            $refObj['$ref'] = $refValue
                            $current[$key] = $refObj
                        }
                    } elseif ($shouldBeArray) {
                        # Créer un tableau vide qui sera rempli par les éléments suivants
                        $newArray = @()
                        $current[$key] = $newArray
                        $stack += @{ indent = $indent; obj = $newArray; isArray = $true }
                        $current = $newArray
                        $currentIsArray = $true
                    } else {
                        # Nouvel objet
                        $newObj = @{}
                        $current[$key] = $newObj
                        $stack += @{ indent = $indent; obj = $newObj; isArray = $false }
                        $current = $newObj
                        $currentIsArray = $false
                    }
                } elseif ($key -eq 'tags') {
                    # tags doit toujours être un tableau selon OpenAPI spec
                    if ($value -match '^\[(.+)\]$') {
                        # Array inline (ex: tags: [VMs] ou tags: [VMs, Health])
                        $items = $matches[1] -split ',' | ForEach-Object { $_.Trim() -replace '^["'']|["'']$', '' }
                        $current[$key] = $items
                    } else {
                        # Valeur simple sans brackets (ex: tags: VMs) -> convertir en tableau
                        $cleanValue = $value -replace '^["'']|["'']$', ''
                        $current[$key] = @($cleanValue)
                    }
                } elseif ($key -eq 'required') {
                    # required doit être un booléen selon OpenAPI spec
                    $cleanValue = $value.Trim() -replace '^["'']|["'']$', ''
                    $lowerValue = $cleanValue.ToLower()
                    if ($lowerValue -eq 'true') {
                        $current[$key] = $true
                    } elseif ($lowerValue -eq 'false') {
                        $current[$key] = $false
                    } else {
                        # Valeur inconnue, garder comme string (sera corrigé en post-processing)
                        $current[$key] = $cleanValue
                    }
                } elseif ($value -match '^\[(.+)\]$') {
                    # Array simple inline (ex: parameters: [param1, param2])
                    $items = $matches[1] -split ',' | ForEach-Object { $_.Trim() -replace '^["'']|["'']$', '' }
                    $current[$key] = $items
                } else {
                    # Valeur simple
                    $current[$key] = $value -replace '^["'']|["'']$', ''
                }
            }
        }
    }
    catch {
        Write-Warning "Error in Convert-HvoOpenApiYaml: $($_.Exception.Message)"
        Write-Warning $_.ScriptStackTrace
        return $result
    }
    
    return $result
}

function Repair-HvoOpenApiSpecStructure {
    param([hashtable]$Spec)
    
    if (-not $Spec -or $Spec.Count -eq 0) {
        return $Spec
    }
    
    # Créer une copie pour éviter de modifier pendant l'itération
    $fixed = @{}
    
    foreach ($key in $Spec.Keys) {
        $value = $Spec[$key]
        
        # Traiter les valeurs selon leur type
        if ($value -is [hashtable]) {
            $fixed[$key] = Repair-HvoOpenApiSpecStructure -Spec $value
        } elseif ($value -is [array]) {
            # Préserver le type array en utilisant @() et en modifiant in-place
            $arrayResult = @()
            foreach ($item in $value) {
                if ($item -is [hashtable]) {
                    $arrayResult += ,(Repair-HvoOpenApiSpecStructure -Spec $item)
                } else {
                    $arrayResult += ,$item
                }
            }
            $fixed[$key] = $arrayResult
        } else {
            $fixed[$key] = $value
        }
    }
    
    # Corriger les problèmes spécifiques
    
    # 1. Extraire responses de requestBody.content.application/json.schema.responses
    if ($fixed.ContainsKey('requestBody')) {
        $requestBody = $fixed['requestBody']
        if ($requestBody -is [hashtable]) {
            # Chercher responses dans requestBody.content.application/json.schema.responses
            if ($requestBody.ContainsKey('content')) {
                $content = $requestBody['content']
                if ($content -is [hashtable] -and $content.ContainsKey('application/json')) {
                    $appJson = $content['application/json']
                    if ($appJson -is [hashtable] -and $appJson.ContainsKey('schema')) {
                        $schema = $appJson['schema']
                        if ($schema -is [hashtable] -and $schema.ContainsKey('responses')) {
                            # Extraire responses et les déplacer au niveau de l'opération
                            $nestedResponses = $schema['responses']
                            if (-not $fixed.ContainsKey('responses')) {
                                $fixed['responses'] = $nestedResponses
                            } else {
                                # Fusionner avec les responses existantes (priorité aux existantes)
                                foreach ($respKey in $nestedResponses.Keys) {
                                    if (-not $fixed['responses'].ContainsKey($respKey)) {
                                        $fixed['responses'][$respKey] = $nestedResponses[$respKey]
                                    }
                                }
                            }
                            # Supprimer responses du schema
                            $schema.Remove('responses')
                            # Nettoyer le schema : si il ne reste que $ref, utiliser directement la référence
                            if ($schema.Count -eq 1 -and $schema.ContainsKey('$ref')) {
                                $appJson['schema'] = @{ '$ref' = $schema['$ref'] }
                            } elseif ($schema.Count -eq 0) {
                                # Si le schema est vide après suppression, le supprimer
                                $appJson.Remove('schema')
                            }
                        }
                    }
                }
            }
        }
    }
    
    # 2. Convertir required de string "true"/"false" en boolean
    if ($fixed.ContainsKey('required')) {
        $requiredValue = $fixed['required']
        if ($requiredValue -is [string]) {
            $lowerValue = $requiredValue.ToLower()
            if ($lowerValue -eq 'true') {
                $fixed['required'] = $true
            } elseif ($lowerValue -eq 'false') {
                $fixed['required'] = $false
            }
        }
    }
    
    # 3. S'assurer que tags est toujours un tableau
    if ($fixed.ContainsKey('tags')) {
        $tagsValue = $fixed['tags']
        if ($tagsValue -isnot [array]) {
            if ($tagsValue -is [string] -and $tagsValue -match '^\[(.+)\]$') {
                # Array inline (ex: [VMs] ou [VMs, Health])
                $items = $matches[1] -split ',' | ForEach-Object { $_.Trim() -replace '^["'']|["'']$', '' }
                $fixed['tags'] = $items
            } else {
                # Valeur simple -> convertir en tableau
                $cleanValue = $tagsValue -replace '^["'']|["'']$', ''
                $fixed['tags'] = @($cleanValue)
            }
        }
    }
    
    # 4. Corriger récursivement les required dans les paramètres et autres structures
    if ($fixed.ContainsKey('parameters')) {
        $parameters = $fixed['parameters']
        if ($parameters -is [array]) {
            # Préserver le tableau en modifiant les éléments in-place
            for ($i = 0; $i -lt $parameters.Count; $i++) {
                $param = $parameters[$i]
                if ($param -is [hashtable] -and $param.ContainsKey('required')) {
                    $reqVal = $param['required']
                    if ($reqVal -is [string]) {
                        $lowerVal = $reqVal.ToLower()
                        if ($lowerVal -eq 'true') {
                            $param['required'] = $true
                        } elseif ($lowerVal -eq 'false') {
                            $param['required'] = $false
                        }
                    }
                }
            }
            # S'assurer que parameters reste un tableau
            $fixed['parameters'] = $parameters
        }
    }
    
    return $fixed
}

function Add-HvoOpenApiSchemas {
    param($Spec)
    
    $Spec.components.schemas.Error = @{
        type = "object"
        properties = @{
            error = @{
                type = "string"
                description = "Message d'erreur lisible"
            }
            detail = @{
                type = "string"
                description = "Message technique optionnel"
            }
        }
        required = @("error")
    }
    
    $Spec.components.schemas.Vm = @{
        type = "object"
        properties = @{
            Name = @{ type = "string" }
            State = @{ type = "string" }
            CPUUsage = @{ type = "integer" }
            MemoryAssigned = @{ type = "integer" }
            Uptime = @{ type = "string" }
        }
    }
    
    $Spec.components.schemas.VmCreateRequest = @{
        type = "object"
        required = @("name", "memoryMB", "vcpu", "diskPath", "diskGB", "switchName")
        properties = @{
            name = @{
                type = "string"
                description = "Nom de la VM"
            }
            memoryMB = @{
                type = "integer"
                description = "Mémoire en MB"
            }
            vcpu = @{
                type = "integer"
                description = "Nombre de vCPU"
            }
            diskPath = @{
                type = "string"
                description = "Chemin du disque"
            }
            diskGB = @{
                type = "integer"
                description = "Taille du disque en GB"
            }
            switchName = @{
                type = "string"
                description = "Nom du switch virtuel"
            }
            isoPath = @{
                type = "string"
                description = "Chemin vers l'ISO (optionnel)"
            }
        }
    }
    
    $Spec.components.schemas.VmUpdateRequest = @{
        type = "object"
        properties = @{
            memoryMB = @{
                type = "integer"
                description = "Mémoire en MB"
            }
            vcpu = @{
                type = "integer"
                description = "Nombre de vCPU"
            }
            switchName = @{
                type = "string"
                description = "Nom du switch virtuel"
            }
            isoPath = @{
                type = "string"
                description = "Chemin vers l'ISO"
            }
        }
    }
    
    $Spec.components.schemas.VmActionResponse = @{
        type = "object"
        properties = @{
            created = @{ type = "string" }
            exists = @{ type = "string" }
            deleted = @{ type = "string" }
            started = @{ type = "string" }
            stopped = @{ type = "string" }
            restarted = @{ type = "string" }
            suspended = @{ type = "string" }
            resumed = @{ type = "string" }
            updated = @{ type = "boolean" }
            unchanged = @{ type = "boolean" }
            name = @{ type = "string" }
        }
    }
    
    $Spec.components.schemas.Switch = @{
        type = "object"
        properties = @{
            Name = @{ type = "string" }
            SwitchType = @{
                type = "string"
                enum = @("Internal", "Private", "External")
            }
            Notes = @{ type = "string" }
        }
    }
    
    $Spec.components.schemas.SwitchCreateRequest = @{
        type = "object"
        required = @("name", "type")
        properties = @{
            name = @{
                type = "string"
                description = "Nom du switch"
            }
            type = @{
                type = "string"
                enum = @("Internal", "Private", "External")
                description = "Type de switch"
            }
            netAdapterName = @{
                type = "string"
                description = "Nom de l'adaptateur réseau (requis pour External)"
            }
            notes = @{
                type = "string"
                description = "Notes optionnelles"
            }
        }
    }
    
    $Spec.components.schemas.SwitchUpdateRequest = @{
        type = "object"
        properties = @{
            notes = @{
                type = "string"
                description = "Notes"
            }
        }
    }
    
    $Spec.components.schemas.HealthResponse = @{
        type = "object"
        properties = @{
            status = @{ type = "string" }
            config = @{ type = "object" }
            root = @{ type = "string" }
            time = @{
                type = "string"
                format = "date-time"
            }
        }
    }
}

function Add-HvoOpenApiResponses {
    param($Spec)
    
    $Spec.components.responses.Error = @{
        description = "Erreur serveur"
        content = @{
            "application/json" = @{
                schema = @{ '$ref' = "#/components/schemas/Error" }
            }
        }
    }
    
    $Spec.components.responses.NotFound = @{
        description = "Ressource non trouvée"
        content = @{
            "application/json" = @{
                schema = @{ '$ref' = "#/components/schemas/Error" }
            }
        }
    }
    
    $Spec.components.responses.BadRequest = @{
        description = "Requête invalide"
        content = @{
            "application/json" = @{
                schema = @{ '$ref' = "#/components/schemas/Error" }
            }
        }
    }
}

Export-ModuleMember -Function *


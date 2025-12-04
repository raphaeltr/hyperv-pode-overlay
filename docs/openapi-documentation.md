# Documentation OpenAPI - Guide d'implémentation et d'utilisation

Ce guide explique comment documenter les routes de l'API avec des commentaires inline pour générer automatiquement la spécification OpenAPI v3.

## Vue d'ensemble

Le système de génération OpenAPI permet de maintenir la documentation synchronisée avec le code en utilisant des commentaires inline dans les fichiers de routes. La documentation est générée automatiquement à partir de ces commentaires, similaire à l'approche de safrs (Python) ou swagger-jsdoc (Node.js).

## Format des commentaires @openapi

Chaque route doit être documentée avec un bloc de commentaires précédant l'appel `Add-PodeRoute`. Le format utilise une syntaxe YAML simplifiée dans les commentaires PowerShell.

### Structure de base

```powershell
# @openapi
# path: /endpoint
# method: GET
# summary: Description courte
# description: Description détaillée (optionnel)
# tags: [Tag1, Tag2]
# responses:
#   200:
#     description: Succès
#     content:
#       application/json:
#         schema:
#           type: object
Add-PodeRoute -Method Get -Path '/endpoint' -ScriptBlock {
    # ...
}
```

### Éléments obligatoires

- `# @openapi` : Marqueur de début du bloc de documentation
- `path` : Chemin de l'endpoint (utiliser `{name}` pour les paramètres de chemin)
- `method` : Méthode HTTP (GET, POST, PUT, DELETE, etc.)
- `summary` : Description courte de l'endpoint
- `responses` : Au moins une réponse doit être définie

### Éléments optionnels

- `description` : Description détaillée de l'endpoint
- `tags` : Tableau de tags pour organiser les endpoints
- `parameters` : Paramètres de chemin, query ou header
- `requestBody` : Corps de la requête pour POST/PUT
- `deprecated` : Marquer un endpoint comme déprécié

## Exemples de documentation

### Endpoint GET simple

```powershell
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
    # ...
}
```

### Endpoint avec paramètre de chemin

```powershell
# @openapi
# path: /vms/{name}
# method: GET
# summary: Récupère les détails d'une VM
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
Add-PodeRoute -Method Get -Path '/vms/:name' -ScriptBlock {
    # ...
}
```

**Note importante** : Dans le code Pode, utilisez `:name` pour les paramètres de chemin, mais dans la documentation OpenAPI, utilisez `{name}`. Le parser convertit automatiquement `:name` en `{name}`.

### Endpoint POST avec requestBody

```powershell
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
Add-PodeRoute -Method Post -Path '/vms' -ScriptBlock {
    # ...
}
```

### Endpoint avec paramètres query

```powershell
# @openapi
# path: /vms/{name}/stop
# method: POST
# summary: Arrête une machine virtuelle
# tags: [VMs]
# parameters:
#   - name: name
#     in: path
#     required: true
#     schema:
#       type: string
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
Add-PodeRoute -Method Post -Path '/vms/:name/stop' -ScriptBlock {
    # ...
}
```

## Utilisation des références ($ref)

Pour éviter la duplication, utilisez des références vers les schémas et réponses communes définis dans le module OpenAPI.

### Références aux schémas

```yaml
# schema:
#   $ref: '#/components/schemas/Vm'
```

### Références aux réponses communes

```yaml
# 404:
#   $ref: '#/components/responses/NotFound'
# 500:
#   $ref: '#/components/responses/Error'
```

## Schémas disponibles

Les schémas suivants sont prédéfinis dans le module OpenAPI :

### Schémas de données

- `Error` : Structure d'erreur standard avec `error` et `detail`
- `Vm` : Objet VM avec Name, State, CPUUsage, MemoryAssigned, Uptime
- `VmCreateRequest` : Requête de création de VM
- `VmUpdateRequest` : Requête de mise à jour de VM
- `VmActionResponse` : Réponses des actions VM (created, exists, deleted, etc.)
- `Switch` : Objet Switch avec Name, SwitchType, Notes
- `SwitchCreateRequest` : Requête de création de switch
- `SwitchUpdateRequest` : Requête de mise à jour de switch
- `HealthResponse` : Réponse du health check

### Réponses communes

- `Error` : Erreur serveur (500)
- `NotFound` : Ressource non trouvée (404)
- `BadRequest` : Requête invalide (400)

## Génération de la documentation

### Génération statique

Génère un fichier `openapi.json` à partir des commentaires :

```powershell
pwsh src/scripts/generate-openapi.ps1
```

Le fichier est généré par défaut dans `docs/openapi.json`. Vous pouvez spécifier un chemin personnalisé :

```powershell
pwsh src/scripts/generate-openapi.ps1 -OutputPath "./custom-path/openapi.json"
```

Le script utilise automatiquement la configuration du serveur (`config.ps1`) pour déterminer l'URL de base. Vous pouvez également la spécifier manuellement :

```powershell
pwsh src/scripts/generate-openapi.ps1 -BaseUrl "http://example.com:8080"
```

### Génération dynamique

La route `/openapi.json` expose la spécification OpenAPI générée à la volée :

```bash
curl http://localhost:8080/openapi.json
```

Cette route génère la documentation en temps réel à partir des commentaires du code, garantissant qu'elle est toujours à jour avec l'implémentation.

## Règles et bonnes pratiques

### Règles de formatage

1. **Marqueur @openapi** : Doit être sur une ligne séparée, précédé de `#`
2. **Indentation** : Utilisez 2 espaces pour chaque niveau d'indentation
3. **Commentaires** : Toutes les lignes de documentation doivent commencer par `#`
4. **Bloc continu** : Le bloc de commentaires doit être continu jusqu'à l'appel `Add-PodeRoute`

### Conversion des chemins

- **Dans le code Pode** : Utilisez `:name` pour les paramètres de chemin
- **Dans la documentation** : Utilisez `{name}` pour les paramètres de chemin
- Le parser convertit automatiquement `:name` en `{name}` lors de la génération

### Tags

Utilisez des tags cohérents pour organiser les endpoints :

- `[VMs]` : Endpoints liés aux machines virtuelles
- `[Switches]` : Endpoints liés aux switches virtuels
- `[Health]` : Endpoints de santé
- `[Meta]` : Endpoints métadonnées (comme `/openapi.json`)

### Réponses

1. **Toujours documenter les codes de statut possibles** : 200, 201, 400, 404, 500, etc.
2. **Utiliser les références communes** : Préférer `$ref: '#/components/responses/Error'` plutôt que de redéfinir
3. **Décrire les réponses** : Ajouter une description pour chaque réponse
4. **Schémas de contenu** : Spécifier le schéma JSON pour les réponses 200/201

### Paramètres

1. **Paramètres de chemin** : Toujours marqués comme `required: true`
2. **Paramètres query** : Marquer `required: false` si optionnels
3. **Descriptions** : Ajouter une description pour chaque paramètre

### RequestBody

1. **Required** : Spécifier si le body est obligatoire (`required: true/false`)
2. **Schémas** : Utiliser des références vers les schémas prédéfinis quand possible
3. **Content-Type** : Toujours spécifier `application/json`

## Structure des fichiers

Les fichiers de routes doivent suivre cette structure :

```
function global:Add-HvoXxxRoutes {
    
    # @openapi
    # ... documentation ...
    Add-PodeRoute -Method Get -Path '/endpoint' -ScriptBlock {
        # Implémentation
    }
    
    # @openapi
    # ... documentation ...
    Add-PodeRoute -Method Post -Path '/endpoint' -ScriptBlock {
        # Implémentation
    }
}
```

## Vérification de la documentation

### Vérifier la génération

Après avoir ajouté ou modifié des commentaires, testez la génération :

```powershell
# Générer le fichier
pwsh src/scripts/generate-openapi.ps1

# Vérifier que le fichier est valide (optionnel, nécessite des outils externes)
# npx swagger-cli validate docs/openapi.json
```

### Visualiser la documentation

Une fois généré, vous pouvez visualiser la documentation avec :

- **Swagger UI** : https://swagger.io/tools/swagger-ui/
- **Redoc** : https://github.com/Redocly/redoc
- **Postman** : Import du fichier `openapi.json`

### Exemple avec Swagger UI

```bash
# Installer swagger-ui (via Docker)
docker run -p 8081:8080 -e SWAGGER_JSON=/openapi.json -v $(pwd)/docs:/openapi swaggerapi/swagger-ui

# Accéder à http://localhost:8081
```

## Dépannage

### Le parser ne détecte pas les commentaires

1. Vérifiez que `# @openapi` est sur une ligne séparée
2. Vérifiez qu'il n'y a pas de lignes vides entre `# @openapi` et les autres commentaires
3. Vérifiez que le bloc de commentaires se termine juste avant `Add-PodeRoute`

### Les paramètres de chemin ne sont pas convertis

Assurez-vous que dans la documentation, vous utilisez `{name}` et non `:name`. Le parser convertit `:name` du code en `{name}` dans le spec, mais dans la documentation inline, utilisez directement `{name}`.

### Les références $ref ne fonctionnent pas

1. Vérifiez que le schéma ou la réponse existe dans `Add-OpenApiSchemas` ou `Add-OpenApiResponses`
2. Vérifiez la syntaxe : `$ref: '#/components/schemas/Vm'` (avec le `#` au début)
3. Vérifiez l'indentation : la référence doit être au bon niveau

### Erreurs de génération

Si la génération échoue :

1. Vérifiez les logs du script pour identifier l'endpoint problématique
2. Vérifiez la syntaxe YAML dans les commentaires
3. Vérifiez que tous les champs obligatoires sont présents

## Ajout de nouveaux schémas

Pour ajouter un nouveau schéma réutilisable :

1. Modifiez `src/modules/HvoOpenApi/HvoOpenApi.psm1`
2. Ajoutez le schéma dans la fonction `Add-OpenApiSchemas` :

```powershell
$Spec.components.schemas.NouveauSchema = @{
    type = "object"
    properties = @{
        champ1 = @{ type = "string" }
        champ2 = @{ type = "integer" }
    }
    required = @("champ1")
}
```

3. Utilisez-le dans vos commentaires avec `$ref: '#/components/schemas/NouveauSchema'`

## Exemple complet

Voici un exemple complet d'endpoint documenté :

```powershell
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
        # ... implémentation ...
    }
    catch {
        # ... gestion d'erreur ...
    }
}
```

## Avantages de cette approche

1. **Documentation à jour** : La documentation est toujours synchronisée avec le code
2. **Moins de maintenance** : Pas besoin de maintenir un fichier OpenAPI séparé
3. **Documentation inline** : La documentation est visible directement dans le code
4. **Génération automatique** : Pas besoin de générer manuellement la spécification
5. **Standards** : Compatible avec tous les outils OpenAPI (Swagger UI, Redoc, Postman, etc.)

## Ressources

- [Spécification OpenAPI 3.0](https://swagger.io/specification/)
- [Swagger UI](https://swagger.io/tools/swagger-ui/)
- [Redoc](https://github.com/Redocly/redoc)


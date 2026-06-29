[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string[]]$ProjectDir,

    [string]$ProfilePath = 'D:\Codex--A\pinterest-interior-design-search\preferences\profile.json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($true))
}

function Get-PropertyValue {
    param($Object, [string]$Name, $Default)
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $Default
}

function New-EmptyProfile {
    return [ordered]@{
        schemaVersion = 1
        updatedAt = [datetime]::UtcNow.ToString('o')
        rules = [ordered]@{
            minimumEffectiveBehaviors = 3
            minimumProjects = 2
            rankingConfidenceThreshold = 0.70
            queryConfidenceThreshold = 0.80
            unselectedIsNegative = $false
        }
        scopes = [ordered]@{}
    }
}

function Add-Weight {
    param([hashtable]$Weights, [string]$Name, [double]$Delta)
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    $key = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+','_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($key)) { return }
    if (-not $Weights.ContainsKey($key)) { $Weights[$key] = 0.0 }
    $Weights[$key] = [math]::Round(([double]$Weights[$key] + $Delta), 4)
}

$profile = $null
if (Test-Path -LiteralPath $ProfilePath -PathType Leaf) {
    $profile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding utf8 | ConvertFrom-Json
} else {
    $profile = [pscustomobject](New-EmptyProfile)
}

$scopeEvents = @{}
foreach ($dir in $ProjectDir) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "ProjectDir does not exist: $dir" }
    $manifestPath = Join-Path $dir 'manifest.json'
    $batchPath = Join-Path $dir 'reviews\batch-review.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "manifest.json is missing in $dir" }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $scope = [string](Get-PropertyValue $manifest 'preferenceScopeKey' '')
    if ([string]::IsNullOrWhiteSpace($scope)) { continue }
    if (-not $scopeEvents.ContainsKey($scope)) {
        $scopeEvents[$scope] = [ordered]@{ projects=@{}; positive=@(); negative=@(); weights=@{} }
    }
    $bucket = $scopeEvents[$scope]
    $bucket.projects[[string](Get-PropertyValue $manifest 'projectName' (Split-Path -Leaf $dir))] = $true
    $behaviors = @()
    if (Test-Path -LiteralPath $batchPath -PathType Leaf) {
        $batch = Get-Content -LiteralPath $batchPath -Raw -Encoding utf8 | ConvertFrom-Json
        $behaviors += @(Get-PropertyValue $batch 'effectiveBehaviors' @())
        $hardRejections = @(Get-PropertyValue $batch 'hardRejections' @())
        foreach ($rejection in $hardRejections) {
            $bucket.negative += $rejection
            Add-Weight $bucket.weights ([string](Get-PropertyValue $rejection 'reason' 'hard_rejection')) -0.25
        }
    }
    foreach ($behavior in $behaviors) {
        $type = [string](Get-PropertyValue $behavior 'type' '')
        if (@('final_selection','large_download_success','moodboard_add','quality_replacement') -notcontains $type) { continue }
        $candidateNumber = [int](Get-PropertyValue $behavior 'candidateNumber' 0)
        $candidate = @($manifest.candidates | Where-Object { [int]$_.number -eq $candidateNumber }) | Select-Object -First 1
        if ($null -eq $candidate) { continue }
        $bucket.positive += $behavior
        Add-Weight $bucket.weights ([string](Get-PropertyValue $candidate 'spaceRole' '')) 0.20
        Add-Weight $bucket.weights ([string](Get-PropertyValue $candidate 'visualSourceType' '')) 0.08
        if ([bool](Get-PropertyValue $candidate 'fullSpace' $false)) { Add-Weight $bucket.weights 'full_space' 0.22 }
        if ([double](Get-PropertyValue $candidate 'subjectOccupancyScore' 0) -ge 8) { Add-Weight $bucket.weights 'strong_subject_occupancy' 0.10 }
        $evidence = [string](Get-PropertyValue $candidate 'visualQualityEvidence' '')
        foreach ($term in @('stone','wood','warm','neutral','vanity','full space','wide','built project','lighting')) {
            if ($evidence.ToLowerInvariant().Contains($term)) { Add-Weight $bucket.weights ($term -replace ' ','_') 0.06 }
        }
    }
}

if (-not ($profile.PSObject.Properties.Name -contains 'scopes')) {
    $profile | Add-Member -NotePropertyName scopes -NotePropertyValue ([pscustomobject]@{})
}

$scopesObject = [ordered]@{}
foreach ($existing in $profile.scopes.PSObject.Properties.Name) {
    $scopesObject[$existing] = $profile.scopes.$existing
}

foreach ($scope in $scopeEvents.Keys) {
    $bucket = $scopeEvents[$scope]
    $effectiveCount = @($bucket.positive).Count + @($bucket.negative).Count
    $projectCount = @($bucket.projects.Keys).Count
    $confidence = [math]::Min(0.95, [math]::Round(0.45 + ($effectiveCount * 0.07) + ($projectCount * 0.10), 2))
    $activeForRanking = ($effectiveCount -ge 3 -and $projectCount -ge 2 -and $confidence -ge 0.70)
    $mayAffectSearchTerms = ($activeForRanking -and $confidence -ge 0.80)
    $mayAffectRoundExpansion = ($activeForRanking -and $confidence -ge 0.80)
    $scopesObject[$scope] = [ordered]@{
        scope = $scope
        effectiveBehaviorCount = $effectiveCount
        projectCount = $projectCount
        confidence = $confidence
        activeForRanking = $activeForRanking
        mayAffectSearchTerms = $mayAffectSearchTerms
        mayAffectRoundExpansion = $mayAffectRoundExpansion
        weights = $bucket.weights
        positiveBehaviorTypes = @($bucket.positive | ForEach-Object { Get-PropertyValue $_ 'type' '' } | Sort-Object -Unique)
        note = 'Unselected candidates are intentionally ignored and are not negative feedback.'
        updatedAt = [datetime]::UtcNow.ToString('o')
    }
}

$output = [ordered]@{
    schemaVersion = 1
    updatedAt = [datetime]::UtcNow.ToString('o')
    rules = [ordered]@{
        minimumEffectiveBehaviors = 3
        minimumProjects = 2
        rankingConfidenceThreshold = 0.70
        queryConfidenceThreshold = 0.80
        unselectedIsNegative = $false
    }
    scopes = $scopesObject
}

Write-Utf8File -Path $ProfilePath -Content ($output | ConvertTo-Json -Depth 12)
Write-Output $ProfilePath

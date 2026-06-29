[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Build','SelectLarge')]
    [string]$Action,

    [string]$InputDir,
    [string]$OutputRoot,
    [string]$Topic,
    [string]$Style,
    [string]$SearchQuery,
    [string]$ProjectDate,
    [string]$SourceMetadata,
    [string]$SearchAttemptLog,
    [string]$ProjectDir,
    [string]$LargeInputDir,
    [string]$LargeSourceMetadata,
    [int[]]$CandidateNumber,
    [string[]]$Role,
    [switch]$Interior,
    [ValidateRange(1,16)]
    [int]$RequestedDownloadCount = 2,
    [ValidateRange(0,16)]
    [int]$ConfirmedDownloadCount = 0,
    [ValidateRange(1,16)]
    [int]$CandidateLimit = 16,
    [ValidateRange(1,16)]
    [int]$MinimumCandidateCount = 10,
    [string]$ProjectType = 'general',
    [string]$OutputUse = 'presentation'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($true))
}

function Get-SafeName {
    param([string]$Value, [string]$Fallback)
    $name = ($Value -replace '[<>:"/\\|?*]', '-' -replace '\s+', '-').Trim(' ', '.', '-')
    if ([string]::IsNullOrWhiteSpace($name)) { return $Fallback }
    return $name
}

function Get-Slug {
    param([string]$Value, [string]$Fallback)
    $raw = [string]$Value
    $slug = ($raw.ToLowerInvariant() -replace '[^a-z0-9]+', '-' -replace '-+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($slug)) { return $Fallback }
    return $slug
}

function Get-RoomSlug {
    param([string]$Topic, [string]$SearchQuery)
    $text = (($Topic + ' ' + $SearchQuery).ToLowerInvariant())
    if ($text -match 'bathroom|master\s*bath|primary\s*bath|主卫|卫生间|浴室') { return 'bathroom' }
    if ($text -match 'living\s*room|客厅') { return 'living-room' }
    if ($text -match 'bedroom|master\s*bedroom|主卧|卧室') { return 'bedroom' }
    if ($text -match 'study|home\s*office|书房') { return 'study' }
    if ($text -match 'dining|餐厅') { return 'dining-room' }
    if ($text -match 'kitchen|厨房') { return 'kitchen' }
    if ($text -match 'foyer|entry|玄关') { return 'entry' }
    return (Get-Slug $Topic 'interior')
}

function Get-CompactSearchSlug {
    param([string]$SearchQuery, [string]$Topic)
    $stop = @('interior','design','completed','project','photography','premium','visualization','photo','images','image','room','primary','master')
    $tokens = @((([string]$SearchQuery).ToLowerInvariant() -split '[^a-z0-9]+') | Where-Object { $_ -and $_.Length -gt 1 -and ($stop -notcontains $_) })
    $unique = @()
    foreach ($token in $tokens) {
        if ($unique.Count -ge 3) { break }
        if ($unique -notcontains $token) { $unique += $token }
    }
    $room = Get-RoomSlug $Topic $SearchQuery
    if (($unique -join '-') -notmatch [regex]::Escape($room)) { $unique += ($room -split '-')[0] }
    $slug = ($unique | Select-Object -First 6) -join '-'
    return (Get-Slug $slug $room)
}

function Get-PreferenceScopeKey {
    param([string]$ProjectType, [string]$Topic, [string]$SearchQuery, [string]$OutputUse)
    $projectSlug = Get-Slug $ProjectType 'general'
    $roomSlug = Get-RoomSlug $Topic $SearchQuery
    $useSlug = Get-Slug $OutputUse 'presentation'
    return "$projectSlug|$roomSlug|$useSlug"
}

function Get-PreferenceScore {
    param([string]$ProfilePath, [string]$ScopeKey, $Metadata)
    if (-not $ProfilePath -or -not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) { return 0.0 }
    try {
        $profile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding utf8 | ConvertFrom-Json
        $scope = $null
        if ($profile.PSObject.Properties.Name -contains 'scopes') {
            $scope = $profile.scopes.PSObject.Properties[$ScopeKey].Value
        }
        if ($null -eq $scope) { return 0.0 }
        $active = [bool](Get-PropertyValue $scope 'activeForRanking' $false)
        if (-not $active) { return 0.0 }
        $weights = Get-PropertyValue $scope 'weights' $null
        if ($null -eq $weights) { return 0.0 }
        $score = 0.0
        $matched = 0
        foreach ($name in $weights.PSObject.Properties.Name) {
            $weight = [double]$weights.$name
            $hasSignal = $false
            $spaceRole = [string](Get-PropertyValue $Metadata 'SpaceRole' '')
            $visualSourceType = [string](Get-PropertyValue $Metadata 'VisualSourceType' '')
            $evidence = ([string](Get-PropertyValue $Metadata 'VisualQualityEvidence' '')).ToLowerInvariant()
            if ($name -eq $spaceRole -or $name -eq $visualSourceType -or $evidence.Contains($name.Replace('_',' '))) { $hasSignal = $true }
            if ($hasSignal) {
                $score += $weight
                $matched++
            }
        }
        if ($matched -eq 0) { return 0.0 }
        return [math]::Max(-10.0, [math]::Min(10.0, [math]::Round($score * 10.0, 2)))
    } catch {
        return 0.0
    }
}

function Get-DiversityScore {
    param([array]$ExistingCandidates, $Metadata)
    if (-not $ExistingCandidates -or $ExistingCandidates.Count -eq 0) { return 5.0 }
    $role = [string](Get-PropertyValue $Metadata 'SpaceRole' '')
    $sourceType = [string](Get-PropertyValue $Metadata 'VisualSourceType' '')
    $sameRole = @($ExistingCandidates | Where-Object { $_.spaceRole -eq $role }).Count
    $sameType = @($ExistingCandidates | Where-Object { $_.visualSourceType -eq $sourceType }).Count
    $score = 5.0 - ([math]::Min(3, $sameRole) * 0.8) - ([math]::Min(2, $sameType) * 0.4)
    return [math]::Max(0.0, [math]::Round($score, 2))
}

function Get-ProjectDate {
    param([string]$RequestedDate)
    if ($RequestedDate) {
        $parsed = [datetime]::ParseExact($RequestedDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        return $parsed.ToString('yyyy-MM-dd')
    }
    try {
        $zone = [TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
        return [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $zone).ToString('yyyy-MM-dd')
    } catch {
        return [datetime]::Now.ToString('yyyy-MM-dd')
    }
}

function Get-ImageDimensions {
    param([string]$Path)
    try {
        $image = [Drawing.Image]::FromFile($Path)
        try { return [pscustomobject]@{ Width=$image.Width; Height=$image.Height; PreviewPath=$Path } }
        finally { $image.Dispose() }
    } catch {
        $ffprobe = Get-Command ffprobe -ErrorAction SilentlyContinue
        if ($ffprobe) {
            $raw = & $ffprobe.Source -v quiet -print_format json -show_streams $Path
            if ($LASTEXITCODE -eq 0 -and $raw) {
                $info = $raw | ConvertFrom-Json
                $stream = $info.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
                if ($stream) {
                    $previewPath = Join-Path ([IO.Path]::GetTempPath()) (([guid]::NewGuid().ToString('N')) + '.jpg')
                    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
                    if ($ffmpeg) {
                        & $ffmpeg.Source -loglevel error -y -i $Path -frames:v 1 $previewPath 2>$null
                        if ($LASTEXITCODE -ne 0) { $previewPath = $null }
                    }
                    return [pscustomobject]@{ Width=[int]$stream.width; Height=[int]$stream.height; PreviewPath=$previewPath }
                }
            }
        }
        return [pscustomobject]@{ Width=0; Height=0; PreviewPath=$null }
    }
}

function Get-MetadataMap {
    param([string]$Path)
    $map = @{}
    if ($Path) {
        $records = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
        foreach ($record in @($records)) { $map[[string]$record.FileName] = $record }
    }
    return $map
}

function Get-LargeMetadataMap {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'LargeSourceMetadata is required for SelectLarge.'
    }
    $map = @{}
    $records = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
    foreach ($record in @($records)) {
        $number = [int](Get-PropertyValue $record 'CandidateNumber' 0)
        if ($number -le 0 -or $map.ContainsKey($number)) { throw 'LargeSourceMetadata contains an invalid or duplicate CandidateNumber.' }
        $map[$number] = $record
    }
    return $map
}

function Get-PropertyValue {
    param($Object, [string]$Name, $Default)
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function Set-ObjectProperty {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.PSObject.Properties[$Name].Value = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Assert-SearchQuery {
    param([string]$Value, [int]$Round = 1, [array]$CauseCodes = @(), [array]$CorrectionActions = @())
    $hardForbidden = '(?i)(3\s*:\s*2|4\s*:\s*3|16\s*:\s*9|\b\d+\s*(px|pixels?)\b|resolution)'
    if ($Value -match $hardForbidden) { throw 'SearchQuery must not contain aspect ratio, pixel-dimension, or resolution terms.' }
    if ($Value -match '(?i)(portrait|vertical)') { throw 'SearchQuery must not contain portrait or vertical orientation terms.' }
    if ($Value -match '(?i)(landscape|horizontal)') {
        $allowedForAspect = ($Round -gt 1) -and ((@($CauseCodes) -contains 'ASPECT_GATE_LOW') -or (@($CauseCodes) -contains 'LANDSCAPE_COVERAGE_LOW') -or (@($CorrectionActions) -contains 'strengthen-aspect-coverage'))
        if (-not $allowedForAspect) { throw 'SearchQuery may use landscape or horizontal terms only after an aspect-gate issue.' }
    }
}

function Get-SearchAttemptData {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'SearchAttemptLog is required for Build.' }
    $parsedRecords = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
    $records = @()
    foreach ($parsedRecord in $parsedRecords) { $records += $parsedRecord }
    if ($records.Count -lt 1 -or $records.Count -gt 4) { throw 'SearchAttemptLog must contain 1-4 rounds.' }
    $attempts = @()
    $issues = @()
    $allowedCorrections = @('broaden-query','change-language','use-similar-seed','replace-similar-seed','strengthen-room-type','strengthen-quality-terms','strengthen-aspect-coverage','recover-page-state')
    $previousAttempt = $null
    foreach ($record in $records) {
        $round = [int](Get-PropertyValue $record 'Round' 0)
        $method = [string](Get-PropertyValue $record 'Method' '')
        $query = [string](Get-PropertyValue $record 'Query' '')
        $seedPinUrl = [string](Get-PropertyValue $record 'SeedPinUrl' '')
        $rawCount = [int](Get-PropertyValue $record 'RawPinCount' -1)
        $validCount = [int](Get-PropertyValue $record 'ValidPreviewCount' -1)
        $cumulativeValidCount = [int](Get-PropertyValue $record 'CumulativeValidPreviewCount' $validCount)
        $landscapePreviewCount = [int](Get-PropertyValue $record 'LandscapePreviewCount' -1)
        $cumulativeLandscapeCount = [int](Get-PropertyValue $record 'CumulativeLandscapePreviewCount' $landscapePreviewCount)
        $eligibleValue = Get-PropertyValue $record 'EligibleVisualCount' $null
        if ($null -eq $eligibleValue) { throw "Search round $round requires EligibleVisualCount." }
        $eligibleCount = [int]$eligibleValue
        $pageStatus = [string](Get-PropertyValue $record 'PageStatus' '')
        $timestamp = [string](Get-PropertyValue $record 'Timestamp' '')
        $addressesRound = [int](Get-PropertyValue $record 'AddressesRound' 0)
        $correctionActions = @(Get-PropertyValue $record 'CorrectionActions' @())
        $adjustmentSummary = [string](Get-PropertyValue $record 'AdjustmentSummary' '')
        $rejections = @(Get-PropertyValue $record 'RejectionReasons' @())
        $causeCodes = @(Get-PropertyValue $record 'CauseCodes' @())
        $isDomTimeout = @($causeCodes) -contains 'DOM_READ_TIMEOUT'
        $isAspectLow = ((@($causeCodes) -contains 'ASPECT_GATE_LOW') -or (@($causeCodes) -contains 'LANDSCAPE_COVERAGE_LOW'))
        if ($round -ne ($attempts.Count + 1)) { throw 'SearchAttemptLog rounds must be sequential from 1.' }
        if (@('keyword','similar') -notcontains $method) { throw "Search round $round has an invalid Method." }
        foreach ($action in $correctionActions) {
            if ($allowedCorrections -notcontains [string]$action) { throw "Search round $round has an invalid CorrectionActions value: $action." }
        }
        if ($method -eq 'keyword') {
            if ([string]::IsNullOrWhiteSpace($query)) { throw "Search round $round requires Query." }
            Assert-SearchQuery $query $round $causeCodes $correctionActions
        } elseif ($seedPinUrl -notmatch '^https://([a-z]+\.)?pinterest\.[^/]+/pin/') { throw "Search round $round requires a valid SeedPinUrl." }
        if ($rawCount -lt 0 -or $validCount -lt 0 -or $eligibleCount -lt 0 -or $validCount -gt $rawCount -or $eligibleCount -gt $validCount) { throw "Search round $round has invalid counts." }
        if ($cumulativeValidCount -lt $validCount) { throw "Search round $round has invalid cumulative valid count." }
        if ($landscapePreviewCount -ge 0 -and $landscapePreviewCount -gt $validCount) { throw "Search round $round has invalid landscape count." }
        if ($cumulativeLandscapeCount -ge 0 -and $cumulativeLandscapeCount -gt $cumulativeValidCount) { throw "Search round $round has invalid cumulative landscape count." }
        if ([string]::IsNullOrWhiteSpace($pageStatus) -or [string]::IsNullOrWhiteSpace($timestamp)) { throw "Search round $round requires PageStatus and Timestamp." }
        if ($null -ne $previousAttempt) {
            $previousNeedsCorrection = (($previousAttempt.cumulativeValidPreviewCount -lt 10 -and -not (@($previousAttempt.causeCodes) -contains 'DOM_READ_TIMEOUT')) -or (@($previousAttempt.causeCodes) -contains 'ASPECT_GATE_LOW') -or (@($previousAttempt.causeCodes) -contains 'LANDSCAPE_COVERAGE_LOW') -or (@($previousAttempt.causeCodes) -contains 'DOM_READ_TIMEOUT'))
            if ($previousNeedsCorrection) {
                if ($addressesRound -ne $previousAttempt.round) { throw "Search round $round must address failed round $($previousAttempt.round)." }
                if ($correctionActions.Count -eq 0 -or [string]::IsNullOrWhiteSpace($adjustmentSummary)) { throw "Search round $round requires CorrectionActions and AdjustmentSummary." }
                $sameDiscovery = $false
                if ($method -eq $previousAttempt.method) {
                    if ($method -eq 'keyword') { $sameDiscovery = $query.Trim().ToLowerInvariant() -eq $previousAttempt.query.Trim().ToLowerInvariant() }
                    else { $sameDiscovery = $seedPinUrl.TrimEnd('/') -eq $previousAttempt.seedPinUrl.TrimEnd('/') }
                }
                if ($sameDiscovery) { $allowSameDomRetry = ((@($previousAttempt.causeCodes) -contains 'DOM_READ_TIMEOUT') -and (@($correctionActions) -contains 'recover-page-state')); if (-not $allowSameDomRetry) { throw "Search round $round repeats the prior failed query or seed." } }
                $previousIssue = @($issues | Where-Object { $_.round -eq $previousAttempt.round }) | Select-Object -First 1
                if ($previousIssue) {
                    $previousIssue.addressesRound = $addressesRound
                    $previousIssue.correctionActions = $correctionActions
                    $previousIssue.adjustmentSummary = $adjustmentSummary
                    if (($cumulativeValidCount -ge 10) -and (-not $isAspectLow) -and (-not $isDomTimeout)) { $previousIssue.resolvedByRound = $round }
                }
            }
        }
        $attempt = [ordered]@{ round=$round; method=$method; query=$query; seedPinUrl=$seedPinUrl; rawPinCount=$rawCount; validPreviewCount=$validCount; cumulativeValidPreviewCount=$cumulativeValidCount; landscapePreviewCount=$landscapePreviewCount; cumulativeLandscapePreviewCount=$cumulativeLandscapeCount; eligibleVisualCount=$eligibleCount; rejectionReasons=$rejections; causeCodes=$causeCodes; addressesRound=$addressesRound; correctionActions=$correctionActions; adjustmentSummary=$adjustmentSummary; pageStatus=$pageStatus; timestamp=$timestamp }
        $attemptObject = [pscustomobject]$attempt
        $attempts += $attemptObject
        if ($cumulativeValidCount -lt 10 -and -not $isDomTimeout) {
            if ($causeCodes.Count -eq 0) { throw "Search round $round requires CauseCodes for LOW_PREVIEW_COUNT." }
            $issues += [pscustomobject][ordered]@{ code='LOW_PREVIEW_COUNT'; round=$round; method=$method; query=$query; seedPinUrl=$seedPinUrl; rawPinCount=$rawCount; validPreviewCount=$validCount; cumulativeValidPreviewCount=$cumulativeValidCount; landscapePreviewCount=$landscapePreviewCount; cumulativeLandscapePreviewCount=$cumulativeLandscapeCount; eligibleVisualCount=$eligibleCount; rejectionReasons=$rejections; causeCodes=$causeCodes; addressesRound=0; correctionActions=@(); adjustmentSummary=''; resolvedByRound=0; pageStatus=$pageStatus; timestamp=$timestamp }
        }
        if ($isAspectLow) {
            if ($causeCodes.Count -eq 0) { throw "Search round $round requires CauseCodes for ASPECT_GATE_LOW." }
            $issues += [pscustomobject][ordered]@{ code='ASPECT_GATE_LOW'; round=$round; method=$method; query=$query; seedPinUrl=$seedPinUrl; rawPinCount=$rawCount; validPreviewCount=$validCount; cumulativeValidPreviewCount=$cumulativeValidCount; landscapePreviewCount=$landscapePreviewCount; cumulativeLandscapePreviewCount=$cumulativeLandscapeCount; eligibleVisualCount=$eligibleCount; rejectionReasons=$rejections; causeCodes=$causeCodes; addressesRound=0; correctionActions=@(); adjustmentSummary=''; resolvedByRound=0; pageStatus=$pageStatus; timestamp=$timestamp }
        }
        if ($isDomTimeout) {
            $issues += [pscustomobject][ordered]@{ code='DOM_READ_TIMEOUT'; round=$round; method=$method; query=$query; seedPinUrl=$seedPinUrl; rawPinCount=$rawCount; validPreviewCount=$validCount; cumulativeValidPreviewCount=$cumulativeValidCount; landscapePreviewCount=$landscapePreviewCount; cumulativeLandscapePreviewCount=$cumulativeLandscapeCount; eligibleVisualCount=$eligibleCount; rejectionReasons=$rejections; causeCodes=$causeCodes; addressesRound=0; correctionActions=@(); adjustmentSummary=''; resolvedByRound=0; pageStatus=$pageStatus; timestamp=$timestamp }
        }
        $previousAttempt = $attemptObject
    }
    return [pscustomobject]@{ Attempts=$attempts; Issues=$issues }
}
function Get-ProfessionalScores {
    param($Metadata, [string]$FileName)
    $limits = [ordered]@{ StyleScore=22; FunctionScaleScore=12; CompositionScore=18; SubjectOccupancyScore=10; MaterialDetailScore=10; LightingScore=7; ColorStylingScore=7; ReferenceValueScore=4 }
    $values = [ordered]@{}
    $total = 0
    foreach ($name in $limits.Keys) {
        $raw = Get-PropertyValue $Metadata $name $null
        if ($null -eq $raw) { throw "Preview metadata requires $name for $FileName." }
        $value = [int]$raw
        if ($value -lt 0 -or $value -gt $limits[$name]) { throw "$name is out of range for $FileName." }
        $values[$name] = $value
        $total += $value
    }
    if ($total -le 0) { throw "Professional scoring cannot be zero-filled for $FileName." }
    $values['ProfessionalScore'] = $total
    return [pscustomobject]$values
}

function Assert-SpaceRoleQuality {
    param($Metadata, $Scores, [string]$FileName)
    $spaceRole = [string](Get-PropertyValue $Metadata 'SpaceRole' '')
    $fullSpace = [bool](Get-PropertyValue $Metadata 'FullSpace' $false)
    $roleEvidence = [string](Get-PropertyValue $Metadata 'SpaceRoleEvidence' (Get-PropertyValue $Metadata 'VisualQualityEvidence' ''))
    if ([string]::IsNullOrWhiteSpace($roleEvidence)) { throw "Preview metadata requires role evidence for $FileName." }
    if ($fullSpace -ne ($spaceRole -eq 'full-space')) { throw "FullSpace must agree with SpaceRole for $FileName." }
    if ($spaceRole -eq 'full-space') {
        if ([int]$Scores.CompositionScore -lt 14 -or [int]$Scores.SubjectOccupancyScore -lt 7 -or [int]$Scores.FunctionScaleScore -lt 8) {
            throw "Full-space candidate $FileName needs stronger complete-space, subject-occupancy, and function-scale evidence."
        }
    }
    if ($spaceRole -eq 'detail' -and $fullSpace) { throw "Detail candidate $FileName cannot be marked FullSpace." }
}

function Get-DifferenceHash {
    param([string]$Path)
    $source = [Drawing.Image]::FromFile($Path)
    $bitmap = [Drawing.Bitmap]::new(9, 8)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.DrawImage($source, 0, 0, 9, 8)
        $bits = [Text.StringBuilder]::new(64)
        for ($y = 0; $y -lt 8; $y++) {
            for ($x = 0; $x -lt 8; $x++) {
                $left = $bitmap.GetPixel($x, $y)
                $right = $bitmap.GetPixel($x + 1, $y)
                $leftValue = (299 * $left.R) + (587 * $left.G) + (114 * $left.B)
                $rightValue = (299 * $right.R) + (587 * $right.G) + (114 * $right.B)
                [void]$bits.Append($(if ($leftValue -ge $rightValue) { '1' } else { '0' }))
            }
        }
        return $bits.ToString()
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
        $source.Dispose()
    }
}

function Get-HammingDistance {
    param([string]$Left, [string]$Right)
    if ($Left.Length -ne $Right.Length) { return [int]::MaxValue }
    $distance = 0
    for ($i = 0; $i -lt $Left.Length; $i++) { if ($Left[$i] -ne $Right[$i]) { $distance++ } }
    return $distance
}

function Test-LandscapeTarget {
    param([int]$Width, [int]$Height)
    if ($Width -le $Height -or $Height -le 0) { return $false }
    $ratio = $Width / $Height
    return (($ratio -ge 1.125 -and $ratio -le 1.875) -or ($ratio -ge 1.0 -and $ratio -le 1.667) -or ($ratio -ge 1.333 -and $ratio -le 2.222))
}

function Assert-LargeImageUrl {
    param([string]$Value, [int]$Candidate)
    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'i.pinimg.com') {
        throw "Candidate $Candidate large image URL must use HTTPS i.pinimg.com."
    }
    if ($uri.AbsolutePath -match '/(75x75_RS|136x136|170x|236x|474x)/') { throw "Candidate $Candidate does not reference a valid large image URL." }
}

function New-RoundedRectanglePath {
    param([Drawing.RectangleF]$Rectangle, [float]$Radius)
    $path = [Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $Radius * 2
    $arc = [Drawing.RectangleF]::new($Rectangle.X, $Rectangle.Y, $diameter, $diameter)
    $path.AddArc($arc, 180, 90)
    $arc.X = $Rectangle.Right - $diameter
    $path.AddArc($arc, 270, 90)
    $arc.Y = $Rectangle.Bottom - $diameter
    $path.AddArc($arc, 0, 90)
    $arc.X = $Rectangle.X
    $path.AddArc($arc, 90, 90)
    $path.CloseFigure()
    return $path
}

function Draw-RoundedRectangle {
    param(
        [Drawing.Graphics]$Graphics,
        [Drawing.RectangleF]$Rectangle,
        [float]$Radius,
        [Drawing.Brush]$Brush,
        [Drawing.Pen]$Pen
    )
    $path = New-RoundedRectanglePath $Rectangle $Radius
    try {
        if ($Brush) { $Graphics.FillPath($Brush, $path) }
        if ($Pen) { $Graphics.DrawPath($Pen, $path) }
    } finally {
        $path.Dispose()
    }
}

function Get-BoardRoleLabel {
    param([string]$Role)
    switch ($Role) {
        'full-space' { return '完整空间 Full-space' }
        'alternate-view' { return '补充视角 Alt-view' }
        'detail' { return '细节 Detail' }
        default { return $Role }
    }
}

function Get-BoardReason {
    param($Candidate)
    $role = [string](Get-PropertyValue $Candidate 'spaceRole' '')
    if ($role -eq 'full-space') {
        if ([int](Get-PropertyValue $Candidate 'lightingScore' 0) -ge 7) { return '空间完整 / Full space' }
        return '比例清晰 / Clear scale'
    }
    if ($role -eq 'alternate-view') { return '补充视角 / Alt view' }
    return '细节清晰 / Detail'
}

function Draw-BoardRow {
    param(
        [Drawing.Graphics]$Graphics,
        [float]$X,
        [float]$Y,
        [string]$Label,
        [string]$Value,
        [Drawing.Font]$LabelFont,
        [Drawing.Font]$ValueFont,
        [Drawing.Brush]$LabelBrush,
        [Drawing.Brush]$ValueBrush,
        [Drawing.Brush]$ChipBrush,
        [Drawing.Pen]$ChipPen
    )
    $labelRect = [Drawing.RectangleF]::new($X, $Y, 118, 30)
    Draw-RoundedRectangle $Graphics $labelRect 14 $ChipBrush $null
    $Graphics.DrawString($Label, $LabelFont, $LabelBrush, $labelRect.X + 10, $labelRect.Y + 6)
    $valueRect = [Drawing.RectangleF]::new($X + 138, $Y + 2, 250, 30)
    $Graphics.DrawString($Value, $ValueFont, $ValueBrush, $valueRect)
}

function Draw-ScorePill {
    param(
        [Drawing.Graphics]$Graphics,
        [float]$X,
        [float]$Y,
        [int]$Score,
        [Drawing.Font]$Font,
        [Drawing.Brush]$TextBrush
    )
    $good = $Score -ge 84
    $fill = if ($good) { [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(230, 248, 238)) } else { [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(255, 246, 218)) }
    $pen = if ($good) { [Drawing.Pen]::new([Drawing.Color]::FromArgb(112, 199, 151), 2) } else { [Drawing.Pen]::new([Drawing.Color]::FromArgb(223, 184, 87), 2) }
    try {
        $rect = [Drawing.RectangleF]::new($X, $Y, 68, 32)
        Draw-RoundedRectangle $Graphics $rect 16 $fill $pen
        $Graphics.DrawString([string]$Score, $Font, $TextBrush, $rect.X + 21, $rect.Y + 7)
    } finally {
        $fill.Dispose()
        $pen.Dispose()
    }
}

function New-CandidateBoard {
    param([array]$Candidates, [string]$Path)
    $columns = 5
    $rows = [math]::Ceiling($Candidates.Count / $columns)
    if ($rows -lt 1) { $rows = 1 }
    if ($rows -gt 2) { $rows = 2 }
    $width = 2560
    $height = 1440
    $marginX = 58
    $marginY = 54
    $gapX = 28
    $gapY = 34
    $footerHeight = 64
    $tileWidth = [int](($width - ($marginX * 2) - (($columns - 1) * $gapX)) / $columns)
    $tileHeight = [int](($height - ($marginY * 2) - $footerHeight - (($rows - 1) * $gapY)) / $rows)
    $sheet = [Drawing.Bitmap]::new($width, $height)
    $graphics = [Drawing.Graphics]::FromImage($sheet)
    $graphics.Clear([Drawing.Color]::FromArgb(250, 250, 248))
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $titleFont = [Drawing.Font]::new('Microsoft YaHei', 18, [Drawing.FontStyle]::Bold)
    $labelFont = [Drawing.Font]::new('Microsoft YaHei', 10, [Drawing.FontStyle]::Bold)
    $valueFont = [Drawing.Font]::new('Microsoft YaHei', 11, [Drawing.FontStyle]::Regular)
    $scoreFont = [Drawing.Font]::new('Arial', 12, [Drawing.FontStyle]::Bold)
    $footerFont = [Drawing.Font]::new('Microsoft YaHei', 18, [Drawing.FontStyle]::Bold)
    $cardBrush = [Drawing.SolidBrush]::new([Drawing.Color]::White)
    $labelBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(118, 118, 118))
    $valueBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(65, 65, 65))
    $chipBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(246, 247, 247))
    $borderPen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(224, 224, 220), 1)
    $outerPen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(225, 225, 222), 2)
    $shadowBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(18, 0, 0, 0))
    try {
        $outerBrush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(253, 253, 251))
        try {
            $outer = [Drawing.RectangleF]::new(18, 18, $width - 36, $height - 36)
            Draw-RoundedRectangle $graphics $outer 24 $outerBrush $outerPen
        } finally {
            $outerBrush.Dispose()
        }
        $visibleCandidates = @($Candidates | Select-Object -First ($columns * $rows))
        for ($i = 0; $i -lt $Candidates.Count; $i++) {
            if ($i -ge $visibleCandidates.Count) { break }
            $candidate = $visibleCandidates[$i]
            $x = $marginX + (($i % $columns) * ($tileWidth + $gapX))
            $y = $marginY + ([math]::Floor($i / $columns) * ($tileHeight + $gapY))
            $shadow = [Drawing.RectangleF]::new($x + 4, $y + 5, $tileWidth, $tileHeight)
            Draw-RoundedRectangle $graphics $shadow 16 $shadowBrush $null
            $card = [Drawing.RectangleF]::new($x, $y, $tileWidth, $tileHeight)
            Draw-RoundedRectangle $graphics $card 16 $cardBrush $borderPen
            $imageArea = [Drawing.RectangleF]::new($x + 20, $y + 20, $tileWidth - 40, [int](($tileWidth - 40) * 9 / 16))
            if ($candidate.previewPath -and (Test-Path -LiteralPath $candidate.previewPath)) {
                $image = [Drawing.Image]::FromFile($candidate.previewPath)
                try {
                    $scale = [math]::Min($imageArea.Width / $image.Width, $imageArea.Height / $image.Height)
                    $drawWidth = [int]($image.Width * $scale)
                    $drawHeight = [int]($image.Height * $scale)
                    $drawX = $imageArea.X + [int](($imageArea.Width - $drawWidth) / 2)
                    $drawY = $imageArea.Y + [int](($imageArea.Height - $drawHeight) / 2)
                    $state = $graphics.Save()
                    $clipPath = New-RoundedRectanglePath $imageArea 10
                    $graphics.SetClip($clipPath)
                    $graphics.DrawImage($image, $drawX, $drawY, $drawWidth, $drawHeight)
                    $graphics.Restore($state)
                    $clipPath.Dispose()
                } finally { $image.Dispose() }
            } else {
                $graphics.FillRectangle([Drawing.Brushes]::Gainsboro, $imageArea)
                $graphics.DrawString('预览缺失 Preview unavailable', $valueFont, [Drawing.Brushes]::DimGray, $imageArea.X + 70, $imageArea.Y + 150)
            }
            $metaTop = $imageArea.Bottom + 18
            $graphics.DrawString(('{0:D2}' -f [int]$candidate.number), $titleFont, [Drawing.Brushes]::Black, $x + 22, $metaTop)
            $rowY = $metaTop + 42
            Draw-BoardRow $graphics ($x + 22) $rowY '角色 Role' (Get-BoardRoleLabel $candidate.spaceRole) $labelFont $valueFont $labelBrush $valueBrush $chipBrush $null
            $rowY += 39
            Draw-BoardRow $graphics ($x + 22) $rowY '来源 Source' 'Pinterest' $labelFont $valueFont $labelBrush $valueBrush $chipBrush $null
            $rowY += 39
            Draw-BoardRow $graphics ($x + 22) $rowY '评分 Score' '' $labelFont $valueFont $labelBrush $valueBrush $chipBrush $null
            Draw-ScorePill $graphics ($x + 160) $rowY ([int]$candidate.professionalScore) $scoreFont $valueBrush
            $rowY += 39
            Draw-BoardRow $graphics ($x + 22) $rowY '理由 Reason' (Get-BoardReason $candidate) $labelFont $valueFont $labelBrush $valueBrush $chipBrush $null
        }
        $footerText = "共 $($Candidates.Count) 张参考图 / $($Candidates.Count) references · 专业评分与理由 / professional review"
        $graphics.DrawString($footerText, $footerFont, $valueBrush, $marginX + 6, $height - $footerHeight + 16)
        $sheet.Save($Path, [Drawing.Imaging.ImageFormat]::Jpeg)
    } finally {
        $titleFont.Dispose()
        $labelFont.Dispose()
        $valueFont.Dispose()
        $scoreFont.Dispose()
        $footerFont.Dispose()
        $cardBrush.Dispose()
        $labelBrush.Dispose()
        $valueBrush.Dispose()
        $chipBrush.Dispose()
        $borderPen.Dispose()
        $outerPen.Dispose()
        $shadowBrush.Dispose()
        $graphics.Dispose()
        $sheet.Dispose()
        foreach ($candidate in $Candidates) {
            if ($candidate.previewPath -and $candidate.previewPath -ne $candidate.fullPath -and (Test-Path -LiteralPath $candidate.previewPath)) {
                Remove-Item -LiteralPath $candidate.previewPath -Force
            }
        }
    }
}

function Write-ProjectReadme {
    param($Manifest, [string]$Path)
    $lines = @(
        "# $($Manifest.projectName)",
        '',
        "Search: ``$($Manifest.searchQuery)``",
        '',
        '## Files',
        '',
        '- `candidates/`: unchanged search-preview files.',
        '- `selected/`: current detail-page large-image selections.',
        '- `preview/candidate-board.jpg`: bilingual professional candidate board.',
        '- `preview/contact-sheet.jpg`: compatibility copy of the candidate board.',
        '- `candidates.csv`: flat candidate metadata.',
        '- `manifest.json`: source of truth and selection history.',
        '- `issues.jsonl`: compact search and recovery issues.',
        '',
        '## Current Selection',
        ''
    )
    if (@($Manifest.currentSelection).Count -eq 0) {
        $lines += '- No final selection yet.'
    } else {
        foreach ($item in @($Manifest.currentSelection)) {
            $lines += "- Slot $($item.slot): Candidate $($item.candidateNumber) as ``$($item.outputFile)``."
        }
    }
    Write-Utf8File -Path $Path -Content ($lines -join [Environment]::NewLine)
}

function Invoke-Build {
    foreach ($required in @('InputDir','OutputRoot','Topic','Style','SearchQuery')) {
        if (-not (Get-Variable -Name $required -ValueOnly)) { throw "$required is required for Build." }
    }
    if (-not (Test-Path -LiteralPath $InputDir -PathType Container)) { throw "InputDir does not exist: $InputDir" }
    if ($MinimumCandidateCount -gt $CandidateLimit) { throw 'MinimumCandidateCount cannot exceed CandidateLimit.' }
    Assert-SearchQuery $SearchQuery 1 @() @()
    $searchData = Get-SearchAttemptData $SearchAttemptLog
    $scopeKey = Get-PreferenceScopeKey $ProjectType $Topic $SearchQuery $OutputUse
    $profilePath = Join-Path $OutputRoot 'preferences\profile.json'
    $searchSlug = Get-CompactSearchSlug $SearchQuery $Topic
    $roomSlug = Get-RoomSlug $Topic $SearchQuery
    $allowed = @('.jpg','.jpeg','.png','.webp')
    $files = @(Get-ChildItem -LiteralPath $InputDir -File | Where-Object { $allowed -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name | Select-Object -First $CandidateLimit)
    if ($files.Count -lt $MinimumCandidateCount) { throw "At least $MinimumCandidateCount preview candidates are required; found $($files.Count)." }
    $metadataMap = Get-MetadataMap $SourceMetadata
    $seenPins = @{}
    $seenImages = @{}
    $perceptualHashes = @()
    $preflightMap = @{}
    $landscapeCount = 0
    foreach ($source in $files) {
        $meta = $metadataMap[$source.Name]
        $pinUrl = [string](Get-PropertyValue $meta 'PinUrl' '')
        $imageUrl = [string](Get-PropertyValue $meta 'ImageUrl' '')
        if ([string]::IsNullOrWhiteSpace($pinUrl) -or [string]::IsNullOrWhiteSpace($imageUrl)) { throw "Preview metadata requires PinUrl and ImageUrl for $($source.Name)." }
        if ($seenPins.ContainsKey($pinUrl) -or $seenImages.ContainsKey($imageUrl)) { throw "Duplicate preview source detected for $($source.Name)." }
        $visualSourceType = [string](Get-PropertyValue $meta 'VisualSourceType' '')
        $evidence = [string](Get-PropertyValue $meta 'VisualQualityEvidence' '')
        $spaceRole = [string](Get-PropertyValue $meta 'SpaceRole' '')
        if (@('photo','cgi','ai','concept') -notcontains $visualSourceType) { throw "Preview metadata has an invalid VisualSourceType for $($source.Name)." }
        if ([string]::IsNullOrWhiteSpace($evidence)) { throw "Preview metadata requires VisualQualityEvidence for $($source.Name)." }
        if (@('full-space','alternate-view','detail') -notcontains $spaceRole) { throw "Preview metadata has an invalid SpaceRole for $($source.Name)." }
        $scores = Get-ProfessionalScores $meta $source.Name
        Assert-SpaceRoleQuality $meta $scores $source.Name
        if ($visualSourceType -ne 'photo' -and $scores.ProfessionalScore -lt 75) { throw "Synthetic candidate $($source.Name) requires ProfessionalScore of at least 75." }
        $engagementScore = [double](Get-PropertyValue $meta 'EngagementScore' 0)
        if ($engagementScore -lt 0 -or $engagementScore -gt 10) { throw "EngagementScore is out of range for $($source.Name)." }
        foreach ($metricName in @('SaveCount','ViewCount')) {
            $metric = Get-PropertyValue $meta $metricName $null
            if ($null -ne $metric -and [long]$metric -lt 0) { throw "$metricName cannot be negative for $($source.Name)." }
        }
        $dimensions = Get-ImageDimensions $source.FullName
        if ($dimensions.Width -le 0 -or $dimensions.Height -le 0 -or -not $dimensions.PreviewPath) { throw "Preview image cannot be decoded: $($source.Name)." }
        try { $differenceHash = Get-DifferenceHash $dimensions.PreviewPath }
        finally {
            if ($dimensions.PreviewPath -ne $source.FullName -and (Test-Path -LiteralPath $dimensions.PreviewPath)) { Remove-Item -LiteralPath $dimensions.PreviewPath -Force }
        }
        foreach ($existingHash in $perceptualHashes) {
            if ((Get-HammingDistance $differenceHash $existingHash) -le 4) { throw "Perceptual duplicate preview detected for $($source.Name)." }
        }
        $perceptualHashes += $differenceHash
        if (Test-LandscapeTarget $dimensions.Width $dimensions.Height) { $landscapeCount++ }
        $preflightMap[$source.Name] = [pscustomobject]@{ Width=$dimensions.Width; Height=$dimensions.Height; DifferenceHash=$differenceHash; Scores=$scores }
        $seenPins[$pinUrl] = $true
        $seenImages[$imageUrl] = $true
    }
    if ($landscapeCount -lt [math]::Ceiling($files.Count * 0.4)) { throw 'At least 40 percent of preview candidates must pass the landscape aspect-ratio target.' }
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

    $date = Get-ProjectDate $ProjectDate
    $baseName = '{0}_{1}_{2}' -f $date, (Get-SafeName $Topic 'topic'), (Get-SafeName $Style 'style')
    $target = Join-Path $OutputRoot $baseName
    $suffix = 2
    while (Test-Path -LiteralPath $target) {
        $target = Join-Path $OutputRoot ('{0}_{1:D2}' -f $baseName, $suffix)
        $suffix++
    }
    foreach ($dir in @($target, (Join-Path $target 'candidates'), (Join-Path $target 'selected'), (Join-Path $target 'preview'), (Join-Path $target 'reviews'))) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }

    $candidates = @()

    for ($i = 0; $i -lt $files.Count; $i++) {
        $source = $files[$i]
        $number = $i + 1
        $extension = $source.Extension.ToLowerInvariant()
        $fileName = '{0}-preview-{1:D2}{2}' -f $searchSlug, $number, $extension
        $destination = Join-Path $target (Join-Path 'candidates' $fileName)
        [IO.File]::Copy($source.FullName, $destination, $false)
        $dimensions = Get-ImageDimensions $destination
        $meta = $metadataMap[$source.Name]
        $preflight = $preflightMap[$source.Name]
        $scores = $preflight.Scores
        $contextPreferenceScore = Get-PreferenceScore $profilePath $scopeKey $meta
        $diversityScore = Get-DiversityScore $candidates $meta
        $finalScore = [math]::Round(([double]$scores.ProfessionalScore * 0.75) + ([double]$contextPreferenceScore * 0.20) + ([double]$diversityScore * 0.05), 2)
        $candidate = [ordered]@{
            number = $number
            fileName = $fileName
            sourceFileName = $source.Name
            extension = $extension
            width = $dimensions.Width
            height = $dimensions.Height
            sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            previewImageUrl = [string](Get-PropertyValue $meta 'ImageUrl' '')
            pinUrl = [string](Get-PropertyValue $meta 'PinUrl' '')
            assetId = [string](Get-PropertyValue $meta 'AssetId' '')
            fullSpace = [bool](Get-PropertyValue $meta 'FullSpace' $false)
            visualSourceType = [string](Get-PropertyValue $meta 'VisualSourceType' '')
            visualQualityEvidence = [string](Get-PropertyValue $meta 'VisualQualityEvidence' '')
            spaceRole = [string](Get-PropertyValue $meta 'SpaceRole' '')
            spaceRoleEvidence = [string](Get-PropertyValue $meta 'SpaceRoleEvidence' (Get-PropertyValue $meta 'VisualQualityEvidence' ''))
            styleScore = [int]$scores.StyleScore
            functionScaleScore = [int]$scores.FunctionScaleScore
            compositionScore = [int]$scores.CompositionScore
            subjectOccupancyScore = [int]$scores.SubjectOccupancyScore
            materialDetailScore = [int]$scores.MaterialDetailScore
            lightingScore = [int]$scores.LightingScore
            colorStylingScore = [int]$scores.ColorStylingScore
            referenceValueScore = [int]$scores.ReferenceValueScore
            professionalScore = [int]$scores.ProfessionalScore
            engagementScore = [double](Get-PropertyValue $meta 'EngagementScore' 0)
            contextPreferenceScore = [double]$contextPreferenceScore
            diversityScore = [double]$diversityScore
            finalScore = [double]$finalScore
            saveCount = Get-PropertyValue $meta 'SaveCount' $null
            viewCount = Get-PropertyValue $meta 'ViewCount' $null
            perceptualHash = [string]$preflight.DifferenceHash
            fullPath = $destination
            previewPath = $dimensions.PreviewPath
        }
        $candidates += [pscustomobject]$candidate
    }

    $candidateBoardPath = Join-Path $target 'preview\candidate-board.jpg'
    New-CandidateBoard -Candidates $candidates -Path $candidateBoardPath
    Copy-Item -LiteralPath $candidateBoardPath -Destination (Join-Path $target 'preview\contact-sheet.jpg') -Force
    $csvRows = $candidates | ForEach-Object {
        [pscustomobject]@{ Candidate=$_.number; FileName=$_.fileName; Width=$_.width; Height=$_.height; SHA256=$_.sha256; PreviewImageUrl=$_.previewImageUrl; PinUrl=$_.pinUrl; VisualSourceType=$_.visualSourceType; FullSpace=$_.fullSpace; SpaceRole=$_.spaceRole; SpaceRoleEvidence=$_.spaceRoleEvidence; SubjectOccupancyScore=$_.subjectOccupancyScore; ProfessionalScore=$_.professionalScore; EngagementScore=$_.engagementScore; ContextPreferenceScore=$_.contextPreferenceScore; DiversityScore=$_.diversityScore; FinalScore=$_.finalScore; SaveCount=$_.saveCount; ViewCount=$_.viewCount; PerceptualHash=$_.perceptualHash }
    }
    $csvRows | Export-Csv -LiteralPath (Join-Path $target 'candidates.csv') -NoTypeInformation -Encoding UTF8

    $manifestCandidates = $candidates | ForEach-Object {
        [ordered]@{ number=$_.number; fileName=$_.fileName; sourceFileName=$_.sourceFileName; extension=$_.extension; width=$_.width; height=$_.height; sha256=$_.sha256; previewImageUrl=$_.previewImageUrl; pinUrl=$_.pinUrl; assetId=$_.assetId; fullSpace=$_.fullSpace; visualSourceType=$_.visualSourceType; visualQualityEvidence=$_.visualQualityEvidence; spaceRole=$_.spaceRole; spaceRoleEvidence=$_.spaceRoleEvidence; styleScore=$_.styleScore; functionScaleScore=$_.functionScaleScore; compositionScore=$_.compositionScore; subjectOccupancyScore=$_.subjectOccupancyScore; materialDetailScore=$_.materialDetailScore; lightingScore=$_.lightingScore; colorStylingScore=$_.colorStylingScore; referenceValueScore=$_.referenceValueScore; professionalScore=$_.professionalScore; engagementScore=$_.engagementScore; contextPreferenceScore=$_.contextPreferenceScore; diversityScore=$_.diversityScore; finalScore=$_.finalScore; saveCount=$_.saveCount; viewCount=$_.viewCount; perceptualHash=$_.perceptualHash }
    }
    $manifest = [ordered]@{
        schemaVersion = 5
        projectName = Split-Path -Leaf $target
        createdDate = $date
        createdAt = [datetime]::UtcNow.ToString('o')
        topic = $Topic
        style = $Style
        searchQuery = $SearchQuery
        searchSlug = $searchSlug
        roomSlug = $roomSlug
        projectType = $ProjectType
        outputUse = $OutputUse
        preferenceScopeKey = $scopeKey
        preferenceProfilePath = $profilePath
        scoringFormula = 'ProfessionalScore * 0.75 + ContextPreferenceScore * 0.20 + DiversityScore * 0.05'
        minimumCandidateCount = $MinimumCandidateCount
        boardStyle = 'professional-review-candidate-board-16x9'
        candidateBoard = 'preview/candidate-board.jpg'
        contactSheet = 'preview/contact-sheet.jpg'
        requestedDownloadCount = $RequestedDownloadCount
        confirmedDownloadCount = 0
        searchAttempts = @($searchData.Attempts)
        issues = @($searchData.Issues)
        candidates = @($manifestCandidates)
        currentSelection = @()
        selectionHistory = @()
    }
    Write-Utf8File -Path (Join-Path $target 'manifest.json') -Content ($manifest | ConvertTo-Json -Depth 10)
    $issuePath = Join-Path $target 'issues.jsonl'
    $issueLines = @($searchData.Issues | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 8 })
    Write-Utf8File -Path $issuePath -Content ($issueLines -join [Environment]::NewLine)
    $roundReviewPath = Join-Path $target 'reviews\round-review.jsonl'
    $roundLines = @($searchData.Attempts | ForEach-Object {
        [pscustomobject][ordered]@{
            projectName = Split-Path -Leaf $target
            scope = $scopeKey
            round = $_.round
            method = $_.method
            rawPinCount = $_.rawPinCount
            validPreviewCount = $_.validPreviewCount
            cumulativeValidPreviewCount = $_.cumulativeValidPreviewCount
            landscapePreviewCount = $_.landscapePreviewCount
            cumulativeLandscapePreviewCount = $_.cumulativeLandscapePreviewCount
            causeCodes = $_.causeCodes
            correctionActions = $_.correctionActions
            pageStatus = $_.pageStatus
            timestamp = $_.timestamp
        } | ConvertTo-Json -Compress -Depth 8
    })
    Write-Utf8File -Path $roundReviewPath -Content ($roundLines -join [Environment]::NewLine)
    $batchReview = [ordered]@{
        projectName = Split-Path -Leaf $target
        scope = $scopeKey
        searchSlug = $searchSlug
        roomSlug = $roomSlug
        candidateCount = @($manifestCandidates).Count
        minimumCandidateCount = $MinimumCandidateCount
        landscapeCandidateCount = $landscapeCount
        boardStyle = 'professional-review-candidate-board'
        candidateBoard = 'preview/candidate-board.jpg'
        contactSheet = 'preview/contact-sheet.jpg'
        candidateSummary = @($manifestCandidates | ForEach-Object {
            [ordered]@{ number=$_.number; role=$_.spaceRole; source=$_.visualSourceType; size=('{0}x{1}' -f $_.width,$_.height); professionalScore=$_.professionalScore; contextPreferenceScore=$_.contextPreferenceScore; diversityScore=$_.diversityScore; finalScore=$_.finalScore }
        })
        effectiveBehaviors = @()
        hardRejections = @()
        preferenceMayAffectSearchTerms = $false
        createdAt = [datetime]::UtcNow.ToString('o')
    }
    Write-Utf8File -Path (Join-Path $target 'reviews\batch-review.json') -Content ($batchReview | ConvertTo-Json -Depth 10)
    Write-ProjectReadme -Manifest ([pscustomobject]$manifest) -Path (Join-Path $target 'README.md')
    return $target
}

function Invoke-SelectLarge {
    if (-not $ProjectDir -or -not (Test-Path -LiteralPath $ProjectDir -PathType Container)) { throw 'A valid ProjectDir is required for SelectLarge.' }
    if (-not $LargeInputDir -or -not (Test-Path -LiteralPath $LargeInputDir -PathType Container)) { throw 'A valid LargeInputDir is required for SelectLarge.' }
    if (-not $CandidateNumber -or $CandidateNumber.Count -eq 0) { throw 'CandidateNumber is required for SelectLarge.' }
    if (-not $Role -or $Role.Count -ne $CandidateNumber.Count) { throw 'Role must contain one value per candidate.' }
    $finalCount = $(if ($ConfirmedDownloadCount -gt 0) { $ConfirmedDownloadCount } else { $CandidateNumber.Count })
    if ($CandidateNumber.Count -ne $finalCount) { throw 'CandidateNumber count must match ConfirmedDownloadCount.' }
    $manifestPath = Join-Path $ProjectDir 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $minSelectionCount = [int](Get-PropertyValue $manifest 'minimumCandidateCount' 10)
    if (@($manifest.candidates).Count -lt $minSelectionCount) { throw "SelectLarge requires a preview board with at least $minSelectionCount candidates." }
    $chosen = @()
    foreach ($number in $CandidateNumber) {
        $item = @($manifest.candidates | Where-Object { $_.number -eq $number })
        if ($item.Count -ne 1) { throw "Candidate $number does not exist." }
        $chosen += $item[0]
    }
    if ($Interior -and $Role.Count -ge 1 -and ([string]$Role[0]).ToLowerInvariant() -eq 'detail') {
        throw 'Interior selections cannot use detail as the primary image.'
    }
    if ($Interior -and $chosen.Count -ge 2 -and -not ($chosen | Where-Object { $_.fullSpace })) {
        throw 'Interior selections with two or more images require at least one full-space candidate.'
    }
    $largeMetadataMap = Get-LargeMetadataMap $LargeSourceMetadata

    $selectedDir = Join-Path $ProjectDir 'selected'
    $stagingDir = Join-Path $ProjectDir ('.selected-staging-' + [guid]::NewGuid().ToString('N'))
    $backupDir = Join-Path $ProjectDir ('.selected-backup-' + [guid]::NewGuid().ToString('N'))
    $temporaryPreviews = @()
    New-Item -ItemType Directory -Path $stagingDir | Out-Null
    $current = @()
    $dateCompact = ([string](Get-PropertyValue $manifest 'createdDate' (Get-ProjectDate ''))).Replace('-', '')
    $roomSlug = [string](Get-PropertyValue $manifest 'roomSlug' '')
    if ([string]::IsNullOrWhiteSpace($roomSlug)) { $roomSlug = Get-RoomSlug ([string](Get-PropertyValue $manifest 'topic' 'interior')) ([string](Get-PropertyValue $manifest 'searchQuery' '')) }
    try {
        for ($i = 0; $i -lt $chosen.Count; $i++) {
            $item = $chosen[$i]
            $largeMeta = $largeMetadataMap[[int]$item.number]
            if ($null -eq $largeMeta) { throw "Large metadata is missing for Candidate $($item.number)." }
            $largeFileName = [string](Get-PropertyValue $largeMeta 'FileName' '')
            $largeImageUrl = [string](Get-PropertyValue $largeMeta 'ImageUrl' '')
            $largePinUrl = [string](Get-PropertyValue $largeMeta 'PinUrl' '')
            $downloadMethod = [string](Get-PropertyValue $largeMeta 'DownloadMethod' '')
            $downloadStatus = [string](Get-PropertyValue $largeMeta 'DownloadStatus' '')
            $failureCode = [string](Get-PropertyValue $largeMeta 'FailureCode' '')
            $replacementOf = [int](Get-PropertyValue $largeMeta 'ReplacementOfCandidateNumber' 0)
            if ([string]::IsNullOrWhiteSpace($largeFileName) -or [IO.Path]::GetFileName($largeFileName) -ne $largeFileName) { throw "Large FileName is invalid for Candidate $($item.number)." }
            Assert-LargeImageUrl $largeImageUrl ([int]$item.number)
            if ($largePinUrl -notmatch '^https://([a-z]+\.)?pinterest\.[^/]+/pin/') { throw "Candidate $($item.number) large PinUrl is invalid." }
            if ($replacementOf -eq 0 -and $largePinUrl -ne [string]$item.pinUrl) { throw "Candidate $($item.number) large PinUrl does not match its preview source." }
            if ($replacementOf -ne 0 -and $replacementOf -ne [int]$item.number) { throw "Candidate $($item.number) replacement relationship is invalid." }
            if (@('pinterest-visible','chrome-native','controlled-url') -notcontains $downloadMethod -or $downloadStatus -ne 'success') { throw "Candidate $($item.number) requires a successful supported DownloadMethod." }
            $source = Join-Path $LargeInputDir $largeFileName
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Large image file is missing for Candidate $($item.number)." }
            $extension = [IO.Path]::GetExtension($source).ToLowerInvariant()
            if (@('.jpg','.jpeg','.png','.webp') -notcontains $extension) { throw "Large image type is unsupported for Candidate $($item.number)." }
            $dimensions = Get-ImageDimensions $source
            if ($dimensions.PreviewPath -and $dimensions.PreviewPath -ne $source) { $temporaryPreviews += $dimensions.PreviewPath }
            if ($dimensions.Width -le 0 -or $dimensions.Height -le 0) { throw "Large image cannot be decoded for Candidate $($item.number)." }
            $outputFile = '{0}-{1}-{2:D2}{3}' -f $dateCompact, $roomSlug, ($i + 1), $extension
            $destination = Join-Path $stagingDir $outputFile
            [IO.File]::Copy($source, $destination, $false)
            $current += [pscustomobject]@{
                slot=$i + 1
                candidateNumber=[int]$item.number
                role=$Role[$i]
                outputFile=$outputFile
                width=[int]$dimensions.Width
                height=[int]$dimensions.Height
                sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
                imageUrl=$largeImageUrl
                pinUrl=$largePinUrl
                originalPinUrl=[string]$item.pinUrl
                downloadMethod=$downloadMethod
                downloadStatus=$downloadStatus
                failureCode=$failureCode
                replacementOfCandidateNumber=$replacementOf
                professionalScore=[int](Get-PropertyValue $item 'professionalScore' 0)
                contextPreferenceScore=[double](Get-PropertyValue $item 'contextPreferenceScore' 0)
                diversityScore=[double](Get-PropertyValue $item 'diversityScore' 0)
                finalScore=[double](Get-PropertyValue $item 'finalScore' 0)
            }
        }
        if (Test-Path -LiteralPath $selectedDir) { Move-Item -LiteralPath $selectedDir -Destination $backupDir }
        try {
            Move-Item -LiteralPath $stagingDir -Destination $selectedDir
            if (Test-Path -LiteralPath $backupDir) { Remove-Item -LiteralPath $backupDir -Recurse -Force }
        } catch {
            if (Test-Path -LiteralPath $selectedDir) { Remove-Item -LiteralPath $selectedDir -Recurse -Force }
            if (Test-Path -LiteralPath $backupDir) { Move-Item -LiteralPath $backupDir -Destination $selectedDir }
            throw
        }
    } finally {
        if (Test-Path -LiteralPath $stagingDir) { Remove-Item -LiteralPath $stagingDir -Recurse -Force }
        foreach ($previewPath in $temporaryPreviews) {
            if (Test-Path -LiteralPath $previewPath) { Remove-Item -LiteralPath $previewPath -Force }
        }
    }
    $previous = @($manifest.currentSelection)
    $history = @($manifest.selectionHistory)
    $history += [pscustomobject]@{ changedAt=[datetime]::UtcNow.ToString('o'); previous=$previous; current=$current }
    $manifest.currentSelection = $current
    $manifest.selectionHistory = $history
    Set-ObjectProperty $manifest 'confirmedDownloadCount' $finalCount
    Write-Utf8File -Path $manifestPath -Content ($manifest | ConvertTo-Json -Depth 12)
    $batchPath = Join-Path $ProjectDir 'reviews\batch-review.json'
    if (Test-Path -LiteralPath $batchPath -PathType Leaf) {
        $batch = Get-Content -LiteralPath $batchPath -Raw -Encoding utf8 | ConvertFrom-Json
        $selectionBehaviors = @($current | ForEach-Object {
            [pscustomobject][ordered]@{
                type = 'final_selection'
                candidateNumber = $_.candidateNumber
                role = $_.role
                outputFile = $_.outputFile
                pinUrl = $_.pinUrl
                imageUrl = $_.imageUrl
                professionalScore = $_.professionalScore
                contextPreferenceScore = $_.contextPreferenceScore
                finalScore = $_.finalScore
                timestamp = [datetime]::UtcNow.ToString('o')
            }
        })
        $downloadBehaviors = @($current | Where-Object { $_.downloadStatus -eq 'success' } | ForEach-Object {
            [pscustomobject][ordered]@{
                type = 'large_download_success'
                candidateNumber = $_.candidateNumber
                outputFile = $_.outputFile
                pinUrl = $_.pinUrl
                imageUrl = $_.imageUrl
                timestamp = [datetime]::UtcNow.ToString('o')
            }
        })
        Set-ObjectProperty $batch 'effectiveBehaviors' @($selectionBehaviors + $downloadBehaviors)
        Set-ObjectProperty $batch 'confirmedDownloadCount' $finalCount
        Set-ObjectProperty $batch 'updatedAt' ([datetime]::UtcNow.ToString('o'))
        Write-Utf8File -Path $batchPath -Content ($batch | ConvertTo-Json -Depth 12)
    }
    Write-ProjectReadme -Manifest $manifest -Path (Join-Path $ProjectDir 'README.md')
    return $current | ForEach-Object { Join-Path $selectedDir $_.outputFile }
}

if ($Action -eq 'Build') { Invoke-Build } else { Invoke-SelectLarge }

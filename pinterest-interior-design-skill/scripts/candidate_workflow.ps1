[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Build','Select')]
    [string]$Action,

    [string]$InputDir,
    [string]$OutputRoot,
    [string]$Topic,
    [string]$Style,
    [string]$SearchQuery,
    [string]$ProjectDate,
    [string]$SourceMetadata,
    [string]$ProjectDir,
    [int[]]$CandidateNumber,
    [string[]]$Role,
    [switch]$Interior,
    [int]$CandidateLimit = 16
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
                    $previewPath = [IO.Path]::ChangeExtension([IO.Path]::GetTempFileName(), '.jpg')
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

function Get-PropertyValue {
    param($Object, [string]$Name, $Default)
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function New-ContactSheet {
    param([array]$Candidates, [string]$Path)
    $columns = 4
    $tileWidth = 320
    $tileHeight = 270
    $rows = [math]::Ceiling($Candidates.Count / $columns)
    $sheet = [Drawing.Bitmap]::new($columns * $tileWidth, [int]$rows * $tileHeight)
    $graphics = [Drawing.Graphics]::FromImage($sheet)
    $graphics.Clear([Drawing.Color]::White)
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $labelFont = [Drawing.Font]::new('Arial', 15, [Drawing.FontStyle]::Bold)
    $detailFont = [Drawing.Font]::new('Arial', 10)
    try {
        for ($i = 0; $i -lt $Candidates.Count; $i++) {
            $candidate = $Candidates[$i]
            $x = ($i % $columns) * $tileWidth
            $y = [math]::Floor($i / $columns) * $tileHeight
            $graphics.DrawString(('Candidate {0:D2}' -f $candidate.number), $labelFont, [Drawing.Brushes]::Black, $x + 12, $y + 8)
            $graphics.DrawString(("$($candidate.width) x $($candidate.height)"), $detailFont, [Drawing.Brushes]::DimGray, $x + 190, $y + 12)
            $imageArea = [Drawing.Rectangle]::new($x + 12, $y + 40, $tileWidth - 24, $tileHeight - 52)
            if ($candidate.previewPath -and (Test-Path -LiteralPath $candidate.previewPath)) {
                $image = [Drawing.Image]::FromFile($candidate.previewPath)
                try {
                    $scale = [math]::Min($imageArea.Width / $image.Width, $imageArea.Height / $image.Height)
                    $drawWidth = [int]($image.Width * $scale)
                    $drawHeight = [int]($image.Height * $scale)
                    $drawX = $imageArea.X + [int](($imageArea.Width - $drawWidth) / 2)
                    $drawY = $imageArea.Y + [int](($imageArea.Height - $drawHeight) / 2)
                    $graphics.DrawImage($image, $drawX, $drawY, $drawWidth, $drawHeight)
                } finally { $image.Dispose() }
            } else {
                $graphics.FillRectangle([Drawing.Brushes]::Gainsboro, $imageArea)
                $graphics.DrawString('Preview unavailable', $detailFont, [Drawing.Brushes]::DimGray, $imageArea.X + 70, $imageArea.Y + 90)
            }
            $graphics.DrawRectangle([Drawing.Pens]::LightGray, $imageArea)
        }
        $sheet.Save($Path, [Drawing.Imaging.ImageFormat]::Jpeg)
    } finally {
        $labelFont.Dispose()
        $detailFont.Dispose()
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
        '- `candidates/`: original candidate files with unchanged bytes.',
        '- `selected/`: current final selections.',
        '- `preview/contact-sheet.jpg`: numbered review board.',
        '- `candidates.csv`: flat candidate metadata.',
        '- `manifest.json`: source of truth and selection history.',
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
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

    $date = Get-ProjectDate $ProjectDate
    $baseName = '{0}_{1}_{2}' -f $date, (Get-SafeName $Topic 'topic'), (Get-SafeName $Style 'style')
    $target = Join-Path $OutputRoot $baseName
    $suffix = 2
    while (Test-Path -LiteralPath $target) {
        $target = Join-Path $OutputRoot ('{0}_{1:D2}' -f $baseName, $suffix)
        $suffix++
    }
    foreach ($dir in @($target, (Join-Path $target 'candidates'), (Join-Path $target 'selected'), (Join-Path $target 'preview'))) {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }

    $allowed = @('.jpg','.jpeg','.png','.webp')
    $files = @(Get-ChildItem -LiteralPath $InputDir -File | Where-Object { $allowed -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name | Select-Object -First ([math]::Max(1, [math]::Min($CandidateLimit, 16))))
    if ($files.Count -eq 0) { throw 'No supported candidate images were found.' }
    $metadataMap = Get-MetadataMap $SourceMetadata
    $candidates = @()

    for ($i = 0; $i -lt $files.Count; $i++) {
        $source = $files[$i]
        $number = $i + 1
        $extension = $source.Extension.ToLowerInvariant()
        $fileName = 'candidate-{0:D2}{1}' -f $number, $extension
        $destination = Join-Path $target (Join-Path 'candidates' $fileName)
        [IO.File]::Copy($source.FullName, $destination, $false)
        $dimensions = Get-ImageDimensions $destination
        $meta = $metadataMap[$source.Name]
        $candidate = [ordered]@{
            number = $number
            fileName = $fileName
            sourceFileName = $source.Name
            extension = $extension
            width = $dimensions.Width
            height = $dimensions.Height
            sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            imageUrl = [string](Get-PropertyValue $meta 'ImageUrl' '')
            pinUrl = [string](Get-PropertyValue $meta 'PinUrl' '')
            assetId = [string](Get-PropertyValue $meta 'AssetId' '')
            clarity = [int](Get-PropertyValue $meta 'Clarity' 0)
            fullSpace = [bool](Get-PropertyValue $meta 'FullSpace' $false)
            realism = [int](Get-PropertyValue $meta 'Realism' 0)
            cleanComposition = [int](Get-PropertyValue $meta 'CleanComposition' 0)
            styleMatch = [int](Get-PropertyValue $meta 'StyleMatch' 0)
            fullPath = $destination
            previewPath = $dimensions.PreviewPath
        }
        $candidates += [pscustomobject]$candidate
    }

    New-ContactSheet -Candidates $candidates -Path (Join-Path $target 'preview\contact-sheet.jpg')
    $csvRows = $candidates | ForEach-Object {
        [pscustomobject]@{ Candidate=$_.number; FileName=$_.fileName; Width=$_.width; Height=$_.height; SHA256=$_.sha256; ImageUrl=$_.imageUrl; PinUrl=$_.pinUrl; AssetId=$_.assetId; Clarity=$_.clarity; FullSpace=$_.fullSpace; Realism=$_.realism; CleanComposition=$_.cleanComposition; StyleMatch=$_.styleMatch }
    }
    $csvRows | Export-Csv -LiteralPath (Join-Path $target 'candidates.csv') -NoTypeInformation -Encoding UTF8

    $manifestCandidates = $candidates | ForEach-Object {
        [ordered]@{ number=$_.number; fileName=$_.fileName; sourceFileName=$_.sourceFileName; extension=$_.extension; width=$_.width; height=$_.height; sha256=$_.sha256; imageUrl=$_.imageUrl; pinUrl=$_.pinUrl; assetId=$_.assetId; clarity=$_.clarity; fullSpace=$_.fullSpace; realism=$_.realism; cleanComposition=$_.cleanComposition; styleMatch=$_.styleMatch }
    }
    $manifest = [ordered]@{
        schemaVersion = 1
        projectName = Split-Path -Leaf $target
        createdDate = $date
        createdAt = [datetime]::UtcNow.ToString('o')
        topic = $Topic
        style = $Style
        searchQuery = $SearchQuery
        candidates = @($manifestCandidates)
        currentSelection = @()
        selectionHistory = @()
    }
    Write-Utf8File -Path (Join-Path $target 'manifest.json') -Content ($manifest | ConvertTo-Json -Depth 10)
    Write-ProjectReadme -Manifest ([pscustomobject]$manifest) -Path (Join-Path $target 'README.md')
    return $target
}

function Invoke-Select {
    if (-not $ProjectDir -or -not (Test-Path -LiteralPath $ProjectDir -PathType Container)) { throw 'A valid ProjectDir is required for Select.' }
    if (-not $CandidateNumber -or $CandidateNumber.Count -eq 0) { throw 'CandidateNumber is required for Select.' }
    if (-not $Role -or $Role.Count -ne $CandidateNumber.Count) { throw 'Role must contain one value per candidate.' }
    $manifestPath = Join-Path $ProjectDir 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    $chosen = @()
    foreach ($number in $CandidateNumber) {
        $item = @($manifest.candidates | Where-Object { $_.number -eq $number })
        if ($item.Count -ne 1) { throw "Candidate $number does not exist." }
        $chosen += $item[0]
    }
    if ($Interior -and $chosen.Count -ge 2 -and -not ($chosen | Where-Object { $_.fullSpace })) {
        throw 'Interior selections with two or more images require at least one full-space candidate.'
    }

    $selectedDir = Join-Path $ProjectDir 'selected'
    Get-ChildItem -LiteralPath $selectedDir -File | Remove-Item -Force
    $current = @()
    for ($i = 0; $i -lt $chosen.Count; $i++) {
        $item = $chosen[$i]
        $roleName = Get-SafeName ($Role[$i].ToLowerInvariant()) ("view-$($i + 1)")
        $outputFile = '{0:D2}-{1}_candidate-{2:D2}{3}' -f ($i + 1), $roleName, [int]$item.number, $item.extension
        $source = Join-Path $ProjectDir (Join-Path 'candidates' $item.fileName)
        $destination = Join-Path $selectedDir $outputFile
        [IO.File]::Copy($source, $destination, $false)
        $current += [pscustomobject]@{ slot=$i + 1; candidateNumber=[int]$item.number; role=$Role[$i]; outputFile=$outputFile; sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash }
    }
    $previous = @($manifest.currentSelection)
    $history = @($manifest.selectionHistory)
    $history += [pscustomobject]@{ changedAt=[datetime]::UtcNow.ToString('o'); previous=$previous; current=$current }
    $manifest.currentSelection = $current
    $manifest.selectionHistory = $history
    Write-Utf8File -Path $manifestPath -Content ($manifest | ConvertTo-Json -Depth 12)
    Write-ProjectReadme -Manifest $manifest -Path (Join-Path $ProjectDir 'README.md')
    return $current | ForEach-Object { Join-Path $selectedDir $_.outputFile }
}

if ($Action -eq 'Build') { Invoke-Build } else { Invoke-Select }

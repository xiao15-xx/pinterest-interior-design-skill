param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function New-TestImage {
    param([string]$Path, [int]$Width, [int]$Height, [string]$Color)
    Add-Type -AssemblyName System.Drawing
    $bitmap = [System.Drawing.Bitmap]::new($Width, $Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::$Color)
        $graphics.DrawRectangle([System.Drawing.Pens]::White, 4, 4, $Width - 9, $Height - 9)
        $format = if ([IO.Path]::GetExtension($Path) -eq '.png') {
            [System.Drawing.Imaging.ImageFormat]::Png
        } else {
            [System.Drawing.Imaging.ImageFormat]::Jpeg
        }
        $bitmap.Save($Path, $format)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$skillRoot = Split-Path -Parent $PSScriptRoot
$workflow = Join-Path $skillRoot 'scripts\candidate_workflow.ps1'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("pinterest-interior-design-skill-test-" + [guid]::NewGuid().ToString('N'))
$inputDir = Join-Path $tempRoot 'input'
$outputRoot = Join-Path $tempRoot 'output'
New-Item -ItemType Directory -Path $inputDir, $outputRoot | Out-Null

try {
    New-TestImage (Join-Path $inputDir '01-wide.jpg') 640 360 'SaddleBrown'
    New-TestImage (Join-Path $inputDir '02-portrait.png') 360 540 'DarkOliveGreen'
    New-TestImage (Join-Path $inputDir '03-square.jpeg') 480 480 'SlateGray'

    $metadata = @(
        [pscustomobject]@{ FileName='01-wide.jpg'; ImageUrl='https://i.pinimg.com/wide.jpg'; PinUrl='https://pinterest.com/pin/1'; AssetId='asset-1'; Clarity=9; FullSpace=$true; Realism=9; CleanComposition=9; StyleMatch=9 },
        [pscustomobject]@{ FileName='02-portrait.png'; ImageUrl='https://i.pinimg.com/portrait.png'; PinUrl='https://pinterest.com/pin/2'; AssetId='asset-2'; Clarity=8; FullSpace=$false; Realism=8; CleanComposition=8; StyleMatch=9 },
        [pscustomobject]@{ FileName='03-square.jpeg'; ImageUrl='https://i.pinimg.com/square.jpeg'; PinUrl='https://pinterest.com/pin/3'; AssetId='asset-3'; Clarity=7; FullSpace=$false; Realism=8; CleanComposition=7; StyleMatch=8 }
    )
    $metadataPath = Join-Path $tempRoot 'source-metadata.json'
    $metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadataPath -Encoding utf8

    $sourceHashes = @{}
    Get-ChildItem -LiteralPath $inputDir -File | ForEach-Object {
        $sourceHashes[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }

    $projectDir = & $workflow -Action Build -InputDir $inputDir -OutputRoot $outputRoot `
        -Topic '书房' -Style '东方新中式' -SearchQuery '东方 新中式 书房 室内设计' `
        -ProjectDate '2026-06-19' -SourceMetadata $metadataPath

    Assert-True (Test-Path -LiteralPath $projectDir -PathType Container) 'Build returns an existing project directory.'
    Assert-True ((Split-Path -Leaf $projectDir) -eq '2026-06-19_书房_东方新中式') 'Project follows date_topic_style naming.'
    Assert-True (Test-Path -LiteralPath (Join-Path $projectDir 'preview\contact-sheet.jpg')) 'Contact sheet is generated.'
    Assert-True (Test-Path -LiteralPath (Join-Path $projectDir 'candidates.csv')) 'Candidate CSV is generated.'
    Assert-True (Test-Path -LiteralPath (Join-Path $projectDir 'manifest.json')) 'Manifest is generated.'
    Assert-True (Test-Path -LiteralPath (Join-Path $projectDir 'README.md')) 'README is generated.'

    $manifest = Get-Content -LiteralPath (Join-Path $projectDir 'manifest.json') -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($manifest.projectName -eq '2026-06-19_书房_东方新中式') 'Manifest records project name.'
    Assert-True ($manifest.candidates.Count -eq 3) 'Manifest records all candidates.'
    Assert-True ($manifest.candidates[0].fileName -eq 'candidate-01.jpg') 'Candidate numbers are stable.'
    Assert-True ($manifest.candidates[1].fileName -eq 'candidate-02.png') 'Original PNG extension is retained.'

    foreach ($candidate in $manifest.candidates) {
        $candidateHash = (Get-FileHash -LiteralPath (Join-Path $projectDir ("candidates\" + $candidate.fileName)) -Algorithm SHA256).Hash
        Assert-True ($candidateHash -eq $sourceHashes[$candidate.sourceFileName]) "Original bytes are preserved for $($candidate.fileName)."
    }

    $secondProject = & $workflow -Action Build -InputDir $inputDir -OutputRoot $outputRoot `
        -Topic '书房' -Style '东方新中式' -SearchQuery '东方 新中式 书房 室内设计' `
        -ProjectDate '2026-06-19' -SourceMetadata $metadataPath
    Assert-True ((Split-Path -Leaf $secondProject) -eq '2026-06-19_书房_东方新中式_02') 'Name collision increments suffix.'

    & $workflow -Action Select -ProjectDir $projectDir -CandidateNumber 1,2 -Role 'full-room','alternate-view' -Interior | Out-Null
    $selected = Get-ChildItem -LiteralPath (Join-Path $projectDir 'selected') -File | Sort-Object Name
    Assert-True ($selected.Count -eq 2) 'Select creates exactly two current files.'
    Assert-True ($selected[0].Name -eq '01-full-room_candidate-01.jpg') 'Full-room semantic filename is used.'
    Assert-True ($selected[1].Name -eq '02-alternate-view_candidate-02.png') 'Alternate-view filename retains source format.'

    $selectedHash = (Get-FileHash -LiteralPath $selected[0].FullName -Algorithm SHA256).Hash
    $candidateHash = (Get-FileHash -LiteralPath (Join-Path $projectDir 'candidates\candidate-01.jpg') -Algorithm SHA256).Hash
    Assert-True ($selectedHash -eq $candidateHash) 'Selected image bytes are unchanged.'

    & $workflow -Action Select -ProjectDir $projectDir -CandidateNumber 1,3 -Role 'full-room','alternate-view' -Interior | Out-Null
    $updated = Get-Content -LiteralPath (Join-Path $projectDir 'manifest.json') -Raw -Encoding utf8 | ConvertFrom-Json
    Assert-True ($updated.selectionHistory.Count -eq 2) 'Each selection operation is recorded.'
    Assert-True ($updated.currentSelection[1].candidateNumber -eq 3) 'Replacement updates the current selection.'
    Assert-True ((Get-ChildItem -LiteralPath (Join-Path $projectDir 'candidates') -File).Count -eq 3) 'Replacement never deletes candidates.'

    $failedAsExpected = $false
    try {
        & $workflow -Action Select -ProjectDir $projectDir -CandidateNumber 2,3 -Role 'detail','alternate-view' -Interior | Out-Null
    } catch {
        $failedAsExpected = $true
    }
    Assert-True $failedAsExpected 'Interior selections require at least one full-space candidate.'

    Write-Output 'PASS: candidate workflow behavior is correct.'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

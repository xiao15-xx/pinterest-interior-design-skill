[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ImageUrl,
    [Parameter(Mandatory=$true)][string]$PinUrl,
    [Parameter(Mandatory=$true)][string]$OutputDir,
    [Parameter(Mandatory=$true)][string]$FileName,
    [Parameter(Mandatory=$true)][ValidateRange(1,16)][int]$CandidateNumber,
    [string]$MetadataPath,
    [ValidateRange(1,120)][int]$TimeoutSeconds = 30,
    [ValidateRange(1,100)][int]$MaximumMegabytes = 25
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

function Assert-DPath {
    param([string]$Path, [string]$Name)
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath('D:\Codex--A')
    if ($full -ne $root -and -not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Name must be under D:\Codex--A."
    }
    return $full
}

function Assert-ImageUri {
    param([string]$Value, [string]$Name)
    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'i.pinimg.com') {
        throw "$Name must use HTTPS i.pinimg.com."
    }
    if ($uri.AbsolutePath -match '/(75x75_RS|136x136|170x|236x|474x)/') { throw "$Name must not use a preview-size path." }
    return $uri
}

function Get-ImageDimensions {
    param([string]$Path)
    try {
        $image = [Drawing.Image]::FromFile($Path)
        try { return [pscustomobject]@{ Width=$image.Width; Height=$image.Height } }
        finally { $image.Dispose() }
    } catch {
        $ffprobe = Get-Command ffprobe -ErrorAction SilentlyContinue
        if (-not $ffprobe) { return [pscustomobject]@{ Width=0; Height=0 } }
        $raw = & $ffprobe.Source -v quiet -print_format json -show_streams $Path
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return [pscustomobject]@{ Width=0; Height=0 } }
        $info = $raw | ConvertFrom-Json
        $stream = $info.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
        if (-not $stream) { return [pscustomobject]@{ Width=0; Height=0 } }
        return [pscustomobject]@{ Width=[int]$stream.width; Height=[int]$stream.height }
    }
}

$requestedUri = Assert-ImageUri $ImageUrl 'ImageUrl'
if ($PinUrl -notmatch '^https://([a-z]+\.)?pinterest\.[^/]+/pin/') { throw 'PinUrl must be a Pinterest Pin detail URL.' }
if ([IO.Path]::GetFileName($FileName) -ne $FileName) { throw 'FileName must not contain a path.' }
$extension = [IO.Path]::GetExtension($FileName).ToLowerInvariant()
if (@('.jpg','.jpeg','.png','.webp') -notcontains $extension) { throw 'FileName has an unsupported image extension.' }
$outputFull = Assert-DPath $OutputDir 'OutputDir'
if ($MetadataPath) { $metadataFull = Assert-DPath $MetadataPath 'MetadataPath' } else { $metadataFull = $null }
New-Item -ItemType Directory -Path $outputFull -Force | Out-Null
$destination = Join-Path $outputFull $FileName
if (Test-Path -LiteralPath $destination) { throw "Destination already exists: $destination" }
$staging = Join-Path $outputFull ('.download-' + [guid]::NewGuid().ToString('N') + $extension)

$handler = [Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $true
$handler.MaxAutomaticRedirections = 5
$client = [Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
$client.DefaultRequestHeaders.Referrer = [Uri]$PinUrl
$client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0 PinterestInteriorReference/1.0')
$response = $null
$inputStream = $null
$outputStream = $null
try {
    $response = $client.GetAsync($requestedUri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    if (-not $response.IsSuccessStatusCode) { throw "Image request failed with HTTP $([int]$response.StatusCode)." }
    $finalUri = $response.RequestMessage.RequestUri
    [void](Assert-ImageUri $finalUri.AbsoluteUri 'FinalImageUrl')
    $contentType = [string]$response.Content.Headers.ContentType.MediaType
    if (@('image/jpeg','image/png','image/webp') -notcontains $contentType) { throw "Unsupported response content type: $contentType" }
    $maximumBytes = [long]$MaximumMegabytes * 1MB
    if ($response.Content.Headers.ContentLength -and [long]$response.Content.Headers.ContentLength -gt $maximumBytes) { throw 'Image exceeds MaximumMegabytes.' }
    $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $outputStream = [IO.File]::Open($staging, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $buffer = [byte[]]::new(65536)
    $total = 0L
    while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $total += $read
        if ($total -gt $maximumBytes) { throw 'Image exceeds MaximumMegabytes.' }
        $outputStream.Write($buffer, 0, $read)
    }
    $outputStream.Dispose(); $outputStream = $null
    $inputStream.Dispose(); $inputStream = $null
    $dimensions = Get-ImageDimensions $staging
    if ($dimensions.Width -le 0 -or $dimensions.Height -le 0) { throw 'Downloaded image cannot be decoded.' }
    [IO.File]::Move($staging, $destination)
    $record = [ordered]@{
        CandidateNumber=$CandidateNumber
        FileName=$FileName
        ImageUrl=$ImageUrl
        FinalImageUrl=$finalUri.AbsoluteUri
        PinUrl=$PinUrl
        DownloadMethod='controlled-url'
        DownloadStatus='success'
        ContentType=$contentType
        Bytes=$total
        Width=[int]$dimensions.Width
        Height=[int]$dimensions.Height
        SHA256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    }
    $json = $record | ConvertTo-Json -Compress
    if ($metadataFull) {
        $parent = Split-Path -Parent $metadataFull
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($metadataFull, $json, [Text.UTF8Encoding]::new($true))
    }
    Write-Output $json
} finally {
    if ($outputStream) { $outputStream.Dispose() }
    if ($inputStream) { $inputStream.Dispose() }
    if ($response) { $response.Dispose() }
    $client.Dispose()
    $handler.Dispose()
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Force }
}

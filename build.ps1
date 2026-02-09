# build.ps1 - Markdown to PDF build script
param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile
)

$ErrorActionPreference = "Stop"

# Resolve paths
$InputFile = Resolve-Path $InputFile
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutputFile = [System.IO.Path]::ChangeExtension($InputFile, ".pdf")
$FileName = Split-Path -Leaf $InputFile

Write-Host "Building: $FileName -> $(Split-Path -Leaf $OutputFile)" -ForegroundColor Cyan

# Detect mmdc (mermaid-cli) and set environment variable for mermaid.lua
if (-not $env:MERMAID_MMDC) {
    $mmdc = Get-Command mmdc -ErrorAction SilentlyContinue
    if (-not $mmdc) {
        # Check npm global bin directory
        $npmRoot = & npm root -g 2>$null
        if ($npmRoot) {
            $npmBin = Split-Path -Parent $npmRoot
            $mmdcPath = Join-Path $npmBin "mmdc.cmd"
            if (Test-Path $mmdcPath) {
                $env:MERMAID_MMDC = $mmdcPath
                Write-Host "Found mmdc at: $mmdcPath" -ForegroundColor Gray
            }
        }
    }
    if (-not $env:MERMAID_MMDC -and -not $mmdc) {
        Write-Host "Warning: mmdc not found. Mermaid diagrams will not be rendered." -ForegroundColor Yellow
    }
}

# Build pandoc arguments
$pandocArgs = @(
    $InputFile
    "-f", "markdown-smart"
    "-o", $OutputFile
    "--pdf-engine=xelatex"
    "--lua-filter=$ScriptDir\pandoc\mermaid.lua"
    "--lua-filter=$ScriptDir\pandoc\paper-filter.lua"
    "--filter=pandoc-crossref"
    "--citeproc"
    "--bibliography=$ScriptDir\references.bib"
    "--csl=$ScriptDir\japanese-reference.csl"
    "--lua-filter=$ScriptDir\pandoc\cite-superscript.lua"
    "--number-sections"
    "-V", "mainfont=Harano Aji Mincho"
    "-V", "geometry:top=30mm,bottom=30mm,left=20mm,right=20mm"
    "--include-in-header=$ScriptDir\pandoc\header.tex"
)

# Run pandoc
Write-Host "Running pandoc..." -ForegroundColor Yellow
& pandoc @pandocArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful: $OutputFile" -ForegroundColor Green
} else {
    Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

# Prepara uma versão local. Não envia arquivos nem altera a Play Console.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoDir = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoDir 'micro_arca_app'
$pubspec = Get-Content -LiteralPath (Join-Path $appDir 'pubspec.yaml') -Raw -Encoding UTF8
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if (-not $versionMatch.Success) { throw 'Use version: X.Y.Z+N no pubspec.yaml.' }
$versionName = $versionMatch.Groups[1].Value
$versionCode = $versionMatch.Groups[2].Value
$version = "$versionName+$versionCode"
$notesPath = Join-Path $appDir "release_notes/$versionName-pt-BR.txt"
if (-not (Test-Path -LiteralPath $notesPath)) { throw "Crie as notas da versão: $notesPath" }
$notes = (Get-Content -LiteralPath $notesPath -Raw -Encoding UTF8).Trim()
if (-not $notes -or $notes.Length -gt 500) { throw 'As notas em pt-BR devem ter de 1 a 500 caracteres.' }
$keyConfig = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.microarca/play-upload.properties'
if (-not (Test-Path -LiteralPath $keyConfig)) { throw 'Configuração da chave de envio ausente em .microarca/play-upload.properties.' }
$flutter = (Get-Command flutter.bat -ErrorAction Stop).Source
$node = (Get-Command node -ErrorAction Stop).Source
$python = (Get-Command python -ErrorAction Stop).Source
$javaCandidates = @()
if ($env:JAVA_HOME) { $javaCandidates += (Join-Path $env:JAVA_HOME 'bin/jarsigner.exe') }
$javaCandidates += (Join-Path $env:ProgramFiles 'Android/Android Studio/jbr/bin/jarsigner.exe')
$installedSigner = Get-Command jarsigner -ErrorAction SilentlyContinue
if ($installedSigner) { $javaCandidates += $installedSigner.Source }
$signer = $javaCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $signer) { throw 'jarsigner não encontrado. Instale/configure o JDK do Android Studio ou JAVA_HOME.' }

$outputDir = Join-Path $appDir "build/publicacao/$version"
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$logPath = Join-Path $outputDir 'preparacao.log'
[IO.File]::WriteAllText($logPath, "Preparação MicroARCA $version`n", [Text.UTF8Encoding]::new($false))

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments, [switch]$Quiet)
    Write-Host "`n> $([IO.Path]::GetFileName($Program)) $($Arguments -join ' ')"
    # Windows PowerShell trata stderr de programas nativos como ErrorRecord.
    # O código de saída, e não a presença de um aviso em stderr, determina falha.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Program @Arguments 2>&1 | ForEach-Object {
            $line = "$_"
            Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
            if (-not $Quiet) { Write-Output $line }
        }
        $nativeCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($nativeCode -ne 0) { throw "Comando falhou (código $nativeCode). Consulte $logPath" }
}

Push-Location $appDir
try {
    Invoke-Checked $flutter @('pub', 'get')
    Invoke-Checked $flutter @('analyze', '--no-pub')
    Invoke-Checked $flutter @('test', '--no-pub', '--reporter', 'expanded')
    # O teste de while inclui os testes existentes de IO e executa Python local.
    $previousPython = $env:PYTHON
    try {
        $env:PYTHON = $python
        Invoke-Checked $node @('test/blockly_while_test.mjs')
    } finally { $env:PYTHON = $previousPython }
    Push-Location (Join-Path $appDir 'android')
    try {
        Invoke-Checked (Join-Path (Get-Location).Path 'gradlew.bat') @(':app:testDebugUnitTest', '--tests', 'com.microarca.app.*Test', '--console=plain')
    } finally { Pop-Location }
    Invoke-Checked $flutter @('build', 'appbundle', '--release', '--no-pub')
    $bundle = Join-Path $outputDir "MicroARCA-$version.aab"
    Copy-Item -LiteralPath (Join-Path $appDir 'build/app/outputs/bundle/release/app-release.aab') -Destination $bundle -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($bundle)
    try {
        $signature = @($archive.Entries | Where-Object { $_.FullName -match '^META-INF/[^/]+\.(RSA|DSA|EC)$' })
        if ($signature.Count -eq 0) { throw 'O AAB não contém assinatura. Confira a configuração de envio.' }
    } finally { $archive.Dispose() }
    Invoke-Checked $signer @('-verify', $bundle) -Quiet
    Write-Host 'Assinatura conferida. Detalhes e avisos do certificado em preparacao.log.'
    Copy-Item -LiteralPath $notesPath -Destination (Join-Path $outputDir 'notas-pt-BR.txt') -Force
    $releaseNotes = "<pt-BR>`n$notes`n</pt-BR>`n"
    [IO.File]::WriteAllText((Join-Path $outputDir 'notas-para-play-console.txt'), $releaseNotes, [Text.UTF8Encoding]::new($false))
    $hash = (Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash
    [IO.File]::WriteAllText((Join-Path $outputDir 'SHA256.txt'), "$hash  $([IO.Path]::GetFileName($bundle))`n", [Text.UTF8Encoding]::new($false))
    $manifest = [ordered]@{
        versao = $versionName; codigo = [int]$versionCode
        preparadoEm = (Get-Date).ToString('o')
        pacote = 'com.microarca.app'; arquivo = [IO.Path]::GetFileName($bundle)
        bytes = (Get-Item -LiteralPath $bundle).Length; sha256 = $hash
        enviadoParaPlay = $false
    } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $outputDir 'versao.json'), $manifest, [Text.UTF8Encoding]::new($false))
    Write-Host "`nVersão $version preparada: $outputDir"
    Write-Host 'Nada foi enviado à Play. Siga docs/publicar-versao-play.md.'
} finally { Pop-Location }

# Восстановление на новом Windows-сервере из move-backup-*.zip.
# Перед запуском на новом сервере: установить FreeLLMAPI (.exe из релизов),
# один раз открыть и закрыть его (Quit), установить Node.js.
# Запускается через restore-after-move.cmd, архив — на Рабочем столе или
# выбирается вручную.

$ErrorActionPreference = 'Stop'
function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Fail($text) { Say ''; Say $text 'Red'; Read-Host 'Нажмите Enter, чтобы закрыть'; exit 1 }

$desktop = [Environment]::GetFolderPath('Desktop')
$zip = Get-ChildItem -LiteralPath $desktop -Filter 'move-backup-*.zip' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($zip) {
    $zipPath = $zip.FullName
} else {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Архив переезда (move-backup-*.zip)|move-backup-*.zip|ZIP|*.zip'
    $dlg.Title = 'Выберите архив move-backup-....zip'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Fail 'Архив не выбран.' }
    $zipPath = $dlg.FileName
}
Say "Архив: $zipPath" 'Green'

$running = Get-Process -Name 'FreeLLMAPI' -ErrorAction SilentlyContinue
if ($running) {
    Say 'Закрываю FreeLLMAPI...' 'Cyan'
    $running | Stop-Process -Force
    Start-Sleep -Seconds 3
}

$stage = Join-Path ([IO.Path]::GetTempPath()) ('move-restore-' + (Get-Date -Format 'yyyyMMddHHmmss'))
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $stage)

# Всё, что будет перезаписано, сначала откладываем в *.before-restore-<время>.
$suffix = '.before-restore-' + (Get-Date -Format 'yyyyMMddHHmmss')
function Put-Back($source, $target) {
    if (-not (Test-Path -LiteralPath $source)) { return }
    if (Test-Path -LiteralPath $target) { Rename-Item -LiteralPath $target -NewName ((Split-Path $target -Leaf) + $suffix) }
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Move-Item -LiteralPath $source -Destination $target
    Say "  восстановлено: $target" 'Green'
}

Say 'Раскладываю файлы:' 'Cyan'
Put-Back (Join-Path $stage 'FreeLLMAPI') (Join-Path $env:APPDATA 'FreeLLMAPI')
Put-Back (Join-Path $stage 'claude\.claude') (Join-Path $env:USERPROFILE '.claude')
Put-Back (Join-Path $stage 'claude\.claude.json') (Join-Path $env:USERPROFILE '.claude.json')
Put-Back (Join-Path $stage 'claude-free') (Join-Path $desktop 'Claude free')
foreach ($pair in @(@('Desktop', $desktop), @('Documents', [Environment]::GetFolderPath('MyDocuments')))) {
    $src = Join-Path $stage $pair[0]
    if (Test-Path -LiteralPath $src) {
        # Рабочий стол и Документы не заменяем, а дополняем: существующие файлы не трогаем.
        Get-ChildItem -LiteralPath $src -Force | ForEach-Object {
            $dest = Join-Path $pair[1] $_.Name
            if (Test-Path -LiteralPath $dest) { Say "  уже есть, пропущено: $dest" 'DarkGray' }
            else { Move-Item -LiteralPath $_.FullName -Destination $dest; Say "  восстановлено: $dest" 'Green' }
        }
    }
}
Remove-Item -LiteralPath $stage -Recurse -Force

# Ярлык и ключ создаст первый запуск claude-free.cmd; путь к папке проекта сбрасываем.
[Environment]::SetEnvironmentVariable('FREELLMAPI_CLAUDE_LAST_DIR', $null, 'User')

Say ''
Say 'Готово. Дальше: папка "Claude free" на Рабочем столе -> двойной клик по claude-free.cmd.' 'Green'
Say 'Он запустит FreeLLMAPI, попросит один раз нажать "Copy Key" и создаст ярлык "Claude FREE".' 'Gray'
Read-Host 'Нажмите Enter, чтобы закрыть'

# Архив для переезда на новый Windows-сервер.
# Запускается через backup-for-move.cmd. Кладёт на Рабочий стол
# move-backup-<дата>.zip, в котором:
#   FreeLLMAPI\   — вся папка %APPDATA%\FreeLLMAPI: база с ключами провайдеров,
#                   файл ключа шифрования .encryption-key (без него ключи не
#                   расшифруются), config.json, логи;
#   claude\.claude, claude\.claude.json — настройки и сессии Claude Code;
#   claude-free\  — скрипты запуска (эта папка);
#   Desktop\, Documents\ — по желанию.
# В архиве секреты: храните его только в личном месте.

$ErrorActionPreference = 'Stop'
function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Fail($text) { Say ''; Say $text 'Red'; Read-Host 'Нажмите Enter, чтобы закрыть'; exit 1 }

$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm'
$desktop = [Environment]::GetFolderPath('Desktop')
$zipPath = Join-Path $desktop "move-backup-$stamp.zip"
$stage = Join-Path ([IO.Path]::GetTempPath()) "move-backup-$stamp"

Say 'Перед архивацией закройте все окна Claude Code.' 'Yellow'
$includeUserDirs = (Read-Host 'Добавить в архив Рабочий стол и Документы? (y — да, Enter — нет)').Trim().ToLower() -eq 'y'

# SQLite нельзя копировать на ходу: сначала закрываем FreeLLMAPI.
$running = Get-Process -Name 'FreeLLMAPI' -ErrorAction SilentlyContinue
if ($running) {
    Say 'Закрываю FreeLLMAPI, чтобы база скопировалась целой...' 'Cyan'
    $running | Stop-Process -Force
    Start-Sleep -Seconds 3
}

New-Item -ItemType Directory -Path $stage -Force | Out-Null
function Copy-Into($source, $target) {
    if (-not (Test-Path -LiteralPath $source)) { Say "  нет: $source" 'DarkGray'; return }
    $dest = Join-Path $stage $target
    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $dest -Recurse -Force
    Say "  добавлено: $source" 'Green'
}

Say 'Собираю файлы:' 'Cyan'
Copy-Into (Join-Path $env:APPDATA 'FreeLLMAPI') 'FreeLLMAPI'
Copy-Into (Join-Path $env:USERPROFILE '.claude') 'claude\.claude'
Copy-Into (Join-Path $env:USERPROFILE '.claude.json') 'claude\.claude.json'
Copy-Into $PSScriptRoot 'claude-free'
if ($includeUserDirs) {
    Copy-Into $desktop 'Desktop'
    Copy-Into ([Environment]::GetFolderPath('MyDocuments')) 'Documents'
    # архивы переезда на Рабочем столе в архив не кладём
    Get-ChildItem -LiteralPath (Join-Path $stage 'Desktop') -Filter 'move-backup-*.zip' -ErrorAction SilentlyContinue |
        Remove-Item -Force
}

if (-not (Test-Path (Join-Path $stage 'FreeLLMAPI\.encryption-key'))) {
    Say ''
    Say 'Внимание: файл FreeLLMAPI\.encryption-key не найден — ключи провайдеров на новом сервере придётся добавить заново.' 'Yellow'
}

Say ''
Say 'Упаковываю архив...' 'Cyan'
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath)
Remove-Item -LiteralPath $stage -Recurse -Force

$sizeMb = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)
Say ''
Say "Готово: $zipPath ($sizeMb МБ)" 'Green'
Say 'В архиве ваши ключи — не выкладывайте его в открытый доступ.' 'Yellow'
Say 'FreeLLMAPI закрыт; запустите его снова ярлыком "Claude FREE" или из меню Пуск.' 'Gray'
Read-Host 'Нажмите Enter, чтобы закрыть'

# Запуск Claude Code через локальный шлюз FreeLLMAPI (бесплатные модели).
# Windows, PowerShell 5.1+. Запускается через claude-free.cmd или ярлык
# «Claude FREE» на Рабочем столе, который скрипт создаёт при первом запуске.
#
# Что делает:
#   1. находит десктоп-приложение FreeLLMAPI (порт из
#      %APPDATA%\FreeLLMAPI\config.json, затем 31415 и 3001) и запускает его,
#      если оно выключено;
#   2. берёт unified-ключ из переменной пользователя FREELLMAPI_API_KEY или из
#      буфера обмена (трей → Copy Key), проверяет и сохраняет его;
#   3. один раз включает FREELLMAPI_CONTEXT_HANDOFF=on_model_switch;
#   4. при необходимости ставит Claude Code через npm;
#   5. спрашивает папку проекта (запоминает последнюю) и режим: новая сессия
#      или продолжение старой;
#   6. запускает claude в режиме manual (спрашивает разрешение на действия) с
#      ANTHROPIC_BASE_URL/ANTHROPIC_AUTH_TOKEN только для этого окна — обычный
#      `claude` остаётся на подписке.

$ErrorActionPreference = 'Stop'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Fail($text) {
    Say ''
    Say $text 'Red'
    Say ''
    Read-Host 'Нажмите Enter, чтобы закрыть'
    exit 1
}
function Get-UserVar($name) { [Environment]::GetEnvironmentVariable($name, 'User') }
function Set-UserVar($name, $value) { [Environment]::SetEnvironmentVariable($name, $value, 'User') }

# --- 1. Шлюз -----------------------------------------------------------------
function Get-GatewayPorts {
    $ports = @()
    $configPath = Join-Path $env:APPDATA 'FreeLLMAPI\config.json'
    if (Test-Path $configPath) {
        try {
            $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($cfg.port) { $ports += [int]$cfg.port }
        } catch { }
    }
    $ports += 31415, 3001
    return $ports | Select-Object -Unique
}

function Find-Gateway {
    foreach ($p in (Get-GatewayPorts)) {
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:$p/livez" -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) { return "http://127.0.0.1:$p" }
        } catch { }
    }
    return $null
}

function Find-DesktopApp {
    $candidates = @()
    if ($env:LOCALAPPDATA) { $candidates += [IO.Path]::Combine($env:LOCALAPPDATA, 'Programs', 'FreeLLMAPI', 'FreeLLMAPI.exe') }
    if ($env:ProgramFiles) { $candidates += [IO.Path]::Combine($env:ProgramFiles, 'FreeLLMAPI', 'FreeLLMAPI.exe') }
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    return $null
}

$base = Find-Gateway
if (-not $base) {
    $app = Find-DesktopApp
    if (-not $app) {
        Fail ("FreeLLMAPI не запущен, и приложение не найдено в обычных местах установки.`n" +
              "Запустите FreeLLMAPI вручную (значок у часов) и откройте этот ярлык снова.")
    }
    Say 'Запускаю FreeLLMAPI...' 'Cyan'
    Start-Process -FilePath $app
    for ($i = 0; $i -lt 30 -and -not $base; $i++) {
        Start-Sleep -Seconds 2
        $base = Find-Gateway
    }
    if (-not $base) {
        Fail 'FreeLLMAPI запустился, но не отвечает уже минуту. Пришлите скриншот этого окна.'
    }
}
Say "Шлюз FreeLLMAPI работает: $base" 'Green'

# --- 2. Ключ -----------------------------------------------------------------
function Test-Key($key) {
    try {
        $r = Invoke-WebRequest -Uri "$base/v1/models" -UseBasicParsing -TimeoutSec 10 `
            -Headers @{ Authorization = "Bearer $key" }
        return $r.StatusCode -eq 200
    } catch { return $false }
}

$key = Get-UserVar 'FREELLMAPI_API_KEY'
if ($key -and -not (Test-Key $key)) {
    Say 'Сохранённый ключ не подошёл, нужен новый.' 'Yellow'
    $key = $null
}
while (-not $key) {
    Say ''
    Say 'Нажмите на значок FreeLLMAPI у часов -> "Copy Key".' 'Cyan'
    Read-Host 'Потом вернитесь сюда и нажмите Enter'
    $clip = (Get-Clipboard -Raw)
    if ($clip) { $clip = $clip.Trim() }
    if (-not $clip -or -not $clip.StartsWith('freellmapi-')) {
        Say 'В буфере обмена нет ключа вида freellmapi-... Попробуйте ещё раз.' 'Yellow'
        continue
    }
    if (-not (Test-Key $clip)) {
        Say 'Шлюз не принял этот ключ. Скопируйте его ещё раз через "Copy Key".' 'Yellow'
        continue
    }
    $key = $clip
    Set-UserVar 'FREELLMAPI_API_KEY' $key
    Say 'Ключ проверен и сохранён.' 'Green'
}

# --- 3. Передача контекста при смене модели ----------------------------------
if ((Get-UserVar 'FREELLMAPI_CONTEXT_HANDOFF') -ne 'on_model_switch') {
    Set-UserVar 'FREELLMAPI_CONTEXT_HANDOFF' 'on_model_switch'
    Say ''
    Say 'Включена передача контекста при смене модели.' 'Green'
    Say 'Она заработает после перезапуска FreeLLMAPI: значок у часов -> "Quit FreeLLMAPI", затем снова этот ярлык.' 'Yellow'
}

# --- 4. Claude Code ----------------------------------------------------------
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Fail 'Не найден npm. Установите Node.js с https://nodejs.org, перезагрузите компьютер и запустите этот файл снова.'
    }
    Say ''
    Say 'Claude Code не установлен. Устанавливаю (npm install -g @anthropic-ai/claude-code)...' 'Cyan'
    & npm install -g '@anthropic-ai/claude-code'
    if ($LASTEXITCODE -ne 0) { Fail 'Установка Claude Code не удалась. Пришлите скриншот этого окна.' }
    $npmPrefix = (& npm prefix -g).Trim()
    if ($npmPrefix) { $env:Path = "$npmPrefix;$env:Path" }
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Fail 'Claude Code установлен, но команда claude не найдена. Закройте окно и запустите файл снова.'
    }
}

# --- 5. Ярлык на Рабочем столе (один раз) ------------------------------------
function Install-DesktopShortcut {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop) { return }
    $lnkPath = Join-Path $desktop 'Claude FREE.lnk'
    if (Test-Path $lnkPath) { return }
    $cmdPath = Join-Path $PSScriptRoot 'claude-free.cmd'
    if (-not (Test-Path $cmdPath)) { return }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($lnkPath)
        $lnk.TargetPath = $cmdPath
        $lnk.WorkingDirectory = $PSScriptRoot
        $lnk.Description = 'Claude Code на бесплатных моделях (FreeLLMAPI)'
        $app = Find-DesktopApp
        if ($app) { $lnk.IconLocation = "$app,0" }
        $lnk.Save()
        Say 'На Рабочем столе создан ярлык "Claude FREE" — дальше запускайте через него.' 'Green'
    } catch { }
}
Install-DesktopShortcut

# --- 6. Папка проекта и режим ------------------------------------------------
function Select-ProjectFolder($initial) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Выберите папку проекта, в которой будет работать Claude'
    $dlg.ShowNewFolderButton = $true
    if ($initial -and (Test-Path $initial)) { $dlg.SelectedPath = $initial }
    $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
    try {
        if ($dlg.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
        return $null
    } finally { $owner.Dispose() }
}

$last = Get-UserVar 'FREELLMAPI_CLAUDE_LAST_DIR'
if (-not $last -or -not (Test-Path $last)) { $last = [Environment]::GetFolderPath('MyDocuments') }
Say ''
Say 'Выберите папку проекта в открывшемся окне (оно может быть позади этого).' 'Cyan'
$folder = Select-ProjectFolder $last
if (-not $folder) { Fail 'Папка не выбрана.' }
Set-UserVar 'FREELLMAPI_CLAUDE_LAST_DIR' $folder
Set-Location -LiteralPath $folder
Say "Папка: $folder" 'Green'

Say ''
Say '  1 — новая сессия (просто Enter)' 'Gray'
Say '  2 — продолжить последнюю сессию в этой папке' 'Gray'
Say '  3 — выбрать старую сессию из списка' 'Gray'
$choice = (Read-Host 'Ваш выбор').Trim()
$claudeArgs = @('--permission-mode', 'manual')
switch ($choice) {
    '2' { $claudeArgs += '--continue' }
    '3' { $claudeArgs += '--resume' }
}

# --- 7. Запуск ---------------------------------------------------------------
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
$env:ANTHROPIC_BASE_URL = $base
$env:ANTHROPIC_AUTH_TOKEN = $key

Say ''
Say 'Запускаю Claude Code на бесплатных моделях.' 'Green'
Say 'Перед каждым действием он спросит разрешение. Выход — /exit.' 'Gray'
Say ''
$started = Get-Date
& claude @claudeArgs @args
$code = $LASTEXITCODE

# --continue/--resume без прошлых сессий в этой папке сразу завершается с
# ошибкой — в этом случае начинаем новую сессию.
if ($code -ne 0 -and $choice -in @('2', '3') -and ((Get-Date) - $started).TotalSeconds -lt 15) {
    Say ''
    Say 'Похоже, в этой папке нет прошлых сессий. Начинаю новую.' 'Yellow'
    Say ''
    & claude --permission-mode manual @args
    $code = $LASTEXITCODE
}

if ($code -ne 0) {
    Say ''
    Say "Claude Code завершился с ошибкой (код $code). Сфотографируйте это окно и пришлите скриншот." 'Red'
    Read-Host 'Нажмите Enter, чтобы закрыть'
}

# Запуск Claude Code через локальный шлюз FreeLLMAPI (бесплатные модели).
# Windows, PowerShell 5.1+. Запускается через claude-free.cmd двойным кликом.
#
# Что делает:
#   1. находит запущенное десктоп-приложение FreeLLMAPI (порт из
#      %APPDATA%\FreeLLMAPI\config.json, затем 31415 и 3001);
#   2. берёт unified-ключ из переменной пользователя FREELLMAPI_API_KEY или из
#      буфера обмена (трей → Copy Key) и сохраняет его в эту переменную;
#   3. один раз включает FREELLMAPI_CONTEXT_HANDOFF=on_model_switch;
#   4. при необходимости ставит Claude Code через npm;
#   5. запускает claude с ANTHROPIC_BASE_URL/ANTHROPIC_AUTH_TOKEN только для
#      этого окна — обычный `claude` остаётся на подписке.

$ErrorActionPreference = 'Stop'

function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Fail($text) {
    Say ''
    Say $text 'Red'
    Say ''
    Read-Host 'Нажмите Enter, чтобы закрыть'
    exit 1
}

# --- 1. Шлюз -----------------------------------------------------------------
$ports = @()
$configPath = Join-Path $env:APPDATA 'FreeLLMAPI\config.json'
if (Test-Path $configPath) {
    try {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($cfg.port) { $ports += [int]$cfg.port }
    } catch { }
}
$ports += 31415, 3001
$ports = $ports | Select-Object -Unique

$base = $null
foreach ($p in $ports) {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$p/livez" -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) { $base = "http://127.0.0.1:$p"; break }
    } catch { }
}
if (-not $base) {
    Fail ("Шлюз FreeLLMAPI не отвечает (проверены порты: $($ports -join ', ')).`n" +
          "Запустите приложение FreeLLMAPI (значок у часов) и запустите этот файл снова.")
}
Say "Шлюз найден: $base" 'Green'

# --- 2. Ключ -----------------------------------------------------------------
function Test-Key($key) {
    try {
        $r = Invoke-WebRequest -Uri "$base/v1/models" -UseBasicParsing -TimeoutSec 10 `
            -Headers @{ Authorization = "Bearer $key" }
        return $r.StatusCode -eq 200
    } catch { return $false }
}

$key = [Environment]::GetEnvironmentVariable('FREELLMAPI_API_KEY', 'User')
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
    [Environment]::SetEnvironmentVariable('FREELLMAPI_API_KEY', $key, 'User')
    Say 'Ключ проверен и сохранён.' 'Green'
}

# --- 3. Передача контекста при смене модели ----------------------------------
if ([Environment]::GetEnvironmentVariable('FREELLMAPI_CONTEXT_HANDOFF', 'User') -ne 'on_model_switch') {
    [Environment]::SetEnvironmentVariable('FREELLMAPI_CONTEXT_HANDOFF', 'on_model_switch', 'User')
    Say ''
    Say 'Включена передача контекста при смене модели.' 'Green'
    Say 'Чтобы она заработала, один раз перезапустите FreeLLMAPI: значок у часов -> "Quit FreeLLMAPI", затем откройте приложение снова.' 'Yellow'
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

# --- 5. Запуск ---------------------------------------------------------------
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
$env:ANTHROPIC_BASE_URL = $base
$env:ANTHROPIC_AUTH_TOKEN = $key

Say ''
Say 'Запускаю Claude Code на бесплатных моделях.' 'Green'
Say 'Старую сессию можно продолжить командой /resume. Выход — /exit.' 'Gray'
Say ''
& claude @args

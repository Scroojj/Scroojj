---
name: freellmapi
description: Установка и подключение FreeLLMAPI — self-hosted роутера, который собирает бесплатные лимиты многих LLM-провайдеров за одним OpenAI/Anthropic-совместимым API, — к Claude Code, Codex CLI, Gemini CLI и другим агентам. Используй, когда пользователь хочет работать на бесплатных моделях после исчерпания платных лимитов, упоминает FreeLLMAPI / freellmapi / «бесплатный роутер моделей», просит настроить ANTHROPIC_BASE_URL на локальный шлюз, включить передачу контекста при смене модели или разобраться, почему агент не доходит до шлюза.
---

# FreeLLMAPI: бесплатные модели для Claude Code / Codex / Gemini CLI

Источник всего ниже — репозиторий https://github.com/tashfeenahmed/freellmapi
(лицензия MIT), проверено по коммиту `eadbeb5` от 2026-09-22. Проект меняется
быстро: перед действиями сверяйся с актуальными файлами, ссылки на которые даны
в каждом разделе. Не выдавай цифры и поведение из этого файла за текущие, если
не перепроверил их.

## Что это и чего ожидать (скажи пользователю честно)

- Локальный сервер (Docker/исходники — порт 3001, десктоп-приложение — 31415), который принимает запросы в форматах OpenAI
  (`/v1/...`), Anthropic Messages (`/v1/messages`) и Gemini (`/v1beta`) и
  раскидывает их по бесплатным тарифам провайдеров, чьи ключи ты добавил.
  При 429/5xx переключается на следующую модель в цепочке. — `README.md`, разделы
  *Features*, *How it works*.
- Цифры из README (заявлены авторами, не проверены мной): ~7,4 млрд токенов/мес,
  34 провайдера, 474 семейства моделей, 635 бесплатных эндпоинтов. — `README.md`,
  раздел *Premium (live catalog)*.
- **Важно:** Claude Code через этот шлюз работает **не на моделях Claude**, а на
  бесплатных моделях других провайдеров — Claude Code остаётся только
  «оболочкой». README прямо пишет: «no frontier models, variable latency, no SLA»,
  качество падает к концу дня, когда лучшие модели исчерпывают дневные лимиты
  (сброс в полночь UTC). — `README.md`, раздел *Limitations*.
- Лимиты берутся только у тех провайдеров, для которых пользователь сам
  зарегистрировался и добавил ключ. 7,4 млрд — сумма по всем 34, а не то, что
  получится «из коробки».
- Проект позиционируется как «for personal experimentation and learning, not
  production»; условия каждого провайдера продолжают действовать. — `README.md`,
  раздел *Disclaimer*.
- Бесплатная установка получает каталог моделей с задержкой 30 дней; мгновенный
  каталог — платный ($19/год). Сам роутер бесплатен. — `README.md`, *Premium*.

## Шаг 1. Установить и запустить шлюз

Выбери один вариант (`README.md` → *Quick start*, `docs/en/install/01-install.md`):

**A. Однострочник (нужен Docker):**
```bash
curl -fsSL https://freellmapi.co/install.sh | bash
```
Перед запуском предложи пользователю прочитать скрипт: https://freellmapi.co/install.sh.

**B. Docker Compose вручную:**
```bash
git clone https://github.com/tashfeenahmed/freellmapi.git
cd freellmapi
ENCRYPTION_KEY="$(openssl rand -hex 32)"
printf "ENCRYPTION_KEY=%s\nPORT=3001\n" "$ENCRYPTION_KEY" > .env
docker compose up -d
```
`ENCRYPTION_KEY` обязателен и шифрует ключи провайдеров (AES-256-GCM). Его
потеря = потеря сохранённых ключей; при обновлении сохраняй тот же `.env` и том.

**C. Десктоп-приложение** (macOS `.dmg` / Windows `.exe`):
https://github.com/tashfeenahmed/freellmapi/releases/latest
(если список файлов на странице не грузится — он доступен по
`https://github.com/tashfeenahmed/freellmapi/releases/expanded_assets/<тег>`).

**Порт у десктоп-приложения другой: по умолчанию 31415**, а фактический порт
записывается в `config.json` (`desktop/src/main.ts`, `DEFAULT_PORT`/`saveConfig`):
Windows `%APPDATA%\FreeLLMAPI\config.json`, macOS
`~/Library/Application Support/FreeLLMAPI/config.json`, Linux
`~/.config/FreeLLMAPI/config.json`. Дашборд — трей → **Open Dashboard**, ключ —
трей → **Copy Key**. Закрытие окна не останавливает шлюз (он живёт в трее);
**Start at login** в меню трея включает автозапуск; `.env` у десктопа нет.
Ниже в примерах `3001` — для Docker; для десктопа подставляй свой порт.

Проверка, что сервер жив:
```bash
curl -fsS http://localhost:3001/livez
```
(эндпоинт определён в `server/src/routes/status.ts`).

По умолчанию контейнер слушает только `127.0.0.1`. `HOST_BIND=0.0.0.0` открывает
его в сеть — делай так только в доверенной сети: шлюз защищён лишь unified-ключом.

## Шаг 2. Ключи провайдеров и unified-ключ

Это делает пользователь сам в браузере — ты не регистрируешь аккаунты за него.

1. Открыть http://localhost:3001 (серверная установка требует email + пароль).
2. На странице **Keys** добавить ключи провайдеров. Актуальный список провайдеров
   и лимитов: https://freellmapi.co/models.html.
3. При желании переупорядочить **Fallback Chain**.
4. Скопировать **unified API key** (`freellmapi-…`) из шапки страницы Keys.

Никогда не проси вставить ключи провайдеров в чат и не пиши их в файлы
репозитория. Unified-ключ держи в переменной окружения:
```bash
export FREELLMAPI_API_KEY='freellmapi-...'
```

## Шаг 3. Подключить агента

Все команды — из npm-пакета `freellmapi` (`cli/README.md`), нужен Node.js ≥ 20.18.
Общие флаги: `--url` (**в коде CLI по умолчанию `http://localhost:3000`** —
`cli/src/index.ts`, `parseArgs`; README пишет 3001, поэтому всегда передавай
`--url` или `FREELLMAPI_URL` явно), `--api-key`,
`--profile NAME`, `--model ID`, `--dry-run`. Вместо флагов работают
`FREELLMAPI_URL` и `FREELLMAPI_API_KEY`.

### Claude Code

**Рекомендуемый путь — `launch`**: ничего не пишет на диск, подставляет
переменные только в дочерний процесс, удаляет из его окружения твои настоящие
`ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN` (`cli/src/index.ts`, `claudeLaunchEnv`).
```bash
npx freellmapi launch
```
Обычный `claude` при этом продолжает работать на подписке — удобно переключаться,
когда платный лимит кончился.

**Windows:** `launch` запускает `claude` через `spawn` без shell
(`cli/src/index.ts`, `runChild`), поэтому npm-обёртку `claude.cmd` он может не
найти. Для Windows в навыке есть готовый скрипт `scripts/claude-free.cmd`
(+ `claude-free.ps1`): двойной клик находит порт десктоп-приложения, берёт и
проверяет ключ из буфера обмена (трей → Copy Key), сохраняет его в
переменную пользователя `FREELLMAPI_API_KEY`, включает
`FREELLMAPI_CONTEXT_HANDOFF`, при необходимости ставит Claude Code через npm и
запускает `claude` с `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN` только для этого
окна. Модели задавать не нужно: шлюз по умолчанию отображает все `claude-*` на
`auto` (`server/src/routes/anthropic.ts`, `services/anthropic-map.ts`).

**Постоянная настройка — `setup-claude`.** Внимание: без `--profile` он
записывает в `~/.claude/settings.json` блок `env` с `ANTHROPIC_BASE_URL`,
`ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL` и `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL`
(`cli/src/tools.ts`, функция `claude`) — после этого **все** сессии Claude Code
пойдут через шлюз. Поэтому:
```bash
npx freellmapi setup-claude --profile free --dry-run   # сначала показать diff
npx freellmapi setup-claude --profile free             # пишет ~/.claude/profiles/free/settings.json
npx freellmapi launch --profile free                   # запуск с этим профилем
```
Перед изменением существующего файла генератор делает бэкап с меткой времени.
Для Claude Code базовый URL — **корень** (`http://localhost:3001`), без `/v1`.

### Codex CLI
```bash
npx freellmapi launch-codex                 # без записи ключа на диск
# или постоянно:
npx freellmapi setup-codex --dry-run
npx freellmapi setup-codex                  # блок в ~/.codex/config.toml, ключ НЕ пишется
export FREELLMAPI_API_KEY='freellmapi-...'  # нужен при каждом запуске codex
```
Codex ходит через `/v1/responses` (`docs/en/clients/01-agent-clients.md`).

### Gemini CLI (нативный протокол `/v1beta`)
```bash
export GOOGLE_GEMINI_BASE_URL=http://localhost:3001
export GEMINI_API_KEY="$FREELLMAPI_API_KEY"
gemini
```

### Остальные
`setup-aider`, `setup-cline`, `setup-continue`, `setup-opencode`, `setup-goose`,
`setup-qwen`, `setup-roo`, `setup-kilo`, `setup-crush`, `setup-dsh`, `setup-mimo`,
`setup-atomcode`, `setup-openclaw`, `setup-hermes`, `setup-cursor`,
`setup-generic`. Полный список: `npx freellmapi list`. Для них базовый URL
включает `/v1`.

## Шаг 4. Непрерывность контекста при смене модели

Как это устроено (по исходникам на коммите `eadbeb5`):

- **История не теряется сама по себе.** Claude Code в каждом запросе отправляет
  всю историю диалога, поэтому любая следующая модель получает тот же контекст.
  Реальные риски другие: у новой модели может не хватить окна контекста, она не
  знает, что продолжает чужую задачу, и может оказаться слабее.
- **Привязка сессии к модели — автоматически.** Для Claude Code шлюз берёт
  заголовок `X-Claude-Code-Session-Id` и держит сессию на одной модели 30 минут
  (`server/src/routes/anthropic.ts`, `server/src/routes/proxy.ts`,
  `STICKY_TTL_MS`). Настраивать ничего не нужно.
- **Слишком маленькое окно — модель пропускается.** Роутер отбрасывает модели,
  в чьё `context_window` не помещается запрос (`fitsContextWindow` в
  `server/src/services/router.ts`). Длинная сессия может остаться без кандидатов.

Что включить в `.env` шлюза (затем перезапуск):
```env
# системная записка новой модели «ты продолжаешь задачу», по умолчанию off
FREELLMAPI_CONTEXT_HANDOFF=on_model_switch
# сжатие запросов, чтобы длинная сессия влезала в меньшие окна, по умолчанию off
FREELLMAPI_COMPRESSION=standard
```
- Handoff: до 6000 символов сводки, хранится только в памяти 3 часа
  (`server/src/services/context-handoff.ts`; `docs/en/clients/01-agent-clients.md`,
  *Context Handoff*).
- Сжатие: режимы `lossless` / `standard` / `aggressive`; после сохранения в
  дашборде (**Settings → Prompt compression**) настройка дашборда важнее `.env`
  (`docs/en/compression/01-compression-pipeline.md`). `aggressive` сжимает старые
  реплики — выше риск потерять детали.

Что делать пользователю:
1. Добавить ключи провайдеров, у которых есть модели с **tool calling** и
   **большим окном контекста** — без инструментов Claude Code не работает, а с
   маленьким окном длинная сессия никуда не поместится. Смотреть на странице
   **Models** дашборда или https://freellmapi.co/models.html.
2. Не перезапускать шлюз посреди сессии: привязка сессий и handoff-записки
   живут только в памяти процесса.
3. В длинных сессиях вызывать `/compact` в Claude Code, чтобы история
   помещалась в окна бесплатных моделей.

Не обещай «бесшовное продолжение»: новая модель получит ту же историю, но может
быть слабее и вести себя иначе. Скрытое состояние прежнего провайдера (например,
его ход рассуждений) не переносится.

## Выбор модели

Поле `model` в запросе (`docs/en/api/01-rest-api.md`, *Routing strategies*):
`auto` (цепочка из дашборда), `auto:smart`, `auto:fast`, `auto:reliable`,
`auto:balanced`, `auto:<имя-профиля>`, либо конкретный id модели. Для агентов
кодинга разумно `auto:smart` или отдельный профиль-цепочка. Какая модель реально
ответила — в заголовке ответа `X-Routed-Via`.

## Диагностика

```bash
npx freellmapi doctor claude      # доходят ли запросы до шлюза (поддержаны claude и codex)
curl -fsS http://localhost:3001/livez
curl -fsS http://localhost:3001/v1/models -H "Authorization: Bearer $FREELLMAPI_API_KEY"
docker compose logs -f freellmapi
```
Частые причины:
- Claude Code настроен на `.../v1` — нужен корень без `/v1`.
- В Docker провайдеры недоступны через прокси на хосте: используй
  `PROXY_URL=socks5h://host.docker.internal:7890` (`docs/en/install/01-install.md`).
- Все ключи в кулдауне / дневные лимиты исчерпаны — смотреть страницу Models и
  Analytics в дашборде.

## Откат

- `launch`/`launch-codex` — откатывать нечего.
- `setup-*` — восстановить бэкап `<файл>.backup-<время>` (`cli/src/config-files.ts`), или удалить
  добавленный блок (`env` в `settings.json` / блок `# freellmapi:start … end` в
  `~/.codex/config.toml`).
- Удаление шлюза: `docker compose down -v` и каталог данных (см. README → FAQ).

## Правила для Claude при выполнении навыка

1. Сначала покажи раздел «Что это и чего ожидать» и получи согласие.
2. Не запускай `curl … | bash` и не изменяй `~/.claude`/`~/.codex` без явного
   разрешения; для генераторов всегда начинай с `--dry-run`.
3. Предпочитай `launch` постоянной перезаписи глобальных настроек.
4. Не выдумывай провайдеров, лимиты и id моделей — бери их из `/v1/models`
   работающего шлюза или с https://freellmapi.co/models.html.

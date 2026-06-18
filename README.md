# Media Service

- Принимает загрузки через presigned PUT в MinIO/S3
- Прогоняет файл через pipeline валидации (`pending` -> `scanning` ->
  `ready`/`rejected`) фоновыми Oban-воркерами: сверяет фактический размер
  и MIME-тип с заявленными при инициировании загрузки
- Выдаёт presigned GET-ссылки на скачивание (TTL 7 дней)
- S2S-аутентификация между сервисами по заголовку `X-Service-Token`
- Предоставляет compat-эндпоинты (`/avatar`, `/attached_files`) для
  profile_service и response_service

## Запуск

- Локально: `mix setup && mix phx.server` (порт 8000)
- В Docker: сервис `media-service` в `infra_faberge/docker-compose.yaml`

## API

- `GET /api/v1/health`, `GET /api/v1/health/ready` - healthcheck
- `POST /api/v1/me/uploads` - инициировать загрузку
- `POST /api/v1/me/uploads/:id/complete` - подтвердить загрузку
- `GET /api/v1/me/assets` - список своих файлов
- `GET /api/v1/assets/:id` - метаданные + download-ссылка
- `DELETE /api/v1/assets/:id` - удалить файл

## TODO

### scanning (не антивирус)
`lib/media_service/pipeline/workers/scan_job.ex`

«scanning» здесь - проверка целостности (размер + MIME), а не антивирус;
Реальное антивирусное сканирование (например, ClamAV) можно добавить
в `ScanJob` как отдельный шаг pipeline

### jwks-verification
`lib/media_service_web/plugs/user_context.ex`

JWT декодируется без проверки подписи: доверяем, что gateway уже проверил.
При обращении в обход gateway токен можно подделать. Нужна проверка подписи
через JWKS Keycloak (`Joken` + кэш ключей)

### remove-compat-shim
`lib/media_service_web/controllers/api/v1/compat_controller.ex`

Контроллер-прослойка для старых путей (`/avatar`, `/attached_files`).
Удалить целиком, когда profile_service и response_service перейдут на
канонический API (`/api/v1/uploads` + `/api/v1/assets/:id`)

### owner-id
`lib/media_service_web/controllers/api/v1/compat_controller.ex`

response_service должен слать `owner_id` (UUID ответа) в payload загрузки,
иначе непонятно, кому принадлежит файл

### streaming-upload
`lib/media_service_web/controllers/api/v1/compat_controller.ex`

Загрузка читает весь файл в память. Для больших файлов заменить на
chunked-стриминг через Req

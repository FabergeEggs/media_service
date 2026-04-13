# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :media_service, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10],
  repo: MediaService.Repo

config :media_service,
  ecto_repos: [MediaService.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

# Storage adapter — overridden in tests with a Mox stub.
config :media_service, :storage_adapter, MediaService.Storage.S3

# Default MinIO settings — per-env values live in runtime.exs / dev.exs / test.exs.
config :media_service, MediaService.Storage.S3,
  bucket: "media",
  access_key_id: "minioadmin",
  secret_access_key: "change_me_password",
  region: "us-east-1",
  scheme: "http://",
  host: "localhost",
  port: 9000

# Shared-secret tokens for S2S. Per-env overrides in runtime.exs.
config :media_service, :service_tokens, []

# Ex-AWS uses these regardless of our S3 overrides.
config :ex_aws,
  json_codec: Jason,
  http_client: ExAws.Request.Hackney

# Configure the endpoint
config :media_service, MediaServiceWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: MediaServiceWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MediaService.PubSub,
  live_view: [signing_salt: "ZGwwl/CF"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

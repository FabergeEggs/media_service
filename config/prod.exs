import Config

# force_ssl is intentionally disabled for Docker / internal service-to-service
# communication. In this architecture, TLS is terminated at the API gateway /
# reverse proxy — containers talk plain HTTP over the internal Docker network.
# Enabling force_ssl here causes 307 redirects from the gateway (Host: media-service)
# to https://localhost which is unreachable by clients.
#
# To re-enable for a bare-metal prod deployment behind a load balancer that sets
# X-Forwarded-Proto, uncomment and configure:
#
# config :media_service, MediaServiceWeb.Endpoint,
#   force_ssl: [rewrite_on: [:x_forwarded_proto]]

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.

FROM hexpm/elixir:1.20.0-rc.4-erlang-29.0-rc3-debian-bookworm-20260406-slim AS builder
ENV MIX_ENV=prod \
    LANG=C.UTF-8

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential \
      git \
      ca-certificates \
      libmagic-dev \
      libvips-dev \
      pkg-config \
 && rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force \
 && mix local.rebar --force

WORKDIR /app

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only $MIX_ENV \
 && mix deps.compile

COPY priv priv
COPY lib lib

RUN mix compile \
 && mix release

# ---- runtime ----
FROM debian:bookworm-20260406-slim  AS runtime

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PHX_SERVER=true \
    PORT=8000

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      libstdc++6 \
      libncurses6 \
      locales \
      openssl \
      libmagic1 \
      libvips42 \
      ffmpeg \
      imagemagick \
      curl \
 && rm -rf /var/lib/apt/lists/* \
 && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
 && locale-gen

WORKDIR /app

RUN groupadd --system app \
 && useradd --system --gid app --home /app --shell /usr/sbin/nologin app \
 && chown app:app /app

USER app

COPY --from=builder --chown=app:app /app/_build/prod/rel/media_service ./

# File permissions on overlay scripts can be lost across multi-arch builds.
# Re-assert +x so `migrate`, `server`, `entrypoint` stay runnable in the image.
USER root
RUN chmod +x /app/bin/migrate /app/bin/server /app/bin/entrypoint
USER app

EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD curl -fsS http://localhost:${PORT}/health || exit 1

# entrypoint runs migrations, then `exec`s into the Phoenix server so the BEAM
# VM becomes PID 1 and receives SIGTERM from the container runtime directly.
ENTRYPOINT ["/app/bin/entrypoint"]

defmodule MediaService.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MediaServiceWeb.Telemetry,
      MediaService.Repo,
      {DNSCluster, query: Application.get_env(:media_service, :dns_cluster_query) || :ignore},
      {Oban, Application.fetch_env!(:media_service, Oban)},
      {Phoenix.PubSub, name: MediaService.PubSub},
      MediaServiceWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MediaService.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MediaServiceWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

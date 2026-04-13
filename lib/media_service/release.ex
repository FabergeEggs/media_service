defmodule MediaService.Release do
  @moduledoc """
  Release helpers — run from the compiled release without Mix.

      bin/media_service eval "MediaService.Release.migrate()"
      bin/media_service eval "MediaService.Release.rollback(MediaService.Repo, 20260416090000)"
  """

  @app :media_service

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end

defmodule MediaService.Pipeline.Workers.ScanJob do
  use Oban.Worker, queue: :default, max_attempts: 5

  require Logger

  alias MediaService.Assets
  alias MediaService.Media.Asset
  alias MediaService.Media.Status
  alias MediaService.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"asset_id" => asset_id}}) do
    with {:ok, %Asset{} = asset} <- Assets.fetch(asset_id),
         {:ok, status} <- Status.to_atom(asset.status),
         :ok <- ensure_scanning(status),
         {:ok, head} <- storage().head_object(asset.object_key) do
      classify(asset, head)
    end
  end

  defp ensure_scanning(:scanning), do: :ok
  defp ensure_scanning(:ready), do: {:ok, :already_done}
  defp ensure_scanning(:rejected), do: {:ok, :already_done}
  defp ensure_scanning(:deleted), do: {:ok, :already_done}
  defp ensure_scanning(:pending), do: {:error, :not_confirmed}

  defp classify(%Asset{size_bytes: declared} = asset, %{content_length: actual})
       when is_integer(actual) and actual != declared do
    Logger.warning("scan: size mismatch asset=#{asset.id} declared=#{declared} actual=#{actual}")
    reject(asset, "too_large")
  end

  defp classify(%Asset{declared_mime: declared} = asset, %{content_type: actual})
       when is_binary(declared) and is_binary(actual) and declared != actual do
    Logger.warning("scan: mime mismatch asset=#{asset.id} declared=#{declared} actual=#{actual}")
    reject(asset, "mime_mismatch")
  end

  defp classify(%Asset{} = asset, %{content_type: detected}) do
    accept(asset, detected)
  end

  defp accept(%Asset{} = asset, detected_mime) do
    asset
    |> Asset.status_changeset(:ready,
      timestamps: [scanned_at: DateTime.utc_now()],
      fields: [detected_mime: detected_mime]
    )
    |> Repo.update()
    |> case do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp reject(%Asset{} = asset, reason) do
    asset
    |> Asset.status_changeset(:rejected,
      timestamps: [scanned_at: DateTime.utc_now()],
      fields: [rejection_reason: reason]
    )
    |> Repo.update()
    |> case do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp storage do
    Application.get_env(:media_service, :storage_adapter, MediaService.Storage.S3)
  end
end

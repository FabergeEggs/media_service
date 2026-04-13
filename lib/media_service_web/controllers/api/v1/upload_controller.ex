defmodule MediaServiceWeb.API.V1.UploadController do
  @moduledoc """
  S2S endpoints that orchestrate an upload:

      POST /api/v1/uploads             — reserve an asset + presigned PUT URL
      POST /api/v1/uploads/:id/complete — confirm bytes landed in MinIO
  """

  use MediaServiceWeb, :controller

  alias MediaService.Assets
  alias MediaServiceWeb.API.V1.AssetJSON

  action_fallback MediaServiceWeb.API.V1.FallbackController

  @required_params ~w(owner_kind owner_id filename content_type size_bytes)

  def create(conn, params) do
    with :ok <- ensure_required(params),
         {:ok, attrs} <- build_attrs(conn, params),
         {:ok, result} <- Assets.create_upload(attrs) do
      conn
      |> put_status(:created)
      |> json(AssetJSON.upload_created(result))
    end
  end

  def complete(conn, %{"id" => id}) do
    with {:ok, asset} <- Assets.confirm_upload(id) do
      conn
      |> put_status(:ok)
      |> json(%{asset: AssetJSON.base(asset)})
    end
  end

  defp ensure_required(params) do
    missing = Enum.reject(@required_params, &Map.has_key?(params, &1))

    case missing do
      [] -> :ok
      missing -> {:error, {:missing_params, missing}}
    end
  end

  defp build_attrs(conn, params) do
    caller = conn.assigns[:caller_service] || "unknown"

    with {:ok, size} <- coerce_size(params["size_bytes"]) do
      {:ok,
       %{
         owner_kind: to_string(params["owner_kind"]),
         owner_id: to_string(params["owner_id"]),
         filename: to_string(params["filename"]),
         content_type: to_string(params["content_type"]),
         size_bytes: size,
         visibility: Map.get(params, "visibility", "owner_only"),
         metadata: Map.get(params, "metadata", %{}),
         created_by_service: caller
       }}
    end
  end

  defp coerce_size(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp coerce_size(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_size}
    end
  end

  defp coerce_size(_), do: {:error, :invalid_size}
end

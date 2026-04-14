defmodule MediaService.Assets do
  import Ecto.Query, warn: false

  alias MediaService.Media.Asset
  alias MediaService.Media.Owner
  alias MediaService.Media.Status
  alias MediaService.Repo
  alias MediaService.Storage.Keys

  @type create_attrs :: %{
          required(:owner_kind) => String.t(),
          required(:owner_id) => String.t(),
          required(:filename) => String.t(),
          required(:content_type) => String.t(),
          required(:size_bytes) => pos_integer(),
          optional(:visibility) => String.t(),
          optional(:metadata) => map(),
          required(:created_by_service) => String.t()
        }

  @spec create_upload(create_attrs()) ::
          {:ok, %{asset: Asset.t(), upload: map()}} | {:error, term()}
  def create_upload(attrs) do
    asset_id = Ecto.UUID.generate()
    bucket = storage().bucket()

    object_key =
      Keys.object_key(attrs.owner_kind, attrs.owner_id, asset_id, attrs.filename)

    asset_attrs = %{
      owner_kind: attrs.owner_kind,
      owner_id: attrs.owner_id,
      created_by_service: Map.get(attrs, :created_by_service, "unknown"),
      bucket: bucket,
      object_key: object_key,
      original_filename: attrs.filename,
      declared_mime: attrs.content_type,
      size_bytes: attrs.size_bytes,
      visibility: Map.get(attrs, :visibility, "owner_only"),
      metadata: Map.get(attrs, :metadata, %{})
    }

    with {:ok, changeset} <- build_changeset(asset_attrs),
         {:ok, asset} <- Repo.insert(Ecto.Changeset.put_change(changeset, :id, asset_id)),
         {:ok, presign} <-
           storage().presign_put(object_key,
             content_type: attrs.content_type,
             content_length: attrs.size_bytes
           ) do
      {:ok, %{asset: asset, upload: presign}}
    end
  end

  @spec confirm_upload(String.t()) :: {:ok, Asset.t()} | {:error, term()}
  def confirm_upload(asset_id) when is_binary(asset_id) do
    with {:ok, asset} <- fetch(asset_id),
         :ok <- ensure_status(asset, :pending),
         {:ok, head} <- storage().head_object(asset.object_key),
         :ok <- ensure_size_matches(asset, head) do
      transition!(asset, :scanning)
    end
  end

  @spec fetch_with_download_url(String.t()) ::
          {:ok, %{asset: Asset.t(), download: map() | nil}} | {:error, term()}
  def fetch_with_download_url(asset_id) when is_binary(asset_id) do
    with {:ok, asset} <- fetch(asset_id) do
      case Status.to_atom(asset.status) do
        {:ok, :ready} ->
          case storage().presign_get(asset.object_key, []) do
            {:ok, presign} -> {:ok, %{asset: asset, download: presign}}
            {:error, reason} -> {:error, reason}
          end

        _ ->
          {:ok, %{asset: asset, download: nil}}
      end
    end
  end

  @spec list_for_owner(String.t(), String.t()) :: [Asset.t()]
  def list_for_owner(owner_kind, owner_id)
      when is_binary(owner_kind) and is_binary(owner_id) do
    from(a in Asset,
      where:
        a.owner_kind == ^owner_kind and
          a.owner_id == ^owner_id and
          a.status == "ready",
      order_by: [desc: a.inserted_at]
    )
    |> Repo.all()
  end

  @spec soft_delete(String.t()) :: {:ok, Asset.t()} | {:error, term()}
  def soft_delete(asset_id) when is_binary(asset_id) do
    with {:ok, asset} <- fetch(asset_id) do
      case Status.to_atom(asset.status) do
        {:ok, :deleted} ->
          {:ok, asset}

        {:ok, _} ->
          _ = storage().delete_object(asset.object_key)
          transition!(asset, :deleted, timestamps: [deleted_at: DateTime.utc_now()])

        :error ->
          {:error, :invalid_status}
      end
    end
  end

  @spec fetch(String.t()) :: {:ok, Asset.t()} | {:error, :not_found}
  def fetch(asset_id) when is_binary(asset_id) do
    case Repo.get(Asset, asset_id) do
      nil -> {:error, :not_found}
      asset -> {:ok, asset}
    end
  end

  defp build_changeset(attrs) do
    changeset = Asset.create_changeset(attrs)
    if changeset.valid?, do: {:ok, changeset}, else: {:error, changeset}
  end

  defp ensure_status(%Asset{} = asset, expected) do
    case Status.to_atom(asset.status) do
      {:ok, ^expected} -> :ok
      {:ok, other} -> {:error, {:invalid_status, other}}
      :error -> {:error, :invalid_status}
    end
  end

  defp ensure_size_matches(%Asset{size_bytes: n}, %{content_length: n}) when is_integer(n),
    do: :ok

  defp ensure_size_matches(%Asset{size_bytes: declared}, %{content_length: actual}) do
    {:error, {:size_mismatch, %{declared: declared, actual: actual}}}
  end

  defp transition!(%Asset{} = asset, new_status, opts \\ []) do
    asset
    |> Asset.status_changeset(new_status, opts)
    |> Repo.update()
  end

  defp storage do
    Application.get_env(:media_service, :storage_adapter, MediaService.Storage.S3)
  end

  if Code.ensure_loaded?(Owner), do: _ = Owner
end

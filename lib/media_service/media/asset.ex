defmodule MediaService.Media.Asset do
  use Ecto.Schema

  import Ecto.Changeset

  alias MediaService.Media.Owner
  alias MediaService.Media.Status

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          owner_kind: String.t() | nil,
          owner_id: String.t() | nil,
          created_by_service: String.t() | nil,
          bucket: String.t() | nil,
          object_key: String.t() | nil,
          original_filename: String.t() | nil,
          declared_mime: String.t() | nil,
          size_bytes: non_neg_integer() | nil,
          status: String.t() | nil,
          visibility: String.t() | nil,
          metadata: map(),
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "media_assets" do
    field :owner_kind, :string
    field :owner_id, :binary_id
    field :created_by_service, :string

    field :bucket, :string
    field :object_key, :string
    field :original_filename, :string

    field :declared_mime, :string
    field :detected_mime, :string
    field :size_bytes, :integer
    field :checksum_sha256, :string

    field :width, :integer
    field :height, :integer
    field :duration_ms, :integer

    field :status, :string, default: "pending"
    field :visibility, :string, default: "owner_only"
    field :rejection_reason, :string

    field :metadata, :map, default: %{}

    field :scanned_at, :utc_datetime_usec
    field :processed_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    timestamps()
  end

  @create_fields ~w(
    owner_kind owner_id created_by_service bucket object_key
    original_filename declared_mime size_bytes visibility metadata
  )a

  @required_on_create ~w(
    owner_kind owner_id created_by_service bucket object_key size_bytes
  )a

  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @create_fields)
    |> validate_required(@required_on_create)
    |> validate_inclusion(:owner_kind, Owner.allowed_kinds())
    |> validate_inclusion(:visibility, ~w(public owner_only))
    |> validate_number(:size_bytes, greater_than: 0)
    |> validate_length(:object_key, max: 512)
    |> validate_length(:original_filename, max: 512)
    |> validate_length(:declared_mime, max: 128)
    |> put_change(:status, "pending")
  end

  # Fields the scan/process pipeline may update alongside a status transition.
  @pipeline_fields ~w(
    detected_mime checksum_sha256 rejection_reason
    width height duration_ms metadata
    scanned_at processed_at deleted_at
  )a

  @rejection_reasons ~w(infected mime_mismatch too_large decode_failed scan_failed svg_not_allowed)

  @spec status_changeset(t(), Status.t(), keyword()) :: Ecto.Changeset.t()
  def status_changeset(%__MODULE__{} = asset, new_status, opts \\ [])
      when is_atom(new_status) do
    timestamps = Keyword.get(opts, :timestamps, [])
    fields = Keyword.get(opts, :fields, [])

    from_atom =
      case Status.to_atom(asset.status) do
        {:ok, a} -> a
        :error -> nil
      end

    asset
    |> change(%{status: Atom.to_string(new_status)})
    |> apply_pairs(timestamps)
    |> apply_pairs(fields)
    |> validate_inclusion(:rejection_reason, @rejection_reasons)
    |> validate_transition(from_atom, new_status)
  end

  def rejection_reasons, do: @rejection_reasons

  defp apply_pairs(changeset, pairs) do
    pairs
    |> Enum.into([])
    |> Enum.reduce(changeset, fn {field, value}, acc ->
      if field in @pipeline_fields do
        put_change(acc, field, value)
      else
        add_error(acc, field, "not writable via status_changeset")
      end
    end)
  end

  defp validate_transition(changeset, from, to) do
    cond do
      is_nil(from) ->
        add_error(changeset, :status, "current status is not a known value")

      Status.can_transition?(from, to) ->
        changeset

      true ->
        add_error(changeset, :status, "illegal transition from #{from} to #{to}")
    end
  end
end

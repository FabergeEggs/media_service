defmodule MediaService.Repo.Migrations.CreateMediaAssets do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"

    create table(:media_assets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :owner_kind, :string, null: false, size: 32
      add :owner_id, :binary_id, null: false
      add :created_by_service, :string, null: false, size: 64

      add :bucket, :string, null: false, size: 128
      add :object_key, :string, null: false, size: 512
      add :original_filename, :string, size: 512

      add :declared_mime, :string, size: 128
      add :detected_mime, :string, size: 128
      add :size_bytes, :bigint, null: false
      add :checksum_sha256, :string, size: 64

      add :width, :integer
      add :height, :integer
      add :duration_ms, :integer

      add :status, :string, null: false, default: "pending", size: 32
      add :visibility, :string, null: false, default: "owner_only", size: 32
      add :rejection_reason, :string, size: 64

      add :metadata, :map, null: false, default: %{}

      add :scanned_at, :utc_datetime_usec
      add :processed_at, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:media_assets, [:owner_kind, :owner_id])
    create index(:media_assets, [:status])
    create index(:media_assets, [:checksum_sha256])
    create index(:media_assets, [:created_by_service])
  end
end

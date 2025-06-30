defmodule VaultLite.Repo.Migrations.CreateSecrets do
  use Ecto.Migration

  def change do
    create table(:secrets) do
      add :key, :string, null: false
      # Encrypted secret data
      add :value, :binary, null: false
      add :version, :integer, null: false, default: 1
      # Additional metadata (created_by, etc.)
      add :metadata, :map, default: %{}
      # For soft deletion
      add :deleted_at, :utc_datetime

      timestamps()
    end

    # Create indexes for efficient queries
    # Ensure unique key-version combinations
    create unique_index(:secrets, [:key, :version])
    # Fast lookups by key
    create index(:secrets, [:key])
    # For time-based queries
    create index(:secrets, [:inserted_at])
    # For filtering deleted secrets
    create index(:secrets, [:deleted_at])
  end
end

defmodule VaultLite.Repo.Migrations.CreateSecretShares do
  use Ecto.Migration

  def change do
    create table(:secret_shares) do
      add :secret_key, :string, null: false
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      add :shared_with_id, references(:users, on_delete: :delete_all), null: false
      # "read_only" or "editable"
      add :permission_level, :string, null: false
      add :shared_at, :utc_datetime, null: false
      # Optional expiration
      add :expires_at, :utc_datetime, null: true
      add :active, :boolean, default: true, null: false

      timestamps()
    end

    # Indexes for efficient querying
    create unique_index(:secret_shares, [:secret_key, :shared_with_id],
             name: :secret_shares_unique_share
           )

    create index(:secret_shares, [:owner_id])
    create index(:secret_shares, [:shared_with_id])
    create index(:secret_shares, [:secret_key])
    create index(:secret_shares, [:permission_level])
    create index(:secret_shares, [:active])
  end
end

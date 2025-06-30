defmodule VaultLite.Repo.Migrations.AddSecretTypeAndOwnerToSecrets do
  use Ecto.Migration

  def change do
    alter table(:secrets) do
      # Add secret type field with default as role_based for existing secrets
      add :secret_type, :string, null: false, default: "role_based"
      # Add owner_id for personal secrets (nullable since role_based secrets don't need owner)
      add :owner_id, references(:users, on_delete: :delete_all), null: true
    end

    # Create index for efficient querying by secret type
    create index(:secrets, [:secret_type])
    # Create index for owner_id lookups for personal secrets
    create index(:secrets, [:owner_id])
    # Create composite index for efficient personal secrets queries
    create index(:secrets, [:owner_id, :secret_type])
  end
end

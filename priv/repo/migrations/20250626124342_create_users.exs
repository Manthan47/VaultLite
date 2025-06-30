defmodule VaultLite.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string, null: false
      add :email, :string, null: false
      add :password_hash, :string, null: false
      # For user activation/deactivation
      add :active, :boolean, default: true

      timestamps()
    end

    # Create indexes for efficient queries and uniqueness
    create unique_index(:users, [:username])
    create unique_index(:users, [:email])
    create index(:users, [:active])
  end
end

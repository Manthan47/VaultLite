defmodule VaultLite.Repo.Migrations.CreateRoles do
  use Ecto.Migration

  def change do
    create table(:roles) do
      add :name, :string, null: false
      # Array of permissions like ["read", "write"]
      add :permissions, {:array, :string}, null: false, default: []
      # Will add foreign key constraint later
      add :user_id, :integer, null: true

      timestamps()
    end

    # Create indexes for efficient queries
    create index(:roles, [:name])
    create index(:roles, [:user_id])
    # Unique role per user
    create unique_index(:roles, [:name, :user_id], where: "user_id IS NOT NULL")
  end
end

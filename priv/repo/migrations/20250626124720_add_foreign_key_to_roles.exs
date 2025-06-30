defmodule VaultLite.Repo.Migrations.AddForeignKeyToRoles do
  use Ecto.Migration

  def change do
    # Add foreign key constraint from roles.user_id to users.id
    alter table(:roles) do
      modify :user_id, references(:users, on_delete: :delete_all), from: :integer
    end
  end
end

defmodule VaultLite.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs) do
      # Reference to user performing the action
      add :user_id, :integer, null: true
      # Action performed (create, read, update, delete)
      add :action, :string, null: false
      # The key of the secret that was accessed
      add :secret_key, :string, null: false
      # When the action occurred
      add :timestamp, :utc_datetime, null: false, default: fragment("NOW()")
      # Additional context (IP address, user agent, etc.)
      add :metadata, :map, default: %{}

      timestamps()
    end

    # Create indexes for efficient queries
    create index(:audit_logs, [:user_id])
    create index(:audit_logs, [:secret_key])
    create index(:audit_logs, [:action])
    create index(:audit_logs, [:timestamp])
    # For time-based queries
    create index(:audit_logs, [:inserted_at])
  end
end

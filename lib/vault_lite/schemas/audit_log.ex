defmodule VaultLite.Schema.AuditLog do
  @moduledoc """
  Audit log schema and functions for tracking user actions and security events.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  @derive {Jason.Encoder,
           only: [
             :id,
             :user_id,
             :action,
             :secret_key,
             :timestamp,
             :metadata,
             :inserted_at,
             :updated_at
           ]}

  schema "audit_logs" do
    # Reference to user performing the action
    field :user_id, :integer
    # Action performed (create, read, update, delete)
    field :action, :string
    # The key of the secret that was accessed
    field :secret_key, :string
    # When the action occurred
    field :timestamp, :utc_datetime
    # Additional context (IP address, user agent, etc.)
    field :metadata, :map, default: %{}

    timestamps()
  end

  @doc """
  Changeset for creating a new audit log entry.
  """
  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [:user_id, :action, :secret_key, :timestamp, :metadata])
    |> validate_required([:action, :secret_key])
    |> VaultLite.Security.InputValidator.validate_action(:action)
    |> VaultLite.Security.InputValidator.validate_secret_key(:secret_key)
    |> VaultLite.Security.InputValidator.validate_metadata(:metadata)
    |> put_timestamp()
  end

  defp put_timestamp(changeset) do
    case get_field(changeset, :timestamp) do
      nil -> put_change(changeset, :timestamp, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end

  @doc """
  Create an audit log entry for a secret operation.
  """
  def log_action(action, secret_key, user_id \\ nil, metadata \\ %{}) do
    attrs = %{
      action: action,
      secret_key: secret_key,
      user_id: user_id,
      metadata: metadata
    }

    %VaultLite.Schema.AuditLog{}
    |> changeset(attrs)
  end

  @doc """
  Query helper to get logs for a specific user.
  """
  def for_user(query, user_id) do
    from a in query, where: a.user_id == ^user_id
  end

  @doc """
  Query helper to get logs for a specific secret key.
  """
  def for_secret(query, secret_key) do
    from a in query, where: a.secret_key == ^secret_key
  end

  @doc """
  Query helper to get logs for a specific action.
  """
  def for_action(query, action) do
    from a in query, where: a.action == ^action
  end

  @doc """
  Query helper to get logs within a time range.
  """
  def between_dates(query, start_date, end_date) do
    from a in query,
      where: a.timestamp >= ^start_date and a.timestamp <= ^end_date
  end

  @doc """
  Query helper to get recent logs (ordered by timestamp desc).
  """
  def recent_first(query) do
    from a in query, order_by: [desc: a.timestamp]
  end

  @doc """
  Query helper to get logs with metadata containing specific key-value pairs.
  """
  def with_metadata(query, key, value) do
    from a in query, where: fragment("?->>? = ?", a.metadata, ^key, ^value)
  end
end

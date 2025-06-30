defmodule VaultLite.User do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "users" do
    field :username, :string
    field :email, :string
    field :password_hash, :string
    # Virtual field for password input
    field :password, :string, virtual: true
    field :active, :boolean, default: true

    has_many :roles, VaultLite.Role

    timestamps()
  end

  @doc """
  Changeset for creating a new user.
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password, :active])
    |> validate_required([:username, :email, :password])
    |> VaultLite.Security.InputValidator.validate_username(:username)
    |> VaultLite.Security.InputValidator.validate_email(:email)
    |> VaultLite.Security.InputValidator.validate_password(:password)
    |> unique_constraint(:username)
    |> unique_constraint(:email)
    |> hash_password()
  end

  @doc """
  Changeset for updating user (without password).
  """
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :active])
    |> validate_required([:username, :email])
    |> VaultLite.Security.InputValidator.validate_username(:username)
    |> VaultLite.Security.InputValidator.validate_email(:email)
    |> unique_constraint(:username)
    |> unique_constraint(:email)
  end

  @doc """
  Changeset for updating password.
  """
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> VaultLite.Security.InputValidator.validate_password(:password)
    |> hash_password()
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    change(changeset, password_hash: Bcrypt.hash_pwd_salt(password))
  end

  defp hash_password(changeset), do: changeset

  @doc """
  Verify password against hash.
  """
  def verify_password(%VaultLite.User{} = user, password) do
    Bcrypt.verify_pass(password, user.password_hash)
  end

  @doc """
  Query helper to get active users only.
  """
  def active_users(query) do
    from u in query, where: u.active == true
  end
end

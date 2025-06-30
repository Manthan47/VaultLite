defmodule VaultLite.Repo do
  use Ecto.Repo,
    otp_app: :vault_lite,
    adapter: Ecto.Adapters.Postgres
end

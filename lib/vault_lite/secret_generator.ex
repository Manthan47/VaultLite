defmodule VaultLite.SecretGenerator do
  @moduledoc """
  Utility module for generating secure secrets and passwords.

  Provides various methods to generate cryptographically secure random secrets
  suitable for different use cases like API keys, passwords, tokens, etc.
  """

  @charset_no_symbols "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  @charset_with_symbols "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+-=[]{}|;:,.<>?"

  @doc """
  Generates a secure random secret with the specified type and length.

  ## Options
  - `:type` - The type of secret to generate (:password, :api_key, :hex, :base64, :alphanumeric)
  - `:length` - The length of the generated secret (default depends on type)
  - `:include_symbols` - Whether to include symbols in password generation (default: true)

  ## Examples
      iex> VaultLite.SecretGenerator.generate_secret(:password, 16)
      {:ok, "A$bC9#xY2@mN7*pQ"}

      iex> VaultLite.SecretGenerator.generate_secret(:api_key, 32)
      {:ok, "vl_1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p"}

      iex> VaultLite.SecretGenerator.generate_secret(:hex, 16)
      {:ok, "3f7a8b9c1d2e4f5g"}
  """
  def generate_secret(type \\ :password, length \\ nil, opts \\ [])

  def generate_secret(:password, length, opts) do
    length = length || 16
    include_symbols = Keyword.get(opts, :include_symbols, true)

    charset =
      if include_symbols do
        @charset_with_symbols
      else
        @charset_no_symbols
      end

    secret = generate_from_charset(charset, length)
    {:ok, secret}
  end

  def generate_secret(:api_key, length, _opts) do
    length = length || 32
    # Generate hex string and prefix with 'vl_' for VaultLite
    hex_part = :crypto.strong_rand_bytes(div(length - 3, 2)) |> Base.encode16(case: :lower)
    api_key = "vl_" <> String.slice(hex_part, 0, length - 3)
    {:ok, api_key}
  end

  def generate_secret(:hex, length, _opts) do
    length = length || 32
    # Ensure even length for proper hex encoding
    byte_length = div(length + 1, 2)

    hex =
      :crypto.strong_rand_bytes(byte_length)
      |> Base.encode16(case: :lower)
      |> String.slice(0, length)

    {:ok, hex}
  end

  def generate_secret(:base64, length, _opts) do
    # Base64 encoding produces ~4/3 the input length
    byte_length = div(length * 3, 4)

    base64 =
      :crypto.strong_rand_bytes(byte_length)
      |> Base.encode64()
      |> String.slice(0, length)

    {:ok, base64}
  end

  def generate_secret(:alphanumeric, length, _opts) do
    length = length || 16
    charset = @charset_no_symbols
    secret = generate_from_charset(charset, length)
    {:ok, secret}
  end

  def generate_secret(:uuid, _length, _opts) do
    uuid = Ecto.UUID.generate()
    {:ok, uuid}
  end

  def generate_secret(type, _length, _opts) do
    {:error, "Unknown secret type: #{inspect(type)}"}
  end

  # Generates a secure secret from a given character set.
  defp generate_from_charset(charset, length) do
    charset_size = String.length(charset)

    1..length
    |> Enum.map(fn _ ->
      index = :crypto.strong_rand_bytes(1) |> :binary.first() |> rem(charset_size)
      String.at(charset, index)
    end)
    |> Enum.join()
  end

  @doc """
  Returns available secret types with their descriptions.
  """
  def available_types do
    [
      {:password, "Strong password with letters, numbers, and symbols"},
      {:alphanumeric, "Letters and numbers only"},
      {:api_key, "API key format (vl_xxxxx)"},
      {:hex, "Hexadecimal string"},
      {:base64, "Base64 encoded string"},
      {:uuid, "UUID v4 format"}
    ]
  end

  @doc """
  Returns default length for each secret type.
  """
  def default_length(type) do
    case type do
      :password -> 16
      :alphanumeric -> 16
      :api_key -> 32
      :hex -> 32
      :base64 -> 24
      :uuid -> 36
      _ -> 16
    end
  end

  @doc """
  Validates if the given length is appropriate for the secret type.
  """
  def valid_length?(type, length) do
    case type do
      :password -> length >= 8 && length <= 128
      :alphanumeric -> length >= 4 && length <= 128
      :api_key -> length >= 16 && length <= 64
      :hex -> length >= 8 && length <= 128
      :base64 -> length >= 8 && length <= 128
      :uuid -> length == 36
      _ -> false
    end
  end
end

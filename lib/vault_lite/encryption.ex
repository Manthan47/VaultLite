defmodule VaultLite.Encryption do
  @moduledoc """
  Handles encryption and decryption of secret values using AES-256-GCM.

  This module provides secure encryption with the following features:
  - AES-256-GCM algorithm for authenticated encryption
  - Random nonce generation for each encryption
  - Environment-based key management
  - Comprehensive error handling
  """

  @doc """
  Encrypts a plaintext value using AES-256-GCM.

  Returns a binary containing: nonce (12 bytes) + auth_tag (16 bytes) + ciphertext

  ## Examples
      iex> encrypt("secret_value")
      {:ok, <<encrypted_binary>>}

      iex> encrypt("secret_value")
      {:error, :encryption_key_not_configured}
  """
  def encrypt(plaintext) when is_binary(plaintext) do
    case get_encryption_key() do
      nil ->
        {:error, :encryption_key_not_configured}

      key ->
        try do
          # Generate a cryptographically secure random nonce
          nonce = :crypto.strong_rand_bytes(12)
          # Additional authenticated data (empty for simplicity)
          aad = ""

          # Perform AES-256-GCM encryption
          {ciphertext, auth_tag} =
            :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, plaintext, aad, true)

          # Combine components for storage: nonce + auth_tag + ciphertext
          encrypted_data = nonce <> auth_tag <> ciphertext
          {:ok, encrypted_data}
        rescue
          error -> {:error, {:encryption_failed, error}}
        end
    end
  end

  @doc """
  Decrypts a value that was encrypted with encrypt/1.

  Expects a binary containing: nonce (12 bytes) + auth_tag (16 bytes) + ciphertext

  ## Examples
      iex> decrypt(encrypted_binary)
      {:ok, "secret_value"}

      iex> decrypt(invalid_binary)
      {:error, :decryption_failed}
  """
  def decrypt(encrypted_data) when is_binary(encrypted_data) do
    case get_encryption_key() do
      nil ->
        {:error, :encryption_key_not_configured}

      key ->
        try do
          # Extract components from encrypted data
          case encrypted_data do
            <<nonce::binary-12, auth_tag::binary-16, ciphertext::binary>> ->
              aad = ""

              # Perform AES-256-GCM decryption with authentication
              case :crypto.crypto_one_time_aead(
                     :aes_256_gcm,
                     key,
                     nonce,
                     ciphertext,
                     aad,
                     auth_tag,
                     false
                   ) do
                plaintext when is_binary(plaintext) ->
                  {:ok, plaintext}

                :error ->
                  {:error, :decryption_failed}
              end

            _ ->
              {:error, :invalid_encrypted_data_format}
          end
        rescue
          error -> {:error, {:decryption_failed, error}}
        end
    end
  end

  @doc """
  Validates that the encryption key is properly configured.

  ## Examples
      iex> validate_encryption_setup()
      :ok

      iex> validate_encryption_setup()
      {:error, :encryption_key_not_configured}
  """
  def validate_encryption_setup do
    case get_encryption_key() do
      nil -> {:error, :encryption_key_not_configured}
      key when byte_size(key) == 32 -> :ok
      _ -> {:error, :invalid_encryption_key_size}
    end
  end

  @doc """
  Generates a secure encryption key for development/testing purposes.

  Note: In production, keys should come from a secure key management system.

  ## Examples
      iex> generate_key()
      "wN8YHQr7DbXo9LZmCJR6bXdz4vP..."
  """
  def generate_key do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end

  @doc """
  Tests encryption and decryption with a sample value.
  Useful for verifying the encryption setup.

  ## Examples
      iex> test_encryption()
      {:ok, "Encryption test successful"}

      iex> test_encryption()
      {:error, :encryption_key_not_configured}
  """
  def test_encryption do
    test_value = "test_secret_value_#{System.system_time(:nanosecond)}"

    with {:ok, encrypted} <- encrypt(test_value),
         {:ok, decrypted} <- decrypt(encrypted) do
      if decrypted == test_value do
        {:ok, "Encryption test successful"}
      else
        {:error, "Encryption test failed: values do not match"}
      end
    else
      error -> error
    end
  end

  # Private helper functions

  defp get_encryption_key do
    case Application.get_env(:vault_lite, :encryption_key) do
      nil ->
        nil

      key when is_binary(key) ->
        # Hash the key to ensure it's exactly 32 bytes for AES-256
        # This allows for keys of any length to be used
        :crypto.hash(:sha256, key)
    end
  end
end

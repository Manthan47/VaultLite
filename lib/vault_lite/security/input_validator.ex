defmodule VaultLite.Security.InputValidator do
  @moduledoc """
  Comprehensive input validation and sanitization for VaultLite.

  This module provides security-focused validation to prevent:
  - SQL injection attacks
  - Path traversal attacks
  - XSS attacks via metadata
  - Invalid secret key patterns
  - Oversized payloads
  - Malicious control characters
  """

  import Ecto.Changeset

  @valid_actions [
    "create",
    "read",
    "update",
    "delete",
    "list",
    "assign_role",
    "revoke_role",
    "create_user",
    "authenticate",
    "failed_authentication",
    "update_role",
    "access_check",
    "system",
    "system_cleanup",
    "purge_logs",
    "secret_share",
    "secret_revoke"
  ]

  @doc """
  Validates and sanitizes secret key input.

  Checks for:
  - Path traversal patterns
  - Malicious characters
  - Control characters
  - Appropriate length limits
  """
  def validate_secret_key(changeset, field \\ :key) do
    changeset
    |> validate_required([field])
    |> validate_length(field, min: 1, max: 255)
    |> validate_format(field, ~r/^[a-zA-Z0-9\/_\-\.]+$/,
      message: "can only contain alphanumeric characters, slashes, hyphens, underscores, and dots"
    )
    |> validate_no_path_traversal(field)
    |> validate_no_dangerous_patterns(field)
  end

  @doc """
  Validates secret value size and content.
  Note: Control character validation is skipped for encrypted values.
  """
  def validate_secret_value(changeset, field \\ :value) do
    max_size = get_config(:max_secret_size, 1_048_576)

    changeset
    |> validate_required([field])
    |> validate_secret_value_size(field, max_size)
  end

  @doc """
  Validates and sanitizes metadata input.
  """
  def validate_metadata(changeset, field \\ :metadata) do
    max_size = get_config(:max_metadata_size, 10_240)

    changeset
    |> validate_metadata_structure(field)
    |> validate_metadata_size(field, max_size)
    |> sanitize_metadata_values(field)
  end

  @doc """
  Validates username for security patterns.
  """
  def validate_username(changeset, field \\ :username) do
    changeset
    |> validate_required([field])
    |> validate_length(field, min: 3, max: 50)
    |> validate_format(field, ~r/^[a-zA-Z0-9_\-\.]+$/,
      message: "can only contain alphanumeric characters, underscores, hyphens, and dots"
    )
    |> validate_no_dangerous_patterns(field)
    |> validate_exclusion(field, ["admin", "root", "system", "administrator", "user", "guest"],
      message: "is reserved and cannot be used"
    )
  end

  @doc """
  Enhanced email validation with security checks.
  """
  def validate_email(changeset, field \\ :email) do
    changeset
    |> validate_required([field])
    |> validate_length(field, max: 255)
    |> validate_format(field, ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/,
      message: "must be a valid email address"
    )
    |> validate_no_dangerous_patterns(field)
    |> validate_email_domain_security(field)
  end

  @doc """
  Enhanced password validation.
  """
  def validate_password(changeset, field \\ :password) do
    changeset
    |> validate_required([field])
    |> validate_length(field, min: 8, max: 128)
    |> validate_password_complexity(field)
    |> validate_password_security(field)
  end

  @doc """
  Validates role name with security considerations.
  """
  def validate_role_name(changeset, field \\ :name) do
    changeset
    |> validate_required([field])
    |> validate_length(field, min: 1, max: 100)
    |> validate_format(field, ~r/^[a-zA-Z0-9_\-\s:*,\/\.]+$/,
      message:
        "can only contain alphanumeric characters, underscores, hyphens, spaces, colons, asterisks, commas, slashes, and dots"
    )
    |> validate_no_dangerous_patterns(field)
  end

  @doc """
  Validates permissions array.
  """
  def validate_permissions(changeset, field \\ :permissions) do
    valid_permissions = ["read", "write", "delete", "admin"]

    changeset
    |> validate_required([field])
    |> validate_permissions_format(field)
    |> validate_inclusion_list(field, valid_permissions)
    |> validate_permissions_not_empty(field)
  end

  @doc """
  Validates action strings for audit logs.
  """
  def validate_action(changeset, field \\ :action) do
    changeset
    |> validate_required([field])
    |> validate_inclusion(field, @valid_actions)
  end

  # Private validation functions

  defp validate_no_path_traversal(changeset, field) do
    validate_change(changeset, field, fn field, value ->
      dangerous_patterns = [
        # Path traversal
        "..",
        # Double slashes
        "//",
        # Windows path separators
        "\\",
        # Null bytes
        "\0"
      ]

      if Enum.any?(dangerous_patterns, &String.contains?(value, &1)) do
        [{field, "contains dangerous path traversal patterns"}]
      else
        []
      end
    end)
  end

  defp validate_no_dangerous_patterns(changeset, field) do
    validate_change(changeset, field, fn field, value ->
      forbidden_patterns =
        get_config(:forbidden_key_patterns, [
          # Path traversal
          ~r/\.\./,
          # HTML/SQL injection characters
          ~r/[<>\"'&]/,
          # Null bytes
          ~r/\x00/,
          # Control characters
          ~r/[\x01-\x1f\x7f]/
        ])

      dangerous_pattern = Enum.find(forbidden_patterns, &Regex.match?(&1, value))

      if dangerous_pattern do
        [{field, "contains dangerous characters or patterns"}]
      else
        []
      end
    end)
  end

  defp validate_secret_value_size(changeset, field, max_size) do
    validate_change(changeset, field, fn field, value ->
      if byte_size(value) > max_size do
        [{field, "exceeds maximum size of #{format_bytes(max_size)}"}]
      else
        []
      end
    end)
  end

  defp validate_metadata_structure(changeset, field) do
    validate_change(changeset, field, fn field, value ->
      case value do
        %{} -> []
        nil -> []
        _ -> [{field, "must be a map or nil"}]
      end
    end)
  end

  defp validate_metadata_size(changeset, field, max_size) do
    validate_change(changeset, field, fn field, value ->
      case value do
        nil ->
          []

        metadata when is_map(metadata) ->
          serialized_size = byte_size(:erlang.term_to_binary(metadata))

          if serialized_size > max_size do
            [{field, "exceeds maximum size of #{format_bytes(max_size)}"}]
          else
            []
          end

        _ ->
          []
      end
    end)
  end

  defp sanitize_metadata_values(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      metadata when is_map(metadata) ->
        sanitized_metadata =
          metadata
          |> Enum.map(fn {key, value} -> {key, sanitize_string_value(value)} end)
          |> Enum.into(%{})

        put_change(changeset, field, sanitized_metadata)

      _ ->
        changeset
    end
  end

  defp validate_email_domain_security(changeset, field) do
    validate_change(changeset, field, fn field, email ->
      domain = email |> String.split("@") |> List.last()

      # Check for suspicious domain patterns
      suspicious_patterns = [
        # IP addresses
        ~r/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/,
        # Suspicious TLDs
        ~r/\.tk$|\.ml$|\.ga$|\.cf$/,
        # Localhost domains
        ~r/localhost/i
      ]

      if Enum.any?(suspicious_patterns, &Regex.match?(&1, domain)) do
        [{field, "domain is not allowed"}]
      else
        []
      end
    end)
  end

  defp validate_password_complexity(changeset, field) do
    validate_change(changeset, field, fn field, password ->
      errors = []

      errors =
        if String.match?(password, ~r/[A-Z]/),
          do: errors,
          else: ["must contain at least one uppercase letter" | errors]

      errors =
        if String.match?(password, ~r/[a-z]/),
          do: errors,
          else: ["must contain at least one lowercase letter" | errors]

      errors =
        if String.match?(password, ~r/[0-9]/),
          do: errors,
          else: ["must contain at least one number" | errors]

      errors =
        if String.match?(password, ~r/[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]/),
          do: errors,
          else: ["must contain at least one special character" | errors]

      if Enum.empty?(errors) do
        []
      else
        [{field, Enum.join(errors, ", ")}]
      end
    end)
  end

  defp validate_password_security(changeset, field) do
    validate_change(changeset, field, fn field, password ->
      # Check for common weak passwords
      weak_passwords = [
        "password",
        "123456",
        "12345678",
        "qwerty",
        "abc123",
        "password123",
        "admin",
        "letmein",
        "welcome",
        "monkey"
      ]

      if String.downcase(password) in weak_passwords do
        [{field, "is too common and insecure"}]
      else
        []
      end
    end)
  end

  defp validate_permissions_format(changeset, field) do
    validate_change(changeset, field, fn field, permissions ->
      case permissions do
        list when is_list(list) ->
          if Enum.all?(list, &is_binary/1) do
            []
          else
            [{field, "must be a list of strings"}]
          end

        _ ->
          [{field, "must be a list"}]
      end
    end)
  end

  defp validate_inclusion_list(changeset, field, valid_values) do
    validate_change(changeset, field, fn field, permissions ->
      case permissions do
        list when is_list(list) ->
          invalid_permissions = list -- valid_values

          if Enum.empty?(invalid_permissions) do
            []
          else
            [{field, "contains invalid permissions: #{Enum.join(invalid_permissions, ", ")}"}]
          end

        _ ->
          []
      end
    end)
  end

  defp validate_permissions_not_empty(changeset, field) do
    validate_change(changeset, field, fn field, permissions ->
      case permissions do
        [] -> [{field, "must have at least one permission"}]
        _ -> []
      end
    end)
  end

  # Helper functions

  defp sanitize_string_value(value) when is_binary(value) do
    value
    # Remove HTML tags
    |> String.replace(~r/<[^>]*>/, "")
    # Remove dangerous characters
    |> String.replace(~r/[<>\"'&]/, "")
    |> String.trim()
  end

  defp sanitize_string_value(value), do: value

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 2)} MB"
  end

  defp format_bytes(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 2)} KB"
  end

  defp format_bytes(bytes), do: "#{bytes} bytes"

  defp get_config(key, default) do
    :vault_lite
    |> Application.get_env(:security, [])
    |> Keyword.get(:input_sanitization, [])
    |> Keyword.get(key, default)
  end
end

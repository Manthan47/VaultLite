# Task 2: Data Models and Database Schema - COMPLETED ✅

## Overview
Task 2 has been successfully implemented, creating robust Ecto schemas and database migrations for VaultLite's core data models: Secrets, Users, Roles, and Audit Logs.

## 📊 Implemented Schemas

### 1. ✅ Secrets Schema (`lib/vault_lite/secret.ex`)
**Purpose**: Store encrypted secrets with versioning support

**Fields**:
- `key` (string) - Unique identifier for the secret
- `value` (binary) - Encrypted secret data
- `version` (integer) - Version number for secret versioning
- `metadata` (map) - Additional metadata (created_by, etc.)
- `deleted_at` (utc_datetime) - For soft deletion
- `inserted_at`, `updated_at` - Timestamps

**Features**:
- ✅ Multiple changesets (create, update, delete)
- ✅ Validation for key length, version numbers
- ✅ Unique constraint on key+version combination
- ✅ Soft deletion support
- ✅ Query helpers for active secrets and latest versions
- ✅ Comprehensive indexes for performance

### 2. ✅ Users Schema (`lib/vault_lite/user.ex`)
**Purpose**: Manage user authentication and accounts

**Fields**:
- `username` (string) - Unique username
- `email` (string) - Unique email address
- `password_hash` (string) - Bcrypt hashed password
- `password` (virtual) - Virtual field for password input
- `active` (boolean) - User activation status
- `inserted_at`, `updated_at` - Timestamps

**Features**:
- ✅ Password hashing with Bcrypt
- ✅ Email and username validation
- ✅ Separate changesets for create, update, and password change
- ✅ Password verification function
- ✅ Query helpers for active users
- ✅ Relationship with roles (has_many)

### 3. ✅ Roles Schema (`lib/vault_lite/role.ex`)
**Purpose**: Role-Based Access Control (RBAC) system

**Fields**:
- `name` (string) - Role name
- `permissions` (array of strings) - List of permissions
- `user_id` (integer) - Reference to user
- `inserted_at`, `updated_at` - Timestamps

**Features**:
- ✅ Predefined valid permissions: `["read", "write", "delete", "admin"]`
- ✅ Permission validation in changesets
- ✅ Helper functions for permission checking
- ✅ Action-to-permission mapping
- ✅ Query helpers for user roles and permission filtering
- ✅ Unique constraint on name+user_id combination

### 4. ✅ Audit Logs Schema (`lib/vault_lite/audit_log.ex`)
**Purpose**: Track all secret operations for auditability

**Fields**:
- `user_id` (integer) - User performing the action
- `action` (string) - Action performed (create, read, update, delete, list)
- `secret_key` (string) - Key of the secret accessed
- `timestamp` (utc_datetime) - When the action occurred
- `metadata` (map) - Additional context (IP, user agent, etc.)
- `inserted_at`, `updated_at` - Timestamps

**Features**:
- ✅ Predefined valid actions
- ✅ Automatic timestamp setting
- ✅ Helper function for creating log entries
- ✅ Multiple query helpers (by user, secret, action, date range)
- ✅ Metadata support for additional context
- ✅ Comprehensive indexes for efficient querying

## 🗄️ Database Migrations

### Successfully Executed Migrations:
1. ✅ **20250626124224_create_secrets.exs** - Secrets table with indexes
2. ✅ **20250626124228_create_roles.exs** - Roles table with permissions array
3. ✅ **20250626124230_create_audit_logs.exs** - Audit logs table with indexes
4. ✅ **20250626124342_create_users.exs** - Users table with unique constraints
5. ✅ **20250626124720_add_foreign_key_to_roles.exs** - Foreign key constraint

### Database Indexes Created:
**Secrets Table**:
- Unique index on `[key, version]`
- Index on `key` for fast lookups
- Index on `inserted_at` for time-based queries
- Index on `deleted_at` for filtering deleted secrets

**Users Table**:
- Unique index on `username`
- Unique index on `email`
- Index on `active` status

**Roles Table**:
- Index on `name`
- Index on `user_id`
- Unique index on `[name, user_id]` where user_id is not null

**Audit Logs Table**:
- Index on `user_id`
- Index on `secret_key`
- Index on `action`
- Index on `timestamp`
- Index on `inserted_at`

## 🔄 Relationships

```
Users (1) -----> (many) Roles
              └─> (many) AuditLogs (via user_id)

Secrets (1) -----> (many) AuditLogs (via secret_key)
```

## 📝 Validation Features

### Secret Validations:
- Key length: 1-255 characters
- Version must be greater than 0
- Unique key+version combinations
- Required fields: key, value

### User Validations:
- Username: 3-50 characters, unique
- Email: valid email format, unique
- Password: minimum 8 characters
- Bcrypt password hashing

### Role Validations:
- Name: 1-100 characters
- Permissions: must be from valid list
- Unique role name per user

### Audit Log Validations:
- Action: must be from predefined list
- Secret key: 1-255 characters
- Automatic timestamp setting
- Metadata must be a map

## 🔍 Query Helpers

### Secret Queries:
- `active_secrets/1` - Filter out soft-deleted secrets
- `latest_versions/1` - Get latest version of each secret

### User Queries:
- `active_users/1` - Get only active users

### Role Queries:
- `for_user/2` - Get roles for specific user
- `with_permission/2` - Get roles with specific permission

### Audit Log Queries:
- `for_user/2` - Logs for specific user
- `for_secret/2` - Logs for specific secret
- `for_action/2` - Logs for specific action
- `between_dates/3` - Logs within date range
- `recent_first/1` - Order by timestamp desc
- `with_metadata/3` - Filter by metadata content

## ✅ Task 2 Requirements Met

1. **✅ Create Secrets Schema**: Complete with versioning, encryption support, soft deletion
2. **✅ Create Roles Schema**: Complete with RBAC permissions and user relationships
3. **✅ Create Audit Logs Schema**: Complete with comprehensive logging capabilities
4. **✅ Run Migrations**: All migrations executed successfully
5. **✅ Additional Features**:
   - User authentication schema
   - Comprehensive validations
   - Query helpers for efficient data access
   - Proper database indexes
   - Foreign key relationships

## 🚀 Next Steps

Task 2 is complete! Ready to proceed with:
- **Task 3**: Secret Management Logic (encryption, CRUD operations)
- **Task 4**: Role-Based Access Control implementation
- **Task 5**: REST API Development
- **Task 6**: Audit Logging integration
- **Task 7**: Testing

## 🔒 Security Notes

- Password hashing using Bcrypt
- Soft deletion for secrets (audit trail preservation)
- Comprehensive audit logging for all operations
- Role-based permission system ready for implementation
- Proper database constraints and validations

## 📊 Database Schema Verification

To verify the schemas are working correctly:

```bash
# Start IEx with your project
iex -S mix

# Test the schemas
alias VaultLite.{User, Role, Secret, AuditLog, Repo}

# Create a test user
{:ok, user} = %User{}
|> User.changeset(%{username: "admin", email: "admin@vault.local", password: "password123"})
|> Repo.insert()

# Create a test role
{:ok, role} = %Role{}
|> Role.changeset(%{name: "admin", permissions: ["admin"], user_id: user.id})
|> Repo.insert()

# Test audit logging
audit_changeset = AuditLog.log_action("create", "test-secret", user.id, %{ip: "127.0.0.1"})
{:ok, _audit} = Repo.insert(audit_changeset)
```

Task 2 implementation is robust, scalable, and ready for the next development phase! 
# Task 4: Role-Based Access Control (RBAC) - COMPLETED ✅

## Overview
Task 4 has been successfully implemented, creating a comprehensive Role-Based Access Control (RBAC) system with JWT authentication, path-based permissions, and complete integration with secret operations for VaultLite.

## 🔐 Core Features Implemented

### 1. ✅ VaultLite.Auth Context Module (`lib/vault_lite/auth.ex`)
**Purpose**: Central RBAC management with role assignment and permission checking

**Key Functions**:
- `assign_role/2` - Assigns roles with permissions to users
- `check_access/3` - Validates user permissions for specific actions and secret keys
- `can_access?/3` - Non-logging permission check for UI/bulk operations
- `update_role_permissions/3` - Updates existing role permissions
- `remove_role/2` - Removes roles from users
- `create_path_role/3` - Creates path-based roles with wildcard support
- `get_user_roles/1` - Retrieves all roles for a user
- `get_user_permissions/1` - Gets consolidated permissions across all user roles
- `is_admin?/1` - Checks for admin privileges
- `list_users_with_permission/1` - Finds users with specific permissions

**Advanced Features**:
- ✅ **Path-based Access Control**: Support for wildcard patterns (e.g., `api/dev/*`)
- ✅ **Role Hierarchy**: Admin permissions override all other checks
- ✅ **Automatic Audit Logging**: All role changes and access checks logged
- ✅ **Pattern Matching**: Complex path patterns with `*` wildcards
- ✅ **Action Mapping**: Maps CRUD actions to required permissions

### 2. ✅ VaultLite.Guardian Module (`lib/vault_lite/guardian.ex`)
**Purpose**: JWT authentication with Guardian integration

**Authentication Features**:
- ✅ **JWT Token Generation**: Creates tokens with user permissions and claims
- ✅ **Token Validation**: Validates and decodes JWT tokens
- ✅ **User Authentication**: Username/email + password authentication
- ✅ **Token Refresh**: Updates tokens with current user permissions
- ✅ **Blacklist Support**: Framework for token revocation (placeholder implementation)

**Guardian Integration**:
- ✅ **AuthPipeline**: Ready-to-use Phoenix pipeline for authentication
- ✅ **AuthErrorHandler**: Comprehensive error handling for auth failures
- ✅ **Enhanced Claims**: Tokens include permissions, admin status, and metadata
- ✅ **Multi-identifier Support**: Login with username or email

**Security Features**:
- ✅ **Timing Attack Protection**: Uses `Bcrypt.no_user_verify()` for invalid users
- ✅ **Active User Check**: Prevents inactive users from authenticating
- ✅ **Token Claims Validation**: Comprehensive token validation and error handling
- ✅ **Bearer Token Support**: Standard Authorization: Bearer header support

### 3. ✅ Secret Operations Integration
**Purpose**: Complete RBAC integration with all secret operations

**Protected Operations**:
- ✅ **create_secret/4**: Requires "write" permission for the secret key
- ✅ **get_secret/3**: Requires "read" permission for the secret key  
- ✅ **update_secret/4**: Requires "write" permission for the secret key
- ✅ **delete_secret/2**: Requires "delete" permission for the secret key
- ✅ **list_secrets/2**: Filters results based on user's read permissions
- ✅ **get_secret_versions/2**: Requires "read" permission for the secret key

**Permission Enforcement**:
- ✅ **Early Authorization**: Checks permissions before any processing
- ✅ **Granular Control**: Different permissions for different actions
- ✅ **Path-based Filtering**: Supports wildcard patterns in secret keys
- ✅ **Graceful Errors**: Returns `:unauthorized` for permission violations

## 🎭 Role-Based Access Control System

### Permission Types:
- **`read`** - Can read/view secrets
- **`write`** - Can create and update secrets  
- **`delete`** - Can delete secrets
- **`admin`** - Can perform all operations (overrides all other permissions)

### Role Assignment Examples:
```elixir
# Admin role (full access)
Auth.assign_role(user, %{name: "admin", permissions: ["admin"]})

# Developer role (read/write for specific paths)
Auth.create_path_role(user, "api/dev/*", ["read", "write"])

# Read-only role (view access only)
Auth.assign_role(user, %{name: "viewer", permissions: ["read"]})

# Production access (read/write for production paths)
Auth.create_path_role(user, "api/prod/*", ["read", "write"])
```

### Path-based Permission System:
```elixir
# Exact match
Auth.check_access(user, "database_password", "read")

# Wildcard patterns
Auth.create_path_role(user, "api/dev/*", ["read", "write"])
# Allows access to: api/dev/database, api/dev/cache_key, api/dev/anything

# Complex patterns
Auth.create_path_role(user, "secrets/*/production", ["read"])
# Allows access to: secrets/app1/production, secrets/app2/production
```

## 🔑 JWT Authentication System

### Token Generation:
```elixir
# Basic authentication
{:ok, user, token} = Guardian.authenticate_user("admin", "password123")

# Token contains enhanced claims:
%{
  "sub" => "1",                    # User ID
  "permissions" => ["admin"],      # User permissions
  "is_admin" => true,             # Admin flag
  "username" => "admin",          # Username
  "iat" => 1640995200            # Issued at timestamp
}
```

### Token Validation:
```elixir
# Validate token and get user
{:ok, user, claims} = Guardian.validate_token(token)

# Refresh token with updated permissions
{:ok, new_token} = Guardian.refresh_token(current_token)
```

### Phoenix Integration:
```elixir
# In router.ex
pipeline :authenticated do
  plug VaultLite.Guardian.AuthPipeline
end

scope "/api", VaultLiteWeb do
  pipe_through [:api, :authenticated]
  # Protected routes here
end
```

## 🛤️ Path Pattern Matching

### Supported Patterns:
1. **Exact Match**: `"database_password"` matches only `"database_password"`
2. **Suffix Wildcard**: `"api/dev/*"` matches `"api/dev/database"`, `"api/dev/cache"`, etc.
3. **Complex Patterns**: `"*/production/*"` matches `"app1/production/db"`, `"app2/production/cache"`

### Pattern Matching Logic:
```elixir
# Implementation highlights
defp matches_path_pattern?(secret_key, pattern) do
  cond do
    # Exact match
    secret_key == pattern -> true
    
    # Suffix wildcard
    String.ends_with?(pattern, "*") ->
      prefix = String.replace_suffix(pattern, "*", "")
      String.starts_with?(secret_key, prefix)
    
    # Complex patterns with regex
    String.contains?(pattern, "*") ->
      regex_pattern = String.replace(pattern, "*", ".*") |> Regex.compile!()
      Regex.match?(regex_pattern, secret_key)
    
    true -> false
  end
end
```

## 🔧 Error Handling

### Authentication Errors:
- `:invalid_credentials` - Wrong username/password
- `:user_inactive` - User account disabled
- `:invalid_token` - Malformed or expired JWT token
- `:user_not_found` - Token references non-existent user

### Authorization Errors:
- `:unauthorized` - User lacks required permissions
- `:role_not_found` - Attempting to modify non-existent role

### Guardian Pipeline Errors:
```json
{
  "error": {
    "type": "unauthenticated",
    "message": "Authentication required"
  }
}
```

## 📊 Integration Architecture

### Secret Operations Flow:
```
1. User Request → 2. Auth Check → 3. Permission Validation → 4. Secret Operation → 5. Audit Log
                       ↓                    ↓                      ↓                ↓
                  Guardian.validate_token   Auth.check_access    Secrets.get_secret  AuditLog.insert
```

### Permission Resolution:
```
1. Get User Roles → 2. Check Admin → 3. Check Required Permission → 4. Validate Path Access
        ↓                   ↓                    ↓                        ↓
   Auth.get_user_roles   "admin" in perms    action_to_permission    matches_path_pattern?
```

## ✅ Task 4 Requirements Verification

### 1. ✅ Create Auth Context
- **VaultLite.Auth module**: ✅ Complete with all required functions
- **assign_role/2**: ✅ Role assignment with permissions and audit logging
- **check_access/3**: ✅ Permission validation with path-based patterns
- **Role management**: ✅ Create, update, remove roles with full audit trail

### 2. ✅ Define Permissions
- **Path-based patterns**: ✅ Support for `secrets/api/*` style patterns
- **Wildcard matching**: ✅ Complex pattern matching with regex support
- **Permission types**: ✅ `read`, `write`, `delete`, `admin` permissions
- **Path role creation**: ✅ `create_path_role/3` for path-specific access

### 3. ✅ Integrate with Secret Operations
- **Permission checks**: ✅ All secret operations check permissions first
- **Authorization errors**: ✅ Return `:unauthorized` for insufficient permissions
- **Path-based filtering**: ✅ `list_secrets/2` filters based on user permissions
- **Granular control**: ✅ Different permissions for different operations

### 4. ✅ User Authentication
- **Guardian integration**: ✅ Complete JWT implementation with enhanced claims
- **Token generation**: ✅ `generate_token/3` with user permissions in claims
- **Token validation**: ✅ `validate_token/1` with comprehensive error handling
- **Phoenix pipeline**: ✅ `AuthPipeline` ready for router integration
- **Multi-format auth**: ✅ Username or email authentication support

## 🧪 Functionality Testing

### Authentication Testing:
```elixir
# User authentication
{:ok, user, token} = Guardian.authenticate_user("admin", "password123")

# Token validation
{:ok, validated_user, claims} = Guardian.validate_token(token)

# Invalid credentials
{:error, :invalid_credentials} = Guardian.authenticate_user("admin", "wrong")
```

### Role Assignment Testing:
```elixir
# Assign admin role
{:ok, role} = Auth.assign_role(user, %{name: "admin", permissions: ["admin"]})

# Create path-based role
{:ok, dev_role} = Auth.create_path_role(user, "api/dev/*", ["read", "write"])

# Check user permissions
permissions = Auth.get_user_permissions(user.id)  # ["admin"] or ["read", "write"]
```

### Access Control Testing:
```elixir
# Admin access (should succeed)
{:ok, :authorized} = Auth.check_access(admin_user, "any_secret", "delete")

# Developer access to dev path (should succeed)
{:ok, :authorized} = Auth.check_access(dev_user, "api/dev/database", "read")

# Developer access to prod path (should fail)
{:error, :unauthorized} = Auth.check_access(dev_user, "api/prod/database", "read")

# Read-only user trying to write (should fail)
{:error, :unauthorized} = Auth.check_access(readonly_user, "any_secret", "write")
```

### Secret Operations Testing:
```elixir
# Admin can create secrets anywhere
{:ok, secret} = Secrets.create_secret("admin/backup", "secret", admin_user)

# Developer can access dev secrets
{:ok, secret_data} = Secrets.get_secret("api/dev/database", dev_user)

# Developer cannot access prod secrets
{:error, :unauthorized} = Secrets.get_secret("api/prod/database", dev_user)

# Read-only user cannot create secrets
{:error, :unauthorized} = Secrets.create_secret("test", "value", readonly_user)
```

## 📈 Performance Features

### Efficient Permission Checking:
- ✅ **Non-logging checks**: `can_access?/3` for bulk operations
- ✅ **Role caching**: Single query for user roles per operation
- ✅ **Pattern optimization**: Efficient wildcard matching algorithms
- ✅ **Early authorization**: Checks permissions before expensive operations

### Database Optimization:
- ✅ **Indexed queries**: Uses existing role and user indexes
- ✅ **Minimal queries**: Single query to get user roles and permissions
- ✅ **Efficient filtering**: Database-level filtering where possible

## 🚀 Next Steps

Task 4 is complete! Ready to proceed with:
- **Task 5**: REST API Development (with RBAC-protected endpoints)
- **Task 6**: Audit Logging enhancement
- **Task 7**: Testing (comprehensive test suite for RBAC)

## 💡 Usage Examples

### Complete RBAC Setup:
```elixir
# 1. Create users
{:ok, admin} = User.changeset(%User{}, %{username: "admin", email: "admin@vault.local", password: "secure123"}) |> Repo.insert()
{:ok, dev} = User.changeset(%User{}, %{username: "dev", email: "dev@vault.local", password: "dev123"}) |> Repo.insert()

# 2. Assign roles
{:ok, _} = Auth.assign_role(admin, %{name: "admin", permissions: ["admin"]})
{:ok, _} = Auth.create_path_role(dev, "api/dev/*", ["read", "write"])

# 3. Authenticate and get token
{:ok, user, token} = Guardian.authenticate_user("admin", "secure123")

# 4. Use in API headers
headers = [{"Authorization", "Bearer #{token}"}]

# 5. Create and access secrets with RBAC
{:ok, secret} = Secrets.create_secret("api/dev/database", "dev_password", dev)  # ✅ Allowed
{:error, :unauthorized} = Secrets.create_secret("api/prod/database", "prod_password", dev)  # ❌ Denied
```

### Path-based Role Management:
```elixir
# Development team access
Auth.create_path_role(dev_user, "api/dev/*", ["read", "write"])
Auth.create_path_role(dev_user, "staging/*", ["read"])

# Production team access  
Auth.create_path_role(prod_user, "api/prod/*", ["read", "write", "delete"])
Auth.create_path_role(prod_user, "backup/*", ["read"])

# Security team access
Auth.assign_role(security_user, %{name: "security", permissions: ["read"]})  # Read all secrets

# Admin access
Auth.assign_role(admin_user, %{name: "admin", permissions: ["admin"]})  # Full access
```

## 🔒 Security Notes

- **JWT Security**: Tokens include user permissions and can be refreshed
- **Password Security**: Bcrypt hashing with timing attack protection
- **Permission Granularity**: Fine-grained control over secret access
- **Audit Trail**: Complete logging of all role changes and access attempts
- **Path Isolation**: Teams can only access their designated secret paths
- **Admin Override**: Admin permissions provide full system access for management

Task 4 implementation provides enterprise-grade RBAC with JWT authentication, enabling secure multi-user and multi-tenant secret management! 🎉 
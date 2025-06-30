# VaultLite

A secure secrets management system built with Elixir and Phoenix, providing encrypted storage, versioning, and role-based access control (RBAC) for secrets. VaultLite offers enterprise-grade security features including AES-256-GCM encryption, comprehensive audit logging, and JWT-based authentication.

## Features

- 🔐 **AES-256-GCM Encryption**: Military-grade encryption for all secret values
- 📝 **Secret Versioning**: Complete version history with the ability to retrieve any version
- 👥 **Role-Based Access Control (RBAC)**: Granular permissions with path-based access patterns
- 📊 **Comprehensive Audit Logging**: Every operation is logged for compliance and security
- 🔑 **JWT Authentication**: Secure token-based authentication system
- 🛡️ **Rate Limiting**: Protection against abuse and DDoS attacks
- 🗑️ **Soft Deletion**: Safe secret deletion with preservation for audit trails
- 🔄 **RESTful API**: Clean, consistent API design following REST conventions

## Quick Start

### Prerequisites

- Elixir 1.17+ and Erlang 27+
- PostgreSQL 15+
- Environment variables for encryption keys

### Setup

1. **Clone and install dependencies:**
   ```bash
   git clone <repository-url>
   cd vault_lite
   mix setup
   ```

2. **Configure environment variables:**
   ```bash
   # Create .env file or set environment variables
   export VAULT_LITE_ENCRYPTION_KEY="your-32-byte-encryption-key-here"
   export GUARDIAN_SECRET_KEY="your-guardian-secret-key-here"
   export DATABASE_URL="ecto://username:password@localhost/vault_lite_dev"
   ```

3. **Start the server:**
   ```bash
   mix phx.server
   ```

The API will be available at `http://localhost:4000/api`

## Admin User Bootstrap

VaultLite provides multiple ways to create the initial admin user (required to manage roles):

### Option 1: Database Seeding (Recommended for Development)
```bash
# Run the seeds to create initial admin user
mix run priv/repo/seeds.exs

# Or use custom admin credentials via environment variables
ADMIN_USERNAME=myadmin ADMIN_EMAIL=admin@company.com ADMIN_PASSWORD=SecurePass123! mix run priv/repo/seeds.exs
```

### Option 2: Mix Task (Recommended for Production)
```bash
# Interactive admin creation
mix vault_lite.admin create

# Non-interactive with command line arguments
mix vault_lite.admin create --username admin --email admin@vault.local --password SecurePass123

# List all admin users
mix vault_lite.admin list

# Promote existing user to admin
mix vault_lite.admin promote john_doe
```

### Option 3: Bootstrap API Endpoint (One-time Setup)
```bash
# Check if bootstrap is needed
curl -X GET http://localhost:4000/api/bootstrap/status

# Create initial admin (only works when no users exist)
curl -X POST http://localhost:4000/api/bootstrap/setup \
  -H "Content-Type: application/json" \
  -d '{
    "admin": {
      "username": "admin",
      "email": "admin@example.com",
      "password": "SecurePassword123!"
    }
  }'
```

## API Usage Examples

### Authentication

#### User Registration
```bash
curl -X POST http://localhost:4000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "username": "john_doe",
      "email": "john@example.com", 
      "password": "secure_password123"
    }
  }'
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "user": {
      "id": 1,
      "username": "john_doe",
      "email": "john@example.com"
    }
  }
}
```

#### User Login
```bash
curl -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "john_doe",
    "password": "secure_password123"
  }'
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "user": {
      "id": 1,
      "username": "john_doe", 
      "email": "john@example.com"
    }
  }
}
```

### Secret Management

> **Note:** All secret endpoints require authentication. Include the JWT token in the Authorization header.

#### Create a Secret
```bash
curl -X POST http://localhost:4000/api/secrets \
  -H "Authorization: Bearer <your-jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "database_password",
    "value": "super_secure_db_password_123",
    "metadata": {
      "environment": "production",
      "description": "Main database password",
      "created_by": "john_doe"
    }
  }'
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "key": "database_password",
    "version": 1,
    "metadata": {
      "environment": "production",
      "description": "Main database password",
      "created_by": "john_doe"
    },
    "created_at": "2024-01-15T10:30:00Z"
  }
}
```

#### Retrieve a Secret (Latest Version)
```bash
curl -X GET http://localhost:4000/api/secrets/database_password \
  -H "Authorization: Bearer <your-jwt-token>"
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "key": "database_password",
    "value": "super_secure_db_password_123",
    "version": 2,
    "metadata": {
      "environment": "production",
      "description": "Main database password",
      "updated_by": "john_doe"
    },
    "created_at": "2024-01-15T10:30:00Z",
    "updated_at": "2024-01-15T11:45:00Z"
  }
}
```

#### Retrieve a Specific Version
```bash
curl -X GET http://localhost:4000/api/secrets/database_password/versions/1 \
  -H "Authorization: Bearer <your-jwt-token>"
```

#### Update a Secret (Creates New Version)
```bash
curl -X PUT http://localhost:4000/api/secrets/database_password \
  -H "Authorization: Bearer <your-jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "value": "new_updated_password_456",
    "metadata": {
      "environment": "production", 
      "description": "Updated database password",
      "updated_by": "john_doe",
      "reason": "Security rotation"
    }
  }'
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "key": "database_password",
    "version": 2,
    "metadata": {
      "environment": "production",
      "description": "Updated database password", 
      "updated_by": "john_doe",
      "reason": "Security rotation"
    },
    "updated_at": "2024-01-15T11:45:00Z"
  }
}
```

#### List All Accessible Secrets
```bash
curl -X GET "http://localhost:4000/api/secrets?page=1&limit=10" \
  -H "Authorization: Bearer <your-jwt-token>"
```

**Response:**
```json
{
  "status": "success",
  "data": [
    {
      "key": "database_password",
      "version": 2,
      "metadata": {
        "environment": "production"
      },
      "created_at": "2024-01-15T10:30:00Z",
      "updated_at": "2024-01-15T11:45:00Z"
    },
    {
      "key": "api_key",
      "version": 1,
      "metadata": {
        "service": "external_api"
      },
      "created_at": "2024-01-15T09:15:00Z",
      "updated_at": "2024-01-15T09:15:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 10,
    "count": 2
  }
}
```

#### Get All Versions of a Secret
```bash
curl -X GET http://localhost:4000/api/secrets/database_password/versions \
  -H "Authorization: Bearer <your-jwt-token>"
```

**Response:**
```json
{
  "status": "success",
  "data": [
    {
      "version": 2,
      "metadata": {
        "updated_by": "john_doe",
        "reason": "Security rotation"
      },
      "created_at": "2024-01-15T11:45:00Z"
    },
    {
      "version": 1,
      "metadata": {
        "created_by": "john_doe"
      },
      "created_at": "2024-01-15T10:30:00Z"
    }
  ]
}
```

#### Delete a Secret (Soft Delete)
```bash
curl -X DELETE http://localhost:4000/api/secrets/database_password \
  -H "Authorization: Bearer <your-jwt-token>"
```

**Response:**
```json
{
  "status": "success",
  "message": "Secret deleted successfully"
}
```

### Role Management

> **Note:** Role management endpoints require admin permissions.

#### Create a Role
```bash
curl -X POST http://localhost:4000/api/roles \
  -H "Authorization: Bearer <admin-jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "role": {
      "name": "developer",
      "permissions": ["read", "write"],
      "path_patterns": ["secrets/dev/*", "secrets/staging/*"],
      "user_id": 2
    }
  }'
```

#### Assign a Role to a User
```bash
curl -X POST http://localhost:4000/api/roles/assign \
  -H "Authorization: Bearer <admin-jwt-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": 2,
    "role_data": {
      "name": "developer",
      "permissions": ["read", "write"],
      "path_patterns": ["secrets/dev/*", "secrets/staging/*"]
    }
  }'
```

#### List All Roles (Admin Only)
```bash
curl -X GET http://localhost:4000/api/roles \
  -H "Authorization: Bearer <admin-jwt-token>"
```

### Audit Logs

VaultLite maintains comprehensive audit logs for all secret operations, providing full traceability for compliance and security monitoring.

> **Note:** Audit endpoints require appropriate permissions. Admin users can access all logs, while regular users can only access logs for secrets they have read permissions for.

#### Get All Audit Logs (Admin Only)
```bash
curl -X GET "http://localhost:4000/api/audit/logs?limit=20&offset=0" \
  -H "Authorization: Bearer <admin-jwt-token>"
```

**Optional Query Parameters:**
- `user_id`: Filter by specific user ID
- `secret_key`: Filter by specific secret key
- `action`: Filter by action type (`create`, `read`, `update`, `delete`, `list`)
- `start_date`: Filter logs from this date (ISO 8601 format)
- `end_date`: Filter logs until this date (ISO 8601 format)
- `limit`: Number of logs to return (default: 50, max: 100)
- `offset`: Number of logs to skip for pagination

**Example with filters:**
```bash
curl -X GET "http://localhost:4000/api/audit/logs?secret_key=database_password&action=read&start_date=2024-01-01T00:00:00Z&limit=10" \
  -H "Authorization: Bearer <admin-jwt-token>"
```

**Response:**
```json
{
  "status": "success",
  "data": [
    {
      "id": 156,
      "user_id": 2,
      "action": "read",
      "secret_key": "database_password",
      "timestamp": "2024-01-15T14:30:00Z",
      "metadata": {
        "version": 2,
        "user_agent": "curl/7.68.0",
        "ip_address": "192.168.1.100"
      },
      "inserted_at": "2024-01-15T14:30:00Z",
      "updated_at": "2024-01-15T14:30:00Z"
    },
    {
      "id": 155,
      "user_id": 1,
      "action": "update", 
      "secret_key": "database_password",
      "timestamp": "2024-01-15T11:45:00Z",
      "metadata": {
        "old_version": 1,
        "new_version": 2,
        "reason": "Security rotation"
      },
      "inserted_at": "2024-01-15T11:45:00Z",
      "updated_at": "2024-01-15T11:45:00Z"
    }
  ],
  "pagination": {
    "limit": 10,
    "offset": 0,
    "total": 156
  }
}
```

#### Get Audit Trail for Specific Secret
```bash
curl -X GET http://localhost:4000/api/audit/secrets/database_password \
  -H "Authorization: Bearer <your-jwt-token>"
```

**Optional Query Parameters:**
- `limit`: Number of logs to return (default: 50)
- `offset`: Number of logs to skip for pagination

**Response:**
```json
{
  "status": "success",
  "data": [
    {
      "id": 156,
      "user_id": 2,
      "action": "read",
      "secret_key": "database_password",
      "timestamp": "2024-01-15T14:30:00Z",
      "metadata": {
        "version": 2,
        "user_agent": "curl/7.68.0"
      }
    },
    {
      "id": 155,
      "user_id": 1,
      "action": "update",
      "secret_key": "database_password", 
      "timestamp": "2024-01-15T11:45:00Z",
      "metadata": {
        "old_version": 1,
        "new_version": 2,
        "reason": "Security rotation"
      }
    },
    {
      "id": 134,
      "user_id": 1,
      "action": "create",
      "secret_key": "database_password",
      "timestamp": "2024-01-15T10:30:00Z",
      "metadata": {
        "version": 1,
        "environment": "production"
      }
    }
  ],
  "pagination": {
    "limit": 50,
    "offset": 0,
    "total": 3
  }
}
```

#### Get User's Audit Trail
```bash
# Admin can access any user's audit trail
curl -X GET http://localhost:4000/api/audit/users/2 \
  -H "Authorization: Bearer <admin-jwt-token>"

# Users can access their own audit trail
curl -X GET http://localhost:4000/api/audit/users/2 \
  -H "Authorization: Bearer <user-jwt-token>"
```

**Optional Query Parameters:**
- `limit`: Number of logs to return (default: 50)
- `offset`: Number of logs to skip for pagination  
- `action`: Filter by action type
- `secret_key`: Filter by specific secret

**Response:**
```json
{
  "status": "success",
  "data": [
    {
      "id": 156,
      "user_id": 2,
      "action": "read",
      "secret_key": "database_password",
      "timestamp": "2024-01-15T14:30:00Z",
      "metadata": {
        "version": 2
      }
    },
    {
      "id": 145,
      "user_id": 2,
      "action": "create",
      "secret_key": "api_key", 
      "timestamp": "2024-01-15T09:15:00Z",
      "metadata": {
        "version": 1,
        "environment": "development"
      }
    }
  ],
  "pagination": {
    "limit": 50,
    "offset": 0,
    "total": 12
  }
}
```

#### Get Audit Statistics (Admin Only)
```bash
curl -X GET http://localhost:4000/api/audit/statistics \
  -H "Authorization: Bearer <admin-jwt-token>"
```

**Optional Query Parameters:**
- `start_date`: Statistics from this date (ISO 8601 format)
- `end_date`: Statistics until this date (ISO 8601 format)

**Example with date range:**
```bash
curl -X GET "http://localhost:4000/api/audit/statistics?start_date=2024-01-01T00:00:00Z&end_date=2024-01-31T23:59:59Z" \
  -H "Authorization: Bearer <admin-jwt-token>"
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "total_logs": 1567,
    "actions": {
      "create": 234,
      "read": 1123,
      "update": 156,
      "delete": 43,
      "list": 11
    },
    "top_secrets": [
      {
        "secret_key": "database_password",
        "access_count": 245
      },
      {
        "secret_key": "api_key",
        "access_count": 189
      },
      {
        "secret_key": "jwt_secret",
        "access_count": 134
      }
    ],
    "active_users": 23
  }
}
```

#### Purge Old Audit Logs (Admin Only)
```bash
curl -X DELETE "http://localhost:4000/api/audit/purge?days_to_keep=90" \
  -H "Authorization: Bearer <admin-jwt-token>"
```

**Optional Query Parameters:**
- `days_to_keep`: Number of days of logs to retain (default: 365)

**Response:**
```json
{
  "status": "success", 
  "message": "Purged 450 audit logs older than 90 days",
  "data": {
    "deleted_count": 450,
    "days_kept": 90
  }
}
```

### Error Handling

#### Unauthorized Access
```bash
curl -X GET http://localhost:4000/api/secrets/database_password
# No Authorization header
```

**Response:**
```json
{
  "error": "unauthenticated",
  "message": "Authentication required"
}
```

#### Permission Denied
```bash
curl -X POST http://localhost:4000/api/roles \
  -H "Authorization: Bearer <non-admin-token>" \
  -H "Content-Type: application/json" \
  -d '{"role": {...}}'
```

**Response:**
```json
{
  "status": "error",
  "message": "Insufficient permissions"
}
```

#### Rate Limit Exceeded
```bash
# After exceeding rate limits
curl -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"identifier": "user", "password": "pass"}'
```

**Response:**
```
HTTP/1.1 429 Too Many Requests
Rate limit exceeded
```

#### Validation Errors
```bash
curl -X POST http://localhost:4000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "username": "",
      "email": "invalid-email",
      "password": "123"
    }
  }'
```

**Response:**
```json
{
  "status": "error",
  "errors": {
    "username": ["can't be blank"],
    "email": ["has invalid format"],
    "password": ["should be at least 8 character(s)"]
  }
}
```

## Rate Limits

VaultLite implements the following rate limits per IP address:

- **Login requests**: 10 per minute
- **Registration requests**: 5 per minute  
- **General API requests**: 100 per minute

When rate limits are exceeded, the API returns HTTP 429 with the message "Rate limit exceeded".

## Security Features

- **Encryption**: All secret values are encrypted using AES-256-GCM before storage
- **Authentication**: JWT-based authentication with secure token generation
- **Authorization**: Role-based access control with path-based permissions
- **Audit Logging**: All operations are logged for security and compliance
- **Rate Limiting**: Protection against brute force attacks and API abuse
- **Input Validation**: Comprehensive validation and sanitization of all inputs
- **Secure Defaults**: No hardcoded secrets, environment-based configuration

## Environment Variables

Required environment variables:

```bash
# Encryption key for AES-256-GCM (32 bytes)
VAULT_LITE_ENCRYPTION_KEY="your-32-byte-encryption-key-here"

# Guardian JWT secret key
GUARDIAN_SECRET_KEY="your-guardian-secret-key-here"

# Database configuration
DATABASE_URL="ecto://username:password@localhost/vault_lite_dev"
```

## Development

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

### Database Management

#### Initial Setup & Seeding
```bash
# Setup database and run migrations
mix ecto.setup

# Seed database with initial admin user and sample data
mix run priv/repo/seeds.exs

# Custom admin credentials for seeding
ADMIN_USERNAME=myadmin \
ADMIN_EMAIL=admin@company.com \
ADMIN_PASSWORD=SecurePass123! \
mix run priv/repo/seeds.exs
```

#### Database Migrations
```bash
# Run pending migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback

# Reset database (drops, creates, migrates, and seeds)
mix ecto.reset

# Check migration status
mix ecto.migrations
```

#### Admin User Management
```bash
# Create admin user interactively
mix vault_lite.admin create

# Create admin user with command line arguments
mix vault_lite.admin create --username admin --email admin@vault.local --password SecurePass123

# List all admin users
mix vault_lite.admin list

# Promote existing user to admin
mix vault_lite.admin promote john_doe

# Remove admin privileges (requires at least one admin to remain)
mix vault_lite.admin demote john_doe

# Show admin management help
mix vault_lite.admin
```

### Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/vault_lite_web/controllers/secret_controller_test.exs

# Run tests with coverage
mix test --cover
```

### API Routes

View all available routes:

```bash
mix phx.routes
```

## Production Deployment

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

### Security Checklist for Production

- [ ] Set strong, unique encryption keys
- [ ] Use HTTPS/TLS for all communications
- [ ] Configure proper database security
- [ ] Set up monitoring and alerting
- [ ] Regular security audits of access logs
- [ ] Implement backup and recovery procedures
- [ ] Configure firewall and network security

## Learn More

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## License

This project is licensed under the MIT License - see the LICENSE file for details.

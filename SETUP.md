# VaultLite Setup Guide

## Task 1: Project Setup - COMPLETED ✅

### What's Been Implemented

1. **✅ Phoenix Project Created**: Project was created with `mix phx.new vault_lite --database postgres`

2. **✅ Dependencies Added**: The following dependencies have been added to `mix.exs`:
   - `guardian` (~> 2.3) - For JWT authentication
   - `bcrypt_elixir` (~> 3.0) - For password hashing  
   - `plug_attack` (~> 0.4) - For rate limiting

3. **✅ Database Configuration**: PostgreSQL is configured in:
   - `config/dev.exs` - Development database settings
   - `config/test.exs` - Test database settings

4. **✅ Environment Variables Configuration**: Added to `config/runtime.exs`:
   - Encryption key loading from `VAULT_LITE_ENCRYPTION_KEY`
   - Guardian JWT secret from `GUARDIAN_SECRET_KEY`
   - PlugAttack rate limiting configuration

5. **✅ Database Setup**: Ran `mix ecto.setup` to create and migrate databases

### Required Environment Variables Setup

To complete Task 1, you need to set the following environment variables:

#### Option 1: Create a .env file (recommended for development)
Create a `.env` file in your project root:

```bash
# Generate encryption key (32 bytes for AES-256)
VAULT_LITE_ENCRYPTION_KEY=$(mix phx.gen.secret 32)

# Generate Guardian JWT secret
GUARDIAN_SECRET_KEY=$(mix phx.gen.secret)

# Database credentials (optional if using defaults)
DB_USERNAME=postgres
DB_PASSWORD=postgres
DB_HOSTNAME=localhost
```

#### Option 2: Export environment variables
```bash
export VAULT_LITE_ENCRYPTION_KEY=$(mix phx.gen.secret 32)
export GUARDIAN_SECRET_KEY=$(mix phx.gen.secret)
```

#### Option 3: Use a .env loader (requires adding dependency)
Add to `mix.exs`:
```elixir
{:dotenv, "~> 3.0.0", only: [:dev, :test]}
```

Then add to your config files:
```elixir
# In config/config.exs or config/dev.exs
if Mix.env() in [:dev, :test] do
  Dotenv.load()
end
```

### Verification Steps

1. **Check Dependencies**: 
   ```bash
   mix deps.get
   ```

2. **Verify Database Connection**:
   ```bash
   mix ecto.create  # Should show database already exists
   ```

3. **Generate Secret Keys**:
   ```bash
   # Generate encryption key (32 bytes)
   mix phx.gen.secret 32
   
   # Generate Guardian secret
   mix phx.gen.secret
   ```

4. **Test Configuration**:
   ```bash
   # Start the Phoenix server to verify everything works
   mix phx.server
   ```

### Next Steps

Task 1 is complete! You can now proceed with:
- **Task 2**: Data Models and Database Schema
- **Task 3**: Secret Management Logic  
- **Task 4**: Role-Based Access Control (RBAC)
- **Task 5**: REST API Development
- **Task 6**: Audit Logging
- **Task 7**: Testing

### Security Notes

🔒 **Important Security Reminders**:
- Never commit `.env` files to version control
- Use strong, randomly generated keys in production
- Rotate encryption keys periodically
- Use environment-specific configurations for different deployment stages

### Troubleshooting

**Database Connection Issues**:
- Ensure PostgreSQL is running locally
- Verify database credentials in config files
- Check if database ports are available

**Compilation Issues**:
- Run `mix clean` and `mix compile` if you encounter compilation errors
- Ensure all dependencies are fetched with `mix deps.get`

**Environment Variable Issues**:
- Verify environment variables are set correctly
- Check config/runtime.exs for proper variable names
- Restart your application after setting new environment variables 
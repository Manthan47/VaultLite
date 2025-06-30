# Instructions for Building VaultLite (HashiCorp Vault-Lite in Elixir)

## Overview
VaultLite is a secure secrets management system built in Elixir, providing encrypted storage, versioning, and role-based access control (RBAC) for secrets. This document outlines detailed tasks and subtasks for developing VaultLite using AI tools like Cursor or GitHub Copilot. Each task includes a description, subtasks, and AI prompts to guide code generation.

---

## Prerequisites
- **Elixir**: Version 1.17 or later.
- **Erlang**: Version 27 or later.
- **PostgreSQL**: Version 15 or later.
- **Tools**: Docker (optional for deployment), Cursor/GitHub Copilot for AI-assisted coding.
- **Dependencies**: Phoenix, Ecto, Guardian, bcrypt_elixir, PlugAttack.

---

## Task Breakdown

### Task 1: Project Setup
**Goal**: Initialize an Elixir Phoenix project with necessary dependencies and configuration.

#### Subtasks
1. **Create Phoenix Project**:
   - Run `mix phx.new vault_lite --database postgres` to create a new Phoenix project.
   - Select "yes" for installing dependencies.
2. **Add Dependencies**:
   - Update `mix.exs` to include:
     - `guardian` for authentication.
     - `bcrypt_elixir` for password hashing.
     - `plug_attack` for rate-limiting.
   - Run `mix deps.get`.
3. **Configure Database**:
   - Update `config/dev.exs` and `config/test.exs` with PostgreSQL credentials.
   - Run `mix ecto.setup` to create and migrate the database.
4. **Set Up Environment Variables**:
   - Create a `.env` file for encryption keys (e.g., `ENCRYPTION_KEY`).
   - Use `dotenv` or `Application.get_env/2` to load variables.

#### AI Prompt
```plaintext
Generate a Phoenix project setup for a secrets management system called VaultLite. Include dependencies for Guardian (authentication), bcrypt_elixir (password hashing), and PlugAttack (rate-limiting) in mix.exs. Configure PostgreSQL in config/dev.exs and config/test.exs. Provide a .env file template for storing an encryption key and code to load it using Application.get_env/2. Ensure the project is set up with mix ecto.setup instructions.
```

---

### Task 2: Data Models and Database Schema
**Goal**: Define Ecto schemas for secrets, roles, and audit logs to support storage, versioning, and auditing.

#### Subtasks
1. **Create Secrets Schema**:
   - Generate a schema for secrets with fields: `key` (string), `value` (binary, encrypted), `version` (integer), `metadata` (map), and timestamps.
   - Run `mix ecto.gen.migration create_secrets`.
2. **Create Roles Schema**:
   - Generate a schema for roles with fields: `name` (string), `permissions` (array of strings), and a reference to `user`.
   - Run `mix ecto.gen.migration create_roles`.
3. **Create Audit Logs Schema**:
   - Generate a schema for audit logs with fields: `user_id` (integer), `action` (string), `secret_key` (string), `timestamp` (utc_datetime).
   - Run `mix ecto.gen.migration create_audit_logs`.
4. **Run Migrations**:
   - Implement migrations for each schema.
   - Run `mix ecto.migrate`.

#### AI Prompt
```plaintext
Generate Ecto schemas and migrations for a VaultLite project in Elixir. Create three schemas:
1. Secrets: fields key (string), value (binary for encrypted data), version (integer), metadata (map), and timestamps.
2. Roles: fields name (string), permissions (array of strings), belongs_to user, and timestamps.
3. Audit Logs: fields user_id (integer), action (string), secret_key (string), timestamp (utc_datetime).
Generate corresponding migrations using mix ecto.gen.migration. Include changesets for each schema with validations (e.g., key uniqueness, required fields).
```

---

### Task 3: Secret Management Logic
**Goal**: Implement logic for creating, updating, retrieving, and deleting secrets with encryption and versioning.

#### Subtasks
1. **Create Secret Context**:
   - Create `VaultLite.Secrets` module for secret CRUD operations.
   - Implement `create_secret/3`, `get_secret/2`, `update_secret/3`, `delete_secret/2`.
2. **Encryption/Decryption**:
   - Use `:crypto.aead_encrypt/4` and `:crypto.aead_decrypt/4` for AES-256-GCM encryption.
   - Fetch encryption key from environment variables.
3. **Versioning**:
   - Increment `version` field on update, storing new record.
   - Support retrieving specific versions via `get_secret/3`.
4. **Soft Deletion**:
   - Mark secrets as deleted (add `deleted_at` field) instead of hard deletion.

#### AI Prompt
```plaintext
Generate an Elixir module VaultLite.Secrets for managing secrets in a VaultLite project. Include functions:
- create_secret(key, value, user): Encrypts value using :crypto.aead_encrypt/4 (AES-256-GCM) and stores with version 1.
- get_secret(key, user, version \\ nil): Retrieves latest or specific version, decrypts, and returns.
- update_secret(key, value, user): Creates new version with incremented version number.
- delete_secret(key, user): Soft deletes by setting deleted_at field.
Use environment variables for encryption key. Include Ecto queries and changesets for database operations. Ensure encryption uses a secure nonce.
```

---

### Task 4: Role-Based Access Control (RBAC)
**Goal**: Implement RBAC to control access to secrets based on user roles and permissions.

#### Subtasks
1. **Create Auth Context**:
   - Create `VaultLite.Auth` module for role and permission management.
   - Implement `assign_role/2`, `check_access/3` (e.g., read, write).
2. **Define Permissions**:
   - Support permissions like `["read", "write"]` for specific paths (e.g., `secrets/api/*`).
   - Use pattern matching for path-based access checks.
3. **Integrate with Secret Operations**:
   - Check permissions in `VaultLite.Secrets` before allowing operations.
4. **User Authentication**:
   - Use `Guardian` for JWT-based authentication.
   - Generate and validate tokens for API requests.

#### AI Prompt
```plaintext
Generate an Elixir module VaultLite.Auth for role-based access control in a VaultLite project. Include:
- assign_role(user, role_data): Assigns a role with permissions to a user.
- check_access(user, secret_key, action): Verifies if user has permission (e.g., read, write) for a secret key, supporting path-based patterns (e.g., secrets/api/*).
Integrate with Guardian for JWT authentication, including token generation and validation. Update VaultLite.Secrets to check permissions before operations. Include helper functions for pattern matching on secret paths.
```

---

### Task 5: REST API Development
**Goal**: Build a RESTful API using Phoenix to expose secret and role management functionality.

#### Subtasks
1. **Generate Controllers**:
   - Create `SecretController` for secret CRUD operations.
   - Create `RoleController` for role management.
2. **Define Routes**:
   - Add routes in `router.ex`:
     ```elixir
     scope "/api", VaultLiteWeb do
       pipe_through [:api, :authenticate]
       resources "/secrets", SecretController, only: [:create, :show, :update, :delete]
       resources "/roles", RoleController, only: [:create]
       get "/secrets/:key/versions/:version", SecretController, :show_version
     end
     ```
3. **Secure Pipeline**:
   - Add `Guardian.Plug` for authentication.
   - Add `PlugAttack` for rate-limiting.
4. **Implement Controllers**:
   - Handle JSON requests/responses.
   - Call `VaultLite.Secrets` and `VaultLite.Auth` for business logic.

#### AI Prompt
```plaintext
Generate Phoenix controllers and routes for a VaultLite project. Create:
- SecretController: Handles create, show, update, delete for secrets, plus show_version for specific versions.
- RoleController: Handles role creation.
Define routes in router.ex with an /api scope, including authentication via Guardian.Plug and rate-limiting via PlugAttack. Implement JSON request/response handling and call VaultLite.Secrets and VaultLite.Auth for logic. Include error handling for unauthorized access and invalid inputs.
```

---

### Task 6: Audit Logging
**Goal**: Log all secret operations for auditability.

#### Subtasks
1. **Create Audit Context**:
   - Create `VaultLite.Audit` module for logging actions.
   - Implement `log_action/3` (user, action, secret_key).
2. **Integrate with Secret Operations**:
   - Call `log_action/3` in `VaultLite.Secrets` after each operation.
3. **Store Logs**:
   - Save logs to `audit_logs` table via Ecto.
   - Optionally, configure external logging (e.g., Sentry).

#### AI Prompt
```plaintext
Generate an Elixir module VaultLite.Audit for logging secret operations in a VaultLite project. Include:
- log_action(user, action, secret_key): Logs action to audit_logs table with user_id, action, secret_key, and timestamp.
Integrate logging into VaultLite.Secrets for create, get, update, and delete operations. Use Ecto for database storage. Provide an optional configuration for sending logs to Sentry.
```

---

### Task 7: Testing
**Goal**: Write comprehensive tests to ensure functionality and security.

#### Subtasks
1. **Unit Tests**:
   - Test `VaultLite.Secrets` for encryption, decryption, and versioning.
   - Test `VaultLite.Auth` for RBAC logic.
   - Test `VaultLite.Audit` for logging.
2. **Integration Tests**:
   - Test API endpoints for correct responses and error handling.
   - Use `Mox` for mocking external dependencies (e.g., database).
3. **Property-Based Testing**:
   - Use `StreamData` to test edge cases (e.g., invalid inputs, large secrets).

#### AI Prompt
```plaintext
Generate ExUnit tests for a VaultLite project in Elixir. Include:
- Unit tests for VaultLite.Secrets: Test encryption/decryption, versioning, and soft deletion.
- Unit tests for VaultLite.Auth: Test role assignment and access checks.
- Unit tests for VaultLite.Audit: Test logging of actions.
- Integration tests for SecretController and RoleController: Test API endpoints for CRUD operations and error handling.
Use Mox for mocking database interactions and StreamData for property-based testing of edge cases (e.g., invalid keys, large secrets).
```

---

### Task 8: Security Enhancements
**Goal**: Ensure the system is secure against common vulnerabilities.

#### Subtasks
1. **Input Validation**:
   - Use Ecto changesets to validate and sanitize inputs.
2. **Rate Limiting**:
   - Configure `PlugAttack` to limit requests per user/IP.
3. **Secure Key Management**:
   - Load encryption key from environment variables.
   - Optionally, integrate with AWS KMS (placeholder for future).
4. **TLS Configuration**:
   - Enable HTTPS in `config/prod.exs` for production.

#### AI Prompt
```plaintext
Enhance security for a VaultLite project in Elixir. Generate:
- Ecto changesets in VaultLite.Secrets and VaultLite.Auth with input validation and sanitization.
- PlugAttack configuration for rate-limiting API requests by user/IP.
- Code to load encryption key from environment variables in VaultLite.Secrets.
- HTTPS configuration for Phoenix in config/prod.exs.
Include comments explaining each security measure and a placeholder for AWS KMS integration.
```

---

### Task 9: Phoenix LiveView UI Implementation
**Goal**: Build a modern, real-time web interface using Phoenix LiveView for secret management with authentication and dashboard functionality.

#### Subtasks
1. **LiveView Setup & Configuration**:
   - Configure LiveView in `router.ex` with proper authentication pipeline.
   - Set up LiveView session handling with Guardian integration.
   - Configure live socket authentication for real-time features.
2. **Authentication UI**:
   - Create login LiveView page (`/login`) with real-time form validation.
   - Create registration LiveView page (`/register`) with instant feedback.
   - Implement logout functionality.
   - Add flash message handling for authentication feedback.
3. **Dashboard LiveView**:
   - Create main dashboard (`/dashboard`) showing user's accessible secrets.
   - Implement real-time secret listing with search and filtering.
   - Add pagination for large secret collections.
   - Show user role and permissions information.
4. **Secret Management UI**:
   - Create secret creation form with live validation.
   - Implement secret viewing with version history.
   - Add secret editing capabilities with versioning display.
   - Implement soft delete with confirmation dialogs.
   - Add metadata management interface.
5. **Real-time Features**:
   - Live updates when secrets are modified by other users.
   - Real-time audit log streaming for admin users.
   - Live permission changes notification.
   - Connection status indicators.
6. **Role & User Management UI** (Admin Only):
   - Create role creation and assignment interface.
   - User management dashboard with role visualization.
   - Permission matrix display and editing.
7. **Security & UX Enhancements**:
   - CSRF protection for all forms.
   - Rate limiting visual feedback.
   - Session timeout warnings.
   - Secure secret display (masked by default, click to reveal).
   - Copy-to-clipboard functionality with security notifications.
8. **Responsive Design**:
   - Mobile-friendly interface using Tailwind CSS.
   - Dark/light theme support.
   - Accessible design following WCAG guidelines.

#### AI Prompt
```plaintext
Generate Phoenix LiveView UI for a VaultLite secrets management system. Create:

1. Authentication LiveViews:
   - LoginLive: Real-time login form with validation, integrated with Guardian JWT
   - RegisterLive: Registration form with live password strength indicator
   - Session management and flash message handling

2. Dashboard LiveView:
   - SecretDashboardLive: Main dashboard showing user's secrets with real-time updates
   - Search, filter, and pagination functionality
   - Role-based UI elements showing different features for admin vs regular users

3. Secret Management LiveViews:
   - SecretFormLive: Create/edit secrets with live validation and metadata support
   - SecretDetailLive: View secret details, version history, and audit logs
   - Secure secret display with reveal/hide functionality and copy-to-clipboard

4. Admin LiveViews (role-based access):
   - UserManagementLive: User listing and role assignment interface
   - RoleManagementLive: Create and manage roles with permission matrix
   - AuditLogLive: Real-time audit log streaming with filtering

5. Core Features:
   - LiveView authentication using Guardian with live socket auth
   - CSRF protection and security headers
   - Real-time updates using Phoenix PubSub for multi-user environments
   - Responsive design with Tailwind CSS and dark/light theme support
   - Error handling and loading states for better UX

6. Router Configuration:
   - Set up LiveView routes with proper authentication pipelines
   - Protected routes based on user roles and permissions
   - Redirect logic for authenticated/unauthenticated users

Integration Requirements:
- Use existing VaultLite.Auth, VaultLite.Secrets, and VaultLite.Audit modules
- Maintain RBAC permission checking in all LiveViews
- Integrate with existing rate limiting and security features
- Support for real-time notifications and updates
```

#### Detailed Implementation Guide

##### Authentication Flow
1. **Unauthenticated users** → Redirect to `/login`
2. **Login success** → Redirect to `/dashboard` with JWT token in session
3. **Role-based navigation** → Different menu items based on user permissions
4. **Session management** → Auto-logout on token expiry with warning

##### LiveView Structure
```elixir
# lib/vault_lite_web/live/
├── auth_live/
│   ├── login_live.ex          # Login form with real-time validation
│   ├── register_live.ex       # Registration with password strength
│   └── login_live.html.heex   # Login template
├── dashboard_live/
│   ├── secret_dashboard_live.ex  # Main secrets dashboard
│   ├── dashboard_live.html.heex  # Dashboard template
│   └── components/               # Reusable dashboard components
├── secrets_live/
│   ├── secret_form_live.ex    # Create/edit secret forms
│   ├── secret_detail_live.ex  # Secret details and versions
│   └── secret_live.html.heex  # Secret templates
└── admin_live/
    ├── user_management_live.ex  # User and role management
    ├── audit_log_live.ex        # Real-time audit logs
    └── admin_live.html.heex     # Admin templates
```

##### Real-time Features Implementation
- **PubSub Topics**: 
  - `secrets:user:#{user_id}` - User-specific secret updates
  - `audit:admin` - Admin audit log streaming
  - `roles:updated` - Role/permission changes
- **Live Updates**: Automatic refresh when secrets are modified
- **Connection Status**: Visual indicators for WebSocket connection
- **Optimistic Updates**: Immediate UI feedback with rollback on errors

##### Security Considerations
- **CSRF Protection**: All forms include CSRF tokens
- **Session Security**: Secure session handling with Guardian
- **Data Exposure**: Secrets masked by default, reveal on user action
- **Rate Limiting**: Visual feedback when rate limits approached
- **Audit Integration**: All UI actions logged via existing audit system

##### UX/UI Features
- **Loading States**: Skeleton screens and spinners for better perceived performance
- **Error Handling**: User-friendly error messages with retry options
- **Accessibility**: ARIA labels, keyboard navigation, screen reader support
- **Responsive Design**: Mobile-first design with Tailwind CSS
- **Theme Support**: Dark/light mode with user preference persistence

---

### Task 10: Deployment
**Goal**: Deploy the application to a production environment.

#### Subtasks
1. **Dockerize Application**:
   - Create a `Dockerfile` for the Phoenix app.
   - Include PostgreSQL setup in a `docker-compose.yml`.
2. **Configure CI/CD**:
   - Set up GitHub Actions for automated testing and deployment.
3. **Deploy to Fly.io**:
   - Generate `fly.toml` for Fly.io deployment.
   - Configure environment variables for production.
4. **Monitoring**:
   - Add Prometheus and Grafana for metrics.
   - Configure Sentry for error tracking.

#### AI Prompt
```plaintext
Generate deployment configuration for a VaultLite project in Elixir. Include:
- Dockerfile for Phoenix app with PostgreSQL dependency.
- docker-compose.yml for local development with Phoenix and PostgreSQL.
- GitHub Actions workflow for CI/CD (test and deploy to Fly.io).
- fly.toml for Fly.io deployment with environment variable configuration.
- Prometheus and Grafana setup for monitoring API metrics.
- Sentry configuration for error tracking.
Ensure environment variables include ENCRYPTION_KEY and database credentials.
```

---

## Development Workflow with AI Tools
1. **Use AI for Code Generation**:
   - Copy each AI prompt into Cursor or GitHub Copilot.
   - Review generated code for correctness and adherence to Elixir conventions.
   - Use AI suggestions for autocompletion in repetitive tasks (e.g., Ecto schemas).
2. **Iterative Refinement**:
   - Ask AI to fix errors or optimize code (e.g., "Refactor this Elixir function to be more idiomatic").
   - Use AI to generate tests based on existing code (e.g., "Generate ExUnit tests for this module").
3. **Documentation**:
   - Use AI to generate docstrings and README content (e.g., "Write a README for a VaultLite project with setup and usage instructions").
4. **Debugging**:
   - Use AI to suggest fixes for test failures or runtime errors (e.g., "Fix this Ecto query error").

---

## Project Timeline
- **Week 1**: Task 1 (Setup), Task 2 (Data Models)
- **Week 2**: Task 3 (Secret Management), Task 4 (RBAC)
- **Week 3**: Task 5 (API), Task 6 (Audit Logging)
- **Week 4**: Task 7 (Testing), Task 8 (Security)
- **Week 5**: Task 9 (Phoenix LiveView UI), Task 10 (Deployment), Final Testing, and Documentation

---

## Notes
- **AI Tool Tips**:
  - Use Cursor's inline suggestions for quick fixes and autocompletion.
  - Leverage Copilot's chat feature to ask clarifying questions (e.g., "Explain this Elixir error").
  - Break prompts into smaller chunks if AI generates incomplete code.
- **Security Focus**:
  - Regularly review AI-generated code for security vulnerabilities (e.g., unescaped inputs).
  - Ensure encryption keys are never hardcoded.
- **Extensibility**:
  - Plan for future features like dynamic secrets or secret rotation by keeping modules modular.
  - Use context modules (`VaultLite.Secrets`, `VaultLite.Auth`) for clean separation of concerns.

This roadmap ensures VaultLite is built efficiently with AI assistance, leveraging Elixir's strengths for a secure, scalable secrets manager.
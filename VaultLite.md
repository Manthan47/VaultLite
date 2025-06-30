# Technical Architecture: VaultLite (HashiCorp Vault-Lite in Elixir)

## Overview
VaultLite is a secure secrets management system built in Elixir, providing encrypted storage, versioning, and role-based access control (RBAC) for sensitive data like API keys and passwords. It exposes a RESTful API for secret operations and ensures auditability and scalability. The system leverages Elixir’s concurrency model, Phoenix for APIs, and PostgreSQL for persistent storage.

---

## Architecture Components

### 1. Client Interface Layer
- **Purpose**: Provides interfaces for users and systems to interact with VaultLite.
- **Components**:
  - **REST API**: Built with Phoenix Framework, exposing endpoints for secret management (e.g., `/secrets`, `/roles`).
    - Endpoints:
      - `POST /secrets`: Create a new secret.
      - `GET /secrets/:key`: Retrieve the latest secret version.
      - `GET /secrets/:key/versions/:version`: Retrieve a specific version.
      - `PUT /secrets/:key`: Update a secret (new version).
      - `DELETE /secrets/:key`: Soft delete a secret.
      - `POST /roles`: Manage roles and permissions.
  - **CLI (Optional)**: Built using Elixir’s `escript` for local secret management.
  - **Web UI (Optional)**: Built with Phoenix LiveView for a user-friendly interface.
- **Security**:
  - HTTPS for all communications.
  - Authentication via JWT (using `Guardian`) or opaque tokens.
  - Rate-limiting with `PlugAttack` to prevent abuse.
- **Technologies**: Phoenix, Plug, Guardian, Phoenix LiveView (optional).

### 2. Application Layer
- **Purpose**: Handles business logic, including secret management, RBAC, and auditing.
- **Components**:
  - **Secret Management**:
    - Encrypts/decrypts secrets using `:crypto` (AES-256-GCM).
    - Manages versioning by storing each secret update as a new database record.
    - Context module (e.g., `Vault.Secrets`) for CRUD operations.
  - **RBAC**:
    - Defines roles (e.g., admin, reader, writer) and permissions (e.g., read, write).
    - Checks access policies using pattern matching and guard clauses.
    - Context module (e.g., `Vault.Auth`) for role and permission management.
  - **Audit Logging**:
    - Logs all actions (create, read, update, delete) to a database or external system.
    - Context module (e.g., `Vault.Audit`) for logging.
- **Concurrency**:
  - Uses GenServers for managing encryption/decryption tasks.
  - Leverages ETS for caching frequently accessed secrets (with TTL).
- **Technologies**: Elixir, GenServer, ETS, `:crypto`, `bcrypt_elixir` or `argon2_elixir` for password hashing.

### 3. Data Layer
- **Purpose**: Stores encrypted secrets, roles, permissions, and audit logs.
- **Components**:
  - **Database**: PostgreSQL, managed via Ecto.
    - **Secrets Table**:
      ```elixir
      schema "secrets" do
        field :key, :string            # e.g., "api_key"
        field :value, :binary          # Encrypted secret
        field :version, :integer       # Version number
        field :metadata, :map          # e.g., created_by, updated_at
        timestamps()
      end
      ```
    - **Roles Table**:
      ```elixir
      schema "roles" do
        field :name, :string           # e.g., "admin"
        field :permissions, {:array, :string}  # e.g., ["read", "write"]
        belongs_to :user, User
      end
      ```
    - **Audit Logs Table**:
      ```elixir
      schema "audit_logs" do
        field :user_id, :integer
        field :action, :string         # e.g., "read"
        field :secret_key, :string
        field :timestamp, :utc_datetime
      end
      ```
  - **Encryption**:
    - Secrets are encrypted using `:crypto.aead_encrypt/4` with AES-256-GCM.
    - Encryption keys stored in environment variables or a Key Management Service (KMS).
  - **Caching**:
    - ETS for in-memory caching of decrypted secrets.
    - Optional Redis integration for distributed caching.
- **Technologies**: PostgreSQL, Ecto, ETS, Redix (optional).

### 4. Security Layer
- **Purpose**: Ensures confidentiality, integrity, and availability of secrets.
- **Components**:
  - **Encryption at Rest**: Secrets encrypted before storage using `:crypto`.
  - **Encryption in Transit**: TLS for all API communications.
  - **Authentication**: JWT or opaque tokens via `Guardian` or `Pow`.
  - **Authorization**: RBAC enforced at the application layer.
  - **Key Management**: Encryption keys stored securely (e.g., environment variables or AWS KMS).
  - **Input Validation**: Ecto changesets for sanitizing inputs.
  - **Rate Limiting**: `PlugAttack` to prevent brute-force attacks.
  - **Audit Logging**: Tamper-proof logs for all actions.
- **Technologies**: `:crypto`, `bcrypt_elixir`, `PlugAttack`, TLS.

### 5. Infrastructure Layer
- **Purpose**: Supports deployment, scaling, and monitoring.
- **Components**:
  - **Deployment**: Docker containers deployed on Fly.io, Gigalixir, or AWS ECS.
  - **Clustering**: `libcluster` or `Horde` for distributed Elixir nodes.
  - **Monitoring**: Prometheus and Grafana for metrics, Sentry for error tracking.
  - **Backup**: Regular database backups with encryption.
  - **CI/CD**: GitHub Actions or similar for automated testing and deployment.
- **Technologies**: Docker, Fly.io, `libcluster`, Prometheus, Grafana, Sentry.

---

## System Interactions
1. **Client Request**:
   - A client (user or application) sends an authenticated request to the REST API (e.g., `POST /secrets`).
   - The request is validated (authentication, rate-limiting) by the Phoenix pipeline.

2. **Authentication and Authorization**:
   - The `Guardian` plug verifies the JWT token.
   - The RBAC module checks if the user’s role allows the requested action.

3. **Secret Processing**:
   - The application layer encrypts/decrypts the secret using `:crypto`.
   - The secret is stored/retrieved from PostgreSQL via Ecto.
   - Versioning is handled by incrementing the version field in the secrets table.

4. **Audit Logging**:
   - The action (e.g., create, read) is logged to the audit_logs table.
   - Logs are optionally sent to an external system (e.g., Elasticsearch).

5. **Response**:
   - The Phoenix controller returns a JSON response with the result or error.

---

## Data Flow Diagram
```
[Client] --> [REST API (Phoenix)] --> [Authentication (Guardian)]
                                    --> [RBAC (Vault.Auth)]
                                    --> [Secret Management (Vault.Secrets)]
                                    --> [Database (PostgreSQL)]
                                    --> [Audit Logging (Vault.Audit)]
                                    --> [Cache (ETS/Redis)]
```

---

## Security Considerations
- **Encryption**: AES-256-GCM for secrets, TLS 1.3 for network traffic.
- **Key Management**: Use environment variables or a KMS for encryption keys.
- **Access Control**: Fine-grained RBAC with least privilege principle.
- **Auditability**: Immutable logs for all actions.
- **Compliance**: Align with GDPR, HIPAA, or SOC 2 if required.
- **Vulnerabilities**: Mitigate OWASP Top 10 (e.g., injection, broken authentication).

---

## Scalability and Performance
- **Concurrency**: Elixir’s Actor model (GenServer) handles concurrent requests.
- **Caching**: ETS/Redis for fast access to frequently used secrets.
- **Clustering**: `libcluster` for distributing workload across nodes.
- **Database Optimization**: Indexes on `secrets.key` and `audit_logs.timestamp`.
- **Load Balancing**: Use a reverse proxy (e.g., Nginx) for API traffic.

---

## Technologies
- **Language**: Elixir
- **Framework**: Phoenix (REST API), Phoenix LiveView (optional UI)
- **Database**: PostgreSQL (via Ecto)
- **Authentication**: Guardian or Pow
- **Cryptography**: `:crypto`, `bcrypt_elixir`, `argon2_elixir`
- **Caching**: ETS, Redix (optional)
- **Clustering**: `libcluster`, Horde
- **Monitoring**: Prometheus, Grafana, Sentry
- **Deployment**: Docker, Fly.io, or AWS ECS

---

## Future Enhancements
- **Dynamic Secrets**: Generate temporary credentials (e.g., database access).
- **Secret Rotation**: Automate key rotation with policies.
- **Multi-Tenancy**: Support isolated namespaces for different teams.
- **External KMS**: Integrate with AWS KMS or HashiCorp Vault for key management.
- **gRPC Support**: Add gRPC alongside REST for high-performance clients.

---

## Assumptions and Constraints
- **Single Region**: Assumes deployment in a single region for simplicity.
- **No External KMS**: Uses environment variables for encryption keys in the prototype.
- **Limited UI**: Focuses on API; Web UI is optional.
- **Compliance**: Not production-ready for regulated environments without additional auditing.

---

## Deployment Diagram
```
[Client] --> [Nginx (Load Balancer)] --> [Phoenix App (Elixir Nodes)]
                                           --> [PostgreSQL]
                                           --> [Redis (Optional)]
                                           --> [Sentry/Elasticsearch (Logs)]
```

This architecture provides a secure, scalable, and maintainable foundation for VaultLite, leveraging Elixir’s strengths for concurrency and fault tolerance. It can be extended with additional features as needed.
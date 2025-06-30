# Personal Secrets Implementation

This document describes the implementation of personal secrets functionality alongside the existing role-based secrets in VaultLite.

## Overview

The application now supports two types of secrets:

1. **Role-based Secrets**: Accessible based on user roles and permissions (existing functionality)
2. **Personal Secrets**: Private secrets that can only be accessed by the user who created them

## Database Changes

### Migration: `add_secret_type_and_owner_to_secrets`

Added two new fields to the `secrets` table:
- `secret_type`: String field with values "role_based" or "personal" (default: "role_based")
- `owner_id`: Foreign key reference to users table (nullable, only used for personal secrets)

Added appropriate indexes for efficient querying.

## Schema Updates

### Secret Schema (`lib/vault_lite/secret.ex`)

- Added `secret_type` field with validation (must be "role_based" or "personal")
- Added `owner_id` belongs_to association
- Added validation to ensure personal secrets have an owner_id
- Added query helpers for filtering by secret type and owner

## Context Updates

### Secrets Context (`lib/vault_lite/secrets.ex`)

- Updated `create_secret/5` to accept a secret_type parameter
- Modified authorization logic to handle both secret types:
  - Personal secrets: Anyone can create, only owner can read/update/delete
  - Role-based secrets: Use existing role-based authorization
- Updated `list_secrets/2` to return both role-based and personal secrets
- Enhanced audit logging to include secret type information

## UI Updates

### Secret Form (`lib/vault_lite_web/live/secrets_live/secret_form_live.ex`)

- Added radio button toggle for selecting secret type (role_based vs personal)
- Dynamic help text based on selected secret type
- Type selection only available when creating new secrets (not when editing)
- Form validation and submission updated to handle secret type

### Dashboard (`lib/vault_lite_web/live/dashboard_live/secret_dashboard_live.ex`)

- Added filter buttons to view all secrets, personal only, or role-based only
- Added visual badges to distinguish secret types
- Different icons for personal (user icon) vs role-based (key icon) secrets
- Enhanced empty states with type-specific messaging

### Secret Detail View (`lib/vault_lite_web/live/secrets_live/secret_detail_live.ex`)

- Added secret type display with badges
- Shows ownership information (personal vs role-based)
- Version history includes secret type information
- Clear visual distinction between secret types

## Features

### Creating Secrets

1. Navigate to "New Secret" from the dashboard
2. Choose between "Role-based Secret" and "Personal Secret" using radio buttons
3. Fill in the secret details
4. Personal secrets are automatically owned by the current user
5. Role-based secrets follow existing permission rules

### Viewing Secrets

1. Dashboard shows all accessible secrets (both personal and role-based)
2. Filter options: "All Secrets", "Personal", "Role-based"
3. Visual badges and icons distinguish secret types
4. Personal secrets show "Only you can access this secret" indicator

### Authorization

- **Personal Secrets**: 
  - Create: Any authenticated user
  - Read/Update/Delete: Only the owner
- **Role-based Secrets**: 
  - All operations: Based on existing role permissions

### Search and Filtering

- Search works across both secret types
- Filter buttons allow viewing specific secret types
- Combined search and filter functionality

## Security Considerations

- Personal secrets are completely isolated - no sharing mechanism
- Existing role-based authorization remains unchanged
- Owner validation ensures personal secrets can't be accessed by other users
- Audit logging tracks secret type for all operations

## Backward Compatibility

- Existing secrets are automatically marked as "role_based" via migration default
- No changes to existing role-based secret functionality
- All existing APIs and workflows continue to work

## Testing

To test the implementation:

1. Start the server: `mix phx.server`
2. Log in to the application
3. Create a new secret and select "Personal Secret"
4. Verify it appears in the dashboard with proper badges
5. Test filtering functionality
6. Verify authorization (personal secrets only visible to owner)
7. Create role-based secrets and ensure existing functionality works

## File Changes

- **Database**: `priv/repo/migrations/20250630115202_add_secret_type_and_owner_to_secrets.exs`
- **Schema**: `lib/vault_lite/secret.ex`
- **Context**: `lib/vault_lite/secrets.ex`
- **Form**: `lib/vault_lite_web/live/secrets_live/secret_form_live.ex`
- **Dashboard**: `lib/vault_lite_web/live/dashboard_live/secret_dashboard_live.ex`
- **Detail View**: `lib/vault_lite_web/live/secrets_live/secret_detail_live.ex`

This implementation provides a clean separation between personal and role-based secrets while maintaining all existing functionality and security measures. 
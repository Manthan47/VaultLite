# VaultLite Complete User Guide

A Comprehensive Guide to Understanding, Using, and Navigating VaultLite

---

## Table of Contents

1. [What is VaultLite?](#what-is-vaultlite)
2. [Key Features](#key-features)
3. [Getting Started](#getting-started)
4. [User Interface Guide](#user-interface-guide)
5. [Secret Management](#secret-management)
6. [Role-Based Access Control](#role-based-access-control)
7. [Admin Features](#admin-features)
8. [API Usage](#api-usage)
9. [Security Features](#security-features)
10. [Troubleshooting](#troubleshooting)

---

## What is VaultLite?

VaultLite is a **secure secrets management system** built with Elixir and Phoenix that provides encrypted storage, versioning, and role-based access control for sensitive data like API keys, passwords, database credentials, and other confidential information.

### Core Purpose
- **Centralized Secret Storage**: Store all your sensitive data in one secure location
- **Access Control**: Control who can access which secrets through role-based permissions
- **Audit Trail**: Track every action for compliance and security monitoring
- **Version Management**: Keep track of secret changes with full version history
- **Enterprise Security**: Military-grade encryption and security features

### Who Should Use VaultLite?
- **Development Teams**: Managing API keys, database credentials, and environment variables
- **DevOps Engineers**: Storing deployment secrets and infrastructure credentials
- **System Administrators**: Managing user access and monitoring security
- **Organizations**: Requiring compliance, audit trails, and centralized secret management

---

## Key Features

### 🔐 Security Features
- **AES-256-GCM Encryption**: Military-grade encryption for all secret values
- **TLS/HTTPS**: All communications encrypted in transit
- **JWT Authentication**: Secure token-based authentication system
- **Rate Limiting**: Protection against abuse and DDoS attacks
- **Security Headers**: Comprehensive protection against web vulnerabilities
- **Input Validation**: Protection against injection attacks and malicious data

### 📝 Secret Management
- **Encrypted Storage**: All secrets encrypted before storage
- **Version Control**: Complete version history with ability to retrieve any version
- **Two Secret Types**:
  - **Personal Secrets**: Private secrets only accessible by the owner
  - **Role-based Secrets**: Shared secrets accessible based on user permissions
- **Metadata Support**: Attach custom metadata to secrets for organization
- **Soft Deletion**: Safe secret deletion with preservation for audit trails

### 👥 Access Control
- **Role-Based Access Control (RBAC)**: Granular permissions system
- **User Management**: Create and manage user accounts
- **Permission Levels**: Read, write, delete, and admin permissions
- **Path-based Access**: Control access to specific secret patterns
- **Admin Controls**: Comprehensive administration features

### 📊 Monitoring & Compliance
- **Comprehensive Audit Logging**: Every action tracked and logged
- **Real-time Monitoring**: Live monitoring of all activities
- **Security Analytics**: Detect suspicious patterns and activities
- **Compliance Support**: Built for SOC 2, GDPR, and other compliance requirements

### 🌐 Interface Options
- **Modern Web Interface**: Phoenix LiveView real-time web application
- **RESTful API**: Complete API for programmatic access
- **Real-time Updates**: Live updates across multiple users and sessions
- **Mobile Responsive**: Works seamlessly on desktop, tablet, and mobile

---

## Getting Started

### Prerequisites
Before using VaultLite, ensure you have:
- A VaultLite instance running (see SETUP.md for installation)
- Valid user credentials
- Appropriate permissions for your intended actions

### First Time Setup

#### For Organizations
1. **Bootstrap Admin Account**: Use one of these methods:
   ```bash
   # Option 1: Database seeding
   mix run priv/repo/seeds.exs
   
   # Option 2: Mix task (recommended for production)
   mix vault_lite.admin create --username admin --email admin@company.com
   
   # Option 3: Bootstrap API endpoint
   curl -X POST http://localhost:4000/api/bootstrap/setup \
     -H "Content-Type: application/json" \
     -d '{"admin": {"username": "admin", "email": "admin@company.com", "password": "SecurePassword123!"}}'
   ```

#### For Individual Users
1. **Navigate to Registration**: Go to `/register` on your VaultLite instance
2. **Create Account**: Fill in username, email, and password
3. **Login**: Use `/login` to access the dashboard

### Accessing VaultLite

#### Web Interface
- **URL**: `http://your-vaultlite-instance:4000`
- **Login Page**: `/login`
- **Dashboard**: `/dashboard` (after authentication)

#### API Access
- **Base URL**: `http://your-vaultlite-instance:4000/api`
- **Authentication**: Required for all endpoints except login/register
- **Format**: JSON requests and responses

---

## User Interface Guide

### Navigation Overview

#### Main Navigation (Authenticated Users)
```
VaultLite Dashboard
├── Dashboard (Home)
├── Secrets
│   ├── View All Secrets
│   ├── Create New Secret
│   └── Search/Filter Secrets
├── Profile Settings
└── Logout
```

#### Admin Navigation (Admin Users Only)
```
Admin Section
├── User Management
├── Role Management
├── Audit Logs
└── System Settings
```

### Dashboard Page (`/dashboard`)

The main dashboard is your central hub for secret management.

#### Dashboard Features

1. **Search Bar**
   - **Location**: Top of the page
   - **Function**: Real-time search across all accessible secrets
   - **Usage**: Type any part of a secret key to filter results

2. **Filter Buttons**
   - **All Secrets**: View all accessible secrets (personal + role-based)
   - **Personal**: View only your personal secrets
   - **Role-based**: View only role-based secrets you have access to

3. **Secret List**
   - **Display**: Card-based layout showing secret information
   - **Information Shown**:
     - Secret key (name)
     - Secret type (Personal/Role-based with icons)
     - Version number
     - Created/Modified dates
     - Metadata preview
   - **Actions Available**: View, Edit, Delete (based on permissions)

4. **Quick Actions**
   - **New Secret Button**: Create a new secret
   - **Refresh Button**: Manually refresh the secret list

---

## Secret Management

### Understanding Secret Types

VaultLite supports two types of secrets:

#### Personal Secrets
- **Access**: Only accessible by the user who created them
- **Use Case**: Personal API keys, individual credentials, private notes
- **Sharing**: Cannot be shared with other users
- **Icon**: User icon (👤)

#### Role-based Secrets
- **Access**: Based on user roles and permissions
- **Use Case**: Shared team credentials, production keys, common resources
- **Sharing**: Controlled by role-based access control
- **Icon**: Key icon (🔑)

### Creating Secrets

#### Using the Web Interface

1. **Navigate to Creation**
   - From Dashboard: Click "New Secret" button
   - Direct URL: `/secrets/new`

2. **Fill Secret Form**
   ```
   Secret Type: [Personal] [Role-based] (Radio buttons)
   Secret Key: my-api-key (Required)
   Secret Value: actual-secret-value (Required)
   ```

3. **Add Metadata (Optional)**
   - Click "Add Metadata" to include key-value pairs
   - Examples: environment=production, team=backend, expires=2024-12-31

4. **Submit**
   - Click "Create Secret" to save
   - You'll be redirected to the secret detail page

#### Using the API

```bash
# Create a personal secret
curl -X POST http://localhost:4000/api/secrets \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "my-api-key",
    "value": "secret-value-here",
    "secret_type": "personal",
    "metadata": {
      "environment": "development",
      "created_by": "john_doe"
    }
  }'
```

### Viewing Secrets

#### Secret Detail Page (`/secrets/:key`)

Access by clicking on any secret in the dashboard or navigating to `/secrets/secret-key-name`.

**Information Displayed:**
- Secret key (name)
- Secret type with badge
- Current version number
- Creation and modification dates
- Metadata (if any)
- Secret value (click to reveal)

**Available Actions:**
- **Reveal/Hide Value**: Toggle secret visibility
- **Copy to Clipboard**: Quick copy button
- **Edit Secret**: Modify the secret (creates new version)
- **View Versions**: See version history
- **Delete Secret**: Soft delete (with confirmation)

#### Security Features
- **Masked by Default**: Secret values are hidden until explicitly revealed
- **Session Timeout**: Values are re-masked after inactivity
- **Copy Protection**: Clipboard is cleared after a short time
- **Access Logging**: All view actions are logged for audit

---

## Role-Based Access Control

### Understanding RBAC in VaultLite

VaultLite uses a role-based access control system where:
- **Users** have **Roles**
- **Roles** have **Permissions**
- **Permissions** control access to **Secrets**

### Permission Types

#### Standard Permissions
- **read**: View secret values and metadata
- **write**: Create and update secrets
- **delete**: Remove secrets
- **admin**: Full administrative access

#### Permission Scope
- **Personal Secrets**: Automatically accessible only by owner
- **Role-based Secrets**: Access controlled by role permissions

### For Regular Users

#### Viewing Your Roles
- **Location**: Profile section or dashboard sidebar
- **Information**: Shows assigned roles and their permissions
- **Access**: Read-only for regular users

#### Understanding Access
- **Green Badge**: You have access to this secret
- **Red Badge**: Access denied
- **Permission Required**: Specific action not allowed

---

## Admin Features

### Admin Dashboard Overview

Admin users have access to additional features for system management:

#### Navigation
```
Admin Section
├── User Management (/admin/users)
├── Role Management (/admin/roles)
└── Audit Logs (/admin/audit)
```

### User Management (`/admin/users`)

#### Features Available

1. **User Listing**
   - View all system users
   - Search by username or email
   - Filter by active/inactive status
   - Sort by various criteria

2. **User Details**
   - View complete user information
   - See assigned roles and permissions
   - View user activity summary
   - Access user audit trail

3. **User Actions**
   - Create new user accounts
   - Assign/revoke roles
   - Activate/deactivate accounts
   - Reset user passwords
   - View user login history

### Role Management (`/admin/roles`)

#### Features Available

1. **Role Creation**
   - Define role names and descriptions
   - Set permission combinations
   - Configure path-based access patterns
   - Set role hierarchy

2. **Permission Matrix**
   - Visual permission overview
   - Quick permission modifications
   - Bulk permission updates
   - Permission conflict detection

### Audit Logs (`/admin/audit`)

#### Overview
The audit logs provide comprehensive tracking of all system activities for security monitoring and compliance.

#### Features Available

1. **Statistics Dashboard**
   - Total log entries
   - Active users count
   - Most accessed secrets
   - Common actions summary

2. **Advanced Filtering**
   - Filter by action type (create, read, update, delete, list)
   - Filter by user ID
   - Filter by secret key
   - Date range filtering
   - Real-time search

---

## API Usage

### Authentication

#### Getting Started with API

1. **Obtain JWT Token**
   ```bash
   # Login to get token
   curl -X POST http://localhost:4000/api/auth/login \
     -H "Content-Type: application/json" \
     -d '{
       "identifier": "username_or_email",
       "password": "your_password"
     }'
   ```

2. **Use Token in Requests**
   ```bash
   # Include token in Authorization header
   curl -X GET http://localhost:4000/api/secrets \
     -H "Authorization: Bearer YOUR_JWT_TOKEN"
   ```

### Secret Management API

#### Create Secret
```bash
POST /api/secrets
Content-Type: application/json
Authorization: Bearer TOKEN

{
  "key": "database_password",
  "value": "super_secure_password",
  "secret_type": "role_based",
  "metadata": {
    "environment": "production",
    "database": "primary"
  }
}
```

#### Get Secret (Latest Version)
```bash
GET /api/secrets/database_password
Authorization: Bearer TOKEN
```

#### Update Secret (Creates New Version)
```bash
PUT /api/secrets/database_password
Content-Type: application/json
Authorization: Bearer TOKEN

{
  "value": "new_password_value",
  "metadata": {
    "environment": "production",
    "updated_reason": "Security rotation"
  }
}
```

#### List All Accessible Secrets
```bash
GET /api/secrets?page=1&limit=10
Authorization: Bearer TOKEN
```

#### Delete Secret (Soft Delete)
```bash
DELETE /api/secrets/database_password
Authorization: Bearer TOKEN
```

---

## Security Features

### Encryption and Data Protection

#### Data at Rest
- **Algorithm**: AES-256-GCM encryption
- **Key Management**: Environment-based encryption keys
- **Scope**: All secret values encrypted before database storage

#### Data in Transit
- **TLS/HTTPS**: All communications encrypted with TLS 1.2/1.3
- **Certificate Validation**: Proper SSL certificate verification
- **Secure Headers**: Comprehensive security headers implemented

### Authentication and Session Management

#### JWT Token Security
- **Algorithm**: HS256 with secure secret keys
- **Expiration**: Configurable token lifetime
- **Refresh**: Token refresh capabilities
- **Invalidation**: Proper logout and token invalidation

### Rate Limiting and Attack Prevention

#### Multi-layer Rate Limiting
- **IP-based Limiting**: Requests per IP address
- **User-based Limiting**: Different limits for admin vs regular users
- **Endpoint-specific Limits**: Custom limits per API endpoint
- **Adaptive Throttling**: Dynamic limit reduction for suspicious activity

---

## Troubleshooting

### Common Issues and Solutions

#### Authentication Problems

**Issue**: Cannot login with correct credentials
- **Solution**: Verify account is active, try password reset, clear browser cache

**Issue**: JWT token expired or invalid
- **Solution**: Re-authenticate to get new token, check token format

#### Permission and Access Issues

**Issue**: Cannot access expected secrets
- **Solution**: Check assigned roles, verify secret type, contact admin

**Issue**: Cannot perform actions (create, edit, delete)
- **Solution**: Verify permissions, check role assignment, contact admin

#### Interface and Navigation Issues

**Issue**: Dashboard not loading or showing errors
- **Solution**: Refresh page, clear cache, check browser console, try different browser

### Getting Help

#### Self-Service Resources
1. **This User Guide**: Complete documentation of features and usage
2. **API Documentation**: Complete API reference in README.md
3. **Setup Guide**: Installation and configuration in SETUP.md

#### Contacting Support
1. **System Administrator**: For permission and access issues
2. **Technical Support**: For bugs and technical problems
3. **Security Team**: For security concerns or incidents

---

## Conclusion

VaultLite provides a comprehensive, secure solution for secrets management with enterprise-grade security features and user-friendly interfaces. Whether you're using the web interface for daily secret management or the API for automated systems, VaultLite offers the tools and security controls needed to protect your sensitive data.

### Key Takeaways

1. **Security First**: All secrets are encrypted with military-grade encryption
2. **Access Control**: Granular permissions ensure proper access control
3. **Audit Trail**: Complete tracking of all activities for compliance
4. **User-Friendly**: Modern web interface with real-time features
5. **API-Ready**: Complete RESTful API for automation and integration

---

*VaultLite - Secure, Simple, Scalable Secrets Management* 
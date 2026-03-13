# Legal Data API

> Use backlogmd for task management

## Setup

```bash
bundle install
bin/rails db:create db:migrate
```

### Create user and API keys

```bash
bundle exec rake db:seed_user
```

This creates an admin user with two API keys: one **admin** (full CRUD) and one **read-only** (GET only).

### API Key Management

```bash
# List all active keys
bundle exec rake api_keys:list

# Create a read-only key
bundle exec rake api_keys:create_read[user@example.com]

# Create an admin key
bundle exec rake api_keys:create_admin[user@example.com]

# Rotate all keys for a user (deactivates old, creates new with same roles)
bundle exec rake api_keys:rotate[user@example.com]

# Rotate keys for all users
bundle exec rake api_keys:rotate
```

## Authentication & Authorization

All endpoints require an API key in the `X-API-KEY` header:

```
X-API-KEY: your_api_key_here
```

### API Key Roles

| Role | Permissions | Use case |
|------|-------------|----------|
| `admin` | Full CRUD (GET, POST, PUT, PATCH, DELETE) | Scraping, data ingestion, management |
| `read` | Read-only (GET) | Application frontend, public queries |

A read-only key attempting a write operation receives `403 Forbidden`.

## Endpoints

### Lawyer Endpoints

```
GET  /api/v1/lawyer/:oab              # Lookup by OAB ID (e.g. PR_54159)
GET  /api/v1/lawyer/:oab/debug        # Extended debug info
GET  /api/v1/lawyer/state/:state/last # Last registered lawyer by state
POST /api/v1/lawyer/create            # Create lawyer (admin only)
POST /api/v1/lawyer/:oab/update       # Update lawyer (admin only)
POST /api/v1/lawyer/:oab/crm          # Update CRM data (admin only)
```

### Society Endpoints

```
GET    /api/v1/society/:inscricao        # Lookup by inscricao
POST   /api/v1/society/create            # Create society (admin only)
POST   /api/v1/society/:inscricao/update # Update society (admin only)
DELETE /api/v1/society/:inscricao        # Delete society (admin only)
```

### Lawyer-Society Relationship Endpoints

```
GET    /api/v1/lawyer_societies/:id   # Show relationship
POST   /api/v1/lawyer_societies       # Create relationship (admin only)
PATCH  /api/v1/lawyer_societies/:id   # Update relationship (admin only)
DELETE /api/v1/lawyer_societies/:id   # Delete relationship (admin only)
```

## Security

- **Authentication**: API key via `X-API-KEY` header
- **Authorization**: Role-based (admin/read) enforced at controller level
- **Rate limiting, IP blocking, CORS, SSL, security headers**: Handled by NGINX

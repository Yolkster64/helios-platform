# HELIOS Platform - Configuration Guide

## Overview

This guide provides comprehensive information about configuring HELIOS Platform for different environments and use cases.

## Table of Contents

1. [Configuration Files](#configuration-files)
2. [Environment Settings](#environment-settings)
3. [API Configuration](#api-configuration)
4. [Security Configuration](#security-configuration)
5. [Database Configuration](#database-configuration)
6. [Caching Configuration](#caching-configuration)
7. [Logging Configuration](#logging-configuration)
8. [Cloud Provider Configuration](#cloud-provider-configuration)

---

## Configuration Files

### File Locations

| Environment | Location |
|-------------|----------|
| **Windows** | `%APPDATA%\HELIOS\config.yaml` |
| **Linux** | `~/.helios/config.yaml` or `/etc/helios/config.yaml` |
| **macOS** | `~/Library/Application Support/HELIOS/config.yaml` |
| **Development** | `.env.local` in project root |

### Configuration File Format

HELIOS uses YAML for configuration files. Basic example:

```yaml
app:
  name: "HELIOS Platform"
  environment: "production"
  debug: false

api:
  endpoint: "https://api.helios.cloud"
  timeout: 30000
  max_retries: 3

database:
  connection_string: "Server=localhost;Database=helios;User Id=admin;"
  pool_size: 10
  query_timeout: 30

security:
  tls_version: "1.3"
  require_https: true
```

---

## Environment Settings

### Development Environment

```yaml
app:
  environment: "development"
  debug: true
  
api:
  endpoint: "http://localhost:5000"
  timeout: 60000
  max_retries: 5

logging:
  level: "DEBUG"
  console_output: true
  file_output: false

cache:
  enabled: false
```

### Staging Environment

```yaml
app:
  environment: "staging"
  debug: false
  
api:
  endpoint: "https://staging-api.helios.cloud"
  timeout: 45000
  max_retries: 3

logging:
  level: "INFO"
  console_output: false
  file_output: true
  retention_days: 7

cache:
  enabled: true
  ttl: 1800
```

### Production Environment

```yaml
app:
  environment: "production"
  debug: false
  
api:
  endpoint: "https://api.helios.cloud"
  timeout: 30000
  max_retries: 2

logging:
  level: "WARNING"
  console_output: false
  file_output: true
  retention_days: 30

cache:
  enabled: true
  ttl: 3600
  distributed: true
```

### Setting Environment Variables

```bash
# Windows
set HELIOS_ENV=production
set HELIOS_API_ENDPOINT=https://api.helios.cloud

# Linux/macOS
export HELIOS_ENV=production
export HELIOS_API_ENDPOINT=https://api.helios.cloud

# Using Docker
docker run -e HELIOS_ENV=production helios-platform
```

---

## API Configuration

### Basic API Settings

```yaml
api:
  # API endpoint URL
  endpoint: "https://api.helios.cloud"
  
  # Request timeout in milliseconds
  timeout: 30000
  
  # Maximum retry attempts
  max_retries: 3
  
  # Retry delay in milliseconds
  retry_delay: 1000
  
  # Rate limiting
  rate_limit:
    enabled: true
    requests_per_minute: 1000
    burst_size: 50
```

### API Gateway Configuration

```yaml
api_gateway:
  # Port to listen on
  port: 5000
  
  # Bind address
  bind: "0.0.0.0"
  
  # Connection pool
  connection_pool:
    size: 100
    timeout: 30000
  
  # Request validation
  validation:
    strict_mode: true
    max_payload_size: 10485760  # 10MB
```

### API Versioning

```yaml
api:
  versions:
    current: "v1"
    supported:
      - "v1"
      - "v2"
    deprecated:
      - "v0"
```

---

## Security Configuration

### Authentication & Authorization

```yaml
security:
  # JWT token settings
  jwt:
    enabled: true
    secret: "${JWT_SECRET}"  # Use environment variable
    algorithm: "HS256"
    expiration: 3600  # seconds
    refresh_token_expiration: 604800  # 7 days
  
  # OAuth2 settings
  oauth2:
    enabled: true
    providers:
      - name: "azure"
        client_id: "${AZURE_CLIENT_ID}"
        client_secret: "${AZURE_CLIENT_SECRET}"
      - name: "google"
        client_id: "${GOOGLE_CLIENT_ID}"
        client_secret: "${GOOGLE_CLIENT_SECRET}"
  
  # API Key management
  api_keys:
    enabled: true
    rotation_days: 90
```

### TLS/SSL Configuration

```yaml
security:
  tls:
    # Minimum TLS version
    min_version: "1.3"
    
    # Certificate paths
    certificate:
      cert_file: "/etc/helios/certs/server.crt"
      key_file: "/etc/helios/certs/server.key"
    
    # HSTS settings
    hsts:
      enabled: true
      max_age: 31536000
      include_subdomains: true
```

### Password Policy

```yaml
security:
  password_policy:
    min_length: 12
    require_uppercase: true
    require_lowercase: true
    require_numbers: true
    require_special: true
    expiration_days: 90
    history_count: 5
```

### Two-Factor Authentication

```yaml
security:
  two_factor_auth:
    enabled: true
    methods:
      - "totp"      # Time-based One-Time Password
      - "email"     # Email verification
      - "sms"       # SMS verification
    enforcement: "required"  # required or optional
```

---

## Database Configuration

### Connection Settings

```yaml
database:
  # Database type
  type: "sql_server"  # mssql, postgresql, mysql, sqlite
  
  # Connection details
  server: "localhost"
  port: 1433
  database: "helios"
  username: "${DB_USER}"
  password: "${DB_PASSWORD}"
  
  # Connection string (alternative to individual settings)
  connection_string: "Server=localhost;Database=helios;User Id=admin;Password=${DB_PASSWORD};"
  
  # Connection pool
  pool:
    size: 20
    min_size: 5
    max_wait_time: 30000
    timeout: 30000
```

### Migration Settings

```yaml
database:
  migrations:
    enabled: true
    auto_migrate: true
    # Script location relative to installation directory
    script_directory: "migrations"
    # Versions to apply
    apply_version: "latest"
```

### Backup Configuration

```yaml
database:
  backup:
    enabled: true
    frequency: "daily"  # hourly, daily, weekly, monthly
    retention_days: 30
    location: "/var/backups/helios"
    compression: true
```

---

## Caching Configuration

### Redis Cache

```yaml
cache:
  enabled: true
  type: "redis"
  
  redis:
    # Connection settings
    server: "localhost"
    port: 6379
    database: 0
    password: "${REDIS_PASSWORD}"
    
    # Timeouts
    connection_timeout: 5000
    command_timeout: 3000
    
    # SSL
    ssl: true
    ssl_host: "redis.example.com"
```

### Memory Cache

```yaml
cache:
  enabled: true
  type: "memory"
  
  memory:
    # Maximum cache size in MB
    max_size: 500
    
    # TTL settings
    default_ttl: 3600
    max_ttl: 86400
```

### Cache Policies

```yaml
cache:
  policies:
    # Cache by default
    default_mode: "write-through"  # write-through or write-back
    
    # Cache expiration
    ttl:
      default: 3600
      api_responses: 600
      user_data: 1800
```

---

## Logging Configuration

### Log Levels

```yaml
logging:
  # Default level: TRACE, DEBUG, INFO, WARNING, ERROR, CRITICAL
  level: "INFO"
  
  # Component-specific levels
  components:
    database: "DEBUG"
    api_gateway: "INFO"
    security: "WARNING"
```

### Log Output

```yaml
logging:
  console:
    enabled: true
    format: "json"  # text or json
    include_timestamp: true
    include_level: true
    colorize: true

  file:
    enabled: true
    path: "/var/log/helios"
    filename: "helios.log"
    format: "json"
    max_size: 104857600  # 100MB
    max_files: 10
    compression: true
```

### Structured Logging

```yaml
logging:
  structured:
    enabled: true
    format: "json"
    
    fields:
      # Include correlation ID for tracing
      correlation_id: true
      # Include request/response timing
      duration: true
      # Include user information
      user_id: true
      # Include request IP
      remote_ip: true
```

---

## Cloud Provider Configuration

### Azure Configuration

```yaml
cloud_provider: "azure"

azure:
  # Subscription and tenant
  subscription_id: "${AZURE_SUBSCRIPTION_ID}"
  tenant_id: "${AZURE_TENANT_ID}"
  
  # Authentication
  client_id: "${AZURE_CLIENT_ID}"
  client_secret: "${AZURE_CLIENT_SECRET}"
  
  # Resource group
  resource_group: "helios-production"
  region: "eastus"
  
  # Storage
  storage_account: "heliosstg"
  container: "application"
```

### AWS Configuration

```yaml
cloud_provider: "aws"

aws:
  # Credentials
  access_key: "${AWS_ACCESS_KEY_ID}"
  secret_key: "${AWS_SECRET_ACCESS_KEY}"
  
  # Region
  region: "us-east-1"
  
  # S3 configuration
  s3:
    bucket: "helios-platform"
    prefix: "data/"
  
  # DynamoDB
  dynamodb:
    table_name: "helios-data"
    read_capacity: 100
    write_capacity: 100
```

### Google Cloud Configuration

```yaml
cloud_provider: "gcp"

gcp:
  # Project configuration
  project_id: "${GCP_PROJECT_ID}"
  
  # Service account
  service_account: "${GCP_SERVICE_ACCOUNT}"
  key_file: "/etc/helios/gcp-key.json"
  
  # Storage
  storage_bucket: "helios-platform"
  
  # Compute
  compute_zone: "us-central1-a"
```

---

## Configuration Validation

### Validate Configuration

```bash
# Validate using CLI
helios config validate

# Validate with verbose output
helios config validate --verbose

# Show all configuration values
helios config list
```

### Common Configuration Errors

| Error | Solution |
|-------|----------|
| `Certificate not found` | Verify cert_file and key_file paths |
| `Connection refused` | Check database server is running and accessible |
| `Invalid API endpoint` | Verify URL format and SSL certificate |
| `Permission denied` | Check file permissions on config directories |
| `Missing required field` | Add required configuration parameters |

---

## Security Best Practices

1. **Use Environment Variables**: Never hardcode secrets in config files

   ```yaml
   password: "${DB_PASSWORD}"  # Use environment variables
   ```

2. **Restrict File Permissions**: Config files contain sensitive data

   ```bash
   chmod 600 config.yaml
   ```

3. **Rotate Secrets Regularly**: Update passwords and API keys periodically

4. **Validate Configuration**: Always run `helios config validate` after changes

5. **Use Configuration Templates**: Use version-controlled templates, not actual configs

6. **Enable Audit Logging**: Log all configuration changes

7. **Backup Configuration**: Keep backups of production configurations

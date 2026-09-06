# HELIOS Platform - API Reference

Complete API documentation including REST APIs, WebSocket APIs, and Plugin APIs.

---

## 📚 API Documentation

### REST API

- **Endpoint**: `http://localhost:8080/api/v1`
- **Format**: JSON
- **Authentication**: Bearer Token
- **Rate Limit**: 1000 requests/hour

### WebSocket API

- **Endpoint**: `ws://localhost:8080/ws`
- **Format**: JSON over WebSocket
- **Purpose**: Real-time updates and monitoring

### Plugin API

- **Framework**: .NET 6.0+
- **Interface**: IPlugin
- **Lifecycle**: Initialize → Execute → Dispose

---

## 🔐 Authentication

### Token-Based Authentication

```bash
# Obtain access token
curl -X POST http://localhost:8080/api/auth/token \
  -H "Content-Type: application/json" \
  -d '{
    "username": "user@example.com",
    "password": "password"
  }'

# Response
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

### Using the Token

```bash
curl -H "Authorization: Bearer <token>" \
  http://localhost:8080/api/v1/deployments
```

---

## 📋 Core Endpoints

### Deployments

#### List Deployments

```http
GET /api/v1/deployments
Authorization: Bearer <token>
```

#### Get Deployment Details

```http
GET /api/v1/deployments/{id}
Authorization: Bearer <token>
```

#### Create Deployment

```http
POST /api/v1/deployments
Authorization: Bearer <token>
Content-Type: application/json

{
  "name": "my-app",
  "component": "MyComponent",
  "target": "production",
  "config": { ... }
}
```

#### Update Deployment

```http
PATCH /api/v1/deployments/{id}
Authorization: Bearer <token>
Content-Type: application/json

{
  "config": { ... }
}
```

#### Delete Deployment

```http
DELETE /api/v1/deployments/{id}
Authorization: Bearer <token>
```

### System Monitoring

#### Get System Status

```http
GET /api/v1/system/status
Authorization: Bearer <token>
```

#### Get Metrics

```http
GET /api/v1/metrics
Authorization: Bearer <token>
```

#### Get Logs

```http
GET /api/v1/logs
Authorization: Bearer <token>
```

---

## 🔌 Plugin API

### Basic Plugin Structure

```csharp
using HELIOS.Platform.Plugins;

public class MyPlugin : IPlugin
{
    public string Name => "My Plugin";
    public string Version => "1.0.0";
    
    public void Initialize(IPluginContext context)
    {
        // Initialize plugin
    }
    
    public void Execute(IExecutionContext context)
    {
        // Execute plugin logic
    }
    
    public void Dispose()
    {
        // Cleanup
    }
}
```

### Plugin Context

```csharp
public interface IPluginContext
{
    ILogger Logger { get; }
    IConfiguration Config { get; }
    IServiceProvider Services { get; }
}
```

### Plugin Hooks

```csharp
public class MyPlugin : IPlugin
{
    public void OnDeploymentStart() { }
    public void OnDeploymentComplete() { }
    public void OnDeploymentError(Exception ex) { }
    public void OnMonitoringAlert(Alert alert) { }
}
```

---

## 🎯 Common API Usage Examples

### Example 1: List Deployments

```bash
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/v1/deployments | jq .
```

### Example 2: Get System Status

```bash
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/v1/system/status | jq .
```

### Example 3: Create a Deployment

```bash
curl -X POST http://localhost:8080/api/v1/deployments \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "web-app",
    "component": "WebServer",
    "target": "production"
  }'
```

---

## 🔗 API Response Format

### Success Response

```json
{
  "success": true,
  "data": { ... },
  "message": "Operation completed successfully"
}
```

### Error Response

```json
{
  "success": false,
  "error": "ERROR_CODE",
  "message": "Human readable error message",
  "details": { ... }
}
```

### Pagination

```json
{
  "success": true,
  "data": [ ... ],
  "pagination": {
    "page": 1,
    "pageSize": 20,
    "total": 150,
    "totalPages": 8
  }
}
```

---

## 📖 Related Documentation

### Guides

- **[Getting Started](../guides/GETTING_STARTED.md)** - API overview
- **[Plugin Development](../guides/PLUGIN_DEVELOPMENT.md)** - Build plugins
- **[Integration Guide](../architecture/INTEGRATION.md)** - Integration patterns

### User Guides

- **[Deployment Guide](../user-guides/DEPLOYMENT.md)** - Deploy using API
- **[Configuration Guide](../user-guides/CONFIGURATION.md)** - Configure API

### Examples

- **[Code Examples](../../examples/README.md)** - Working code samples

---

## ⚠️ Error Codes

| Code | Meaning | Resolution |
|------|---------|-----------|
| AUTH_FAILED | Authentication failed | Check token validity |
| INVALID_REQUEST | Invalid request format | Check request format |
| NOT_FOUND | Resource not found | Verify resource ID |
| CONFLICT | Resource conflict | Check for duplicates |
| SERVER_ERROR | Internal server error | Check server logs |

---

## 🔗 Rate Limiting

- **Limit**: 1000 requests per hour
- **Header**: `X-RateLimit-Remaining`
- **Reset**: `X-RateLimit-Reset`

```bash
# Check rate limit
curl -I http://localhost:8080/api/v1/deployments | grep X-RateLimit
```

---

## 📞 Support

- **API Issues?** → See [Troubleshooting](../troubleshooting/README.md)
- **Need examples?** → See [Examples](../../examples/README.md)
- **Have questions?** → See [FAQ](../faq/README.md)

---

**Last Updated:** 2026-04-16 | [Back to Main Documentation](../README.md)

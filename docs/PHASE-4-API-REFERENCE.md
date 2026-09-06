# HELIOS Phase 4 - API Reference

**Version:** 4.0.0  
**Status:** Production  
**Last Updated:** April 14, 2026

---

## 📋 API Endpoints Overview

### Authentication Endpoints

#### POST /api/v1/auth/login

Register a user and receive JWT tokens

**Request:**

```json
{
  "username": "user@example.com",
  "password": "secure_password"
}
```

**Response (Success - 200):**

```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "r0F3kL9mP2jQ5xW8zY1b4c7d...",
  "expiresIn": 3600,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "username": "user@example.com",
    "roles": ["user"]
  }
}
```

**Response (Failure - 401):**

```json
{
  "error": "Invalid credentials",
  "message": "Username or password is incorrect"
}
```

---

#### POST /api/v1/auth/register

Register a new user account

**Request:**

```json
{
  "username": "newuser@example.com",
  "email": "newuser@example.com",
  "password": "secure_password",
  "firstName": "John",
  "lastName": "Doe"
}
```

**Response (Success - 201):**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "username": "newuser@example.com",
  "email": "newuser@example.com",
  "createdAt": "2026-04-14T04:32:14.539Z"
}
```

---

#### POST /api/v1/auth/refresh

Refresh access token using refresh token

**Request:**

```json
{
  "refreshToken": "r0F3kL9mP2jQ5xW8zY1b4c7d..."
}
```

**Response (Success - 200):**

```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expiresIn": 3600
}
```

---

#### POST /api/v1/auth/logout

Logout current user and invalidate tokens

**Request:** (Requires Authorization header)

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Response (Success - 200):**

```json
{
  "message": "Logout successful"
}
```

---

### Health Check Endpoints

#### GET /api/v1/health

Check API health status

**Response (200):**

```json
{
  "status": "healthy",
  "version": "4.0.0",
  "timestamp": "2026-04-14T04:32:14.539Z"
}
```

---

#### GET /api/v1/health/ready

Readiness probe for orchestrators

**Response (200):**

```json
{
  "ready": true,
  "services": {
    "database": "ok",
    "redis": "ok",
    "auth": "ok"
  }
}
```

---

#### GET /api/v1/health/live

Liveness probe for orchestrators

**Response (200):**

```json
{
  "live": true,
  "uptime": "24h 15m 30s"
}
```

---

### User Management Endpoints

#### GET /api/v1/users/{id}

Get user profile (Requires Auth)

**Response (200):**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "username": "user@example.com",
  "email": "user@example.com",
  "firstName": "John",
  "lastName": "Doe",
  "roles": ["user", "admin"],
  "isActive": true,
  "createdAt": "2026-04-01T10:00:00Z",
  "updatedAt": "2026-04-14T04:32:14.539Z"
}
```

---

#### PUT /api/v1/users/{id}

Update user profile (Requires Auth + Authorization)

**Request:**

```json
{
  "firstName": "Jane",
  "lastName": "Smith",
  "email": "newemail@example.com"
}
```

**Response (200):**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "username": "user@example.com",
  "email": "newemail@example.com",
  "firstName": "Jane",
  "lastName": "Smith",
  "updatedAt": "2026-04-14T04:32:14.539Z"
}
```

---

#### DELETE /api/v1/users/{id}

Delete user account (Requires Auth + Admin)

**Response (204):** No Content

---

### Task Management Endpoints

#### POST /api/v1/tasks

Create a new task (Requires Auth)

**Request:**

```json
{
  "name": "Generate report",
  "description": "Generate monthly analytics report",
  "type": "scheduled",
  "priority": "high",
  "scheduledFor": "2026-04-14T12:00:00Z"
}
```

**Response (201):**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "userId": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Generate report",
  "type": "scheduled",
  "status": "pending",
  "priority": "high",
  "createdAt": "2026-04-14T04:32:14.539Z",
  "scheduledFor": "2026-04-14T12:00:00Z"
}
```

---

#### GET /api/v1/tasks/{id}

Get task details (Requires Auth)

**Response (200):**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440001",
  "userId": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Generate report",
  "status": "completed",
  "startedAt": "2026-04-14T12:00:00Z",
  "completedAt": "2026-04-14T12:05:30Z"
}
```

---

#### GET /api/v1/tasks

List user's tasks (Requires Auth)

**Query Parameters:**

- `page` (default: 1)
- `pageSize` (default: 20, max: 100)
- `status` (pending, running, completed, failed)
- `priority` (critical, high, normal, low, deferred)

**Response (200):**

```json
{
  "items": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "name": "Generate report",
      "status": "completed",
      "priority": "high",
      "createdAt": "2026-04-14T04:32:14.539Z"
    }
  ],
  "total": 1,
  "page": 1,
  "pageSize": 20
}
```

---

#### PUT /api/v1/tasks/{id}

Update task (Requires Auth)

**Request:**

```json
{
  "name": "Generate monthly report",
  "priority": "critical"
}
```

**Response (200):** Updated task object

---

#### DELETE /api/v1/tasks/{id}

Delete task (Requires Auth)

**Response (204):** No Content

---

### AI Integration Endpoints

#### POST /api/v1/ai/prompt

Submit AI prompt (Requires Auth)

**Request:**

```json
{
  "content": "Generate a summary of Q1 performance",
  "model": "gpt-4",
  "parameters": {
    "temperature": 0.7,
    "maxTokens": 200
  }
}
```

**Response (201):**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440002",
  "promptId": "550e8400-e29b-41d4-a716-446655440001",
  "content": "Q1 performance shows strong growth across all metrics...",
  "inputTokens": 150,
  "outputTokens": 200,
  "estimatedCost": 0.0045,
  "createdAt": "2026-04-14T04:32:14.539Z"
}
```

---

#### GET /api/v1/ai/cost-estimate

Estimate cost for AI operation (Requires Auth)

**Query Parameters:**

- `model` (required): gpt-4, gpt-3.5-turbo, claude-3
- `inputLength` (required): Expected input text length
- `outputLength` (optional, default: 100)

**Response (200):**

```json
{
  "estimatedCost": 0.0045,
  "inputCost": 0.0015,
  "outputCost": 0.003,
  "model": "gpt-4"
}
```

---

### Analytics Endpoints

#### GET /api/v1/analytics/metrics

Get aggregated system metrics (Requires Auth + Admin)

**Query Parameters:**

- `window` (default: 1h): 1h, 24h, 7d, 30d
- `metric` (optional): specific metric to retrieve

**Response (200):**

```json
{
  "window": "1h",
  "timestamp": "2026-04-14T04:32:14.539Z",
  "metrics": {
    "totalRequests": 45230,
    "avgLatency": 87.5,
    "p95Latency": 245.3,
    "p99Latency": 512.7,
    "errorRate": 0.0012,
    "cacheHitRate": 0.82,
    "activeUsers": 1234
  }
}
```

---

#### GET /api/v1/analytics/performance

Get performance percentiles (Requires Auth + Admin)

**Response (200):**

```json
{
  "latencyPercentiles": {
    "p50": 45,
    "p95": 245,
    "p99": 512
  },
  "throughput": {
    "requestsPerSecond": 750,
    "averageResponseTime": 87
  }
}
```

---

## 🔐 Authentication

All protected endpoints require JWT token in Authorization header:

```
Authorization: Bearer <access_token>
```

Token expires after 1 hour. Use refresh token to obtain new access token.

---

## ⚠️ Error Responses

### Standard Error Format

```json
{
  "error": "ErrorCode",
  "message": "Human-readable error message",
  "timestamp": "2026-04-14T04:32:14.539Z",
  "traceId": "0HN1GKAD73Q6S:00000001"
}
```

### Common HTTP Status Codes

| Code | Meaning | Common Cause |
|------|---------|-------------|
| 400 | Bad Request | Invalid input parameters |
| 401 | Unauthorized | Missing or invalid token |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource does not exist |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Server error |
| 503 | Service Unavailable | Service down for maintenance |

---

## 📈 Rate Limiting

- **Default Limit:** 100 requests per minute per client
- **Burst Limit:** 150 concurrent requests
- **Headers:**
  - `X-RateLimit-Limit`: Request limit
  - `X-RateLimit-Remaining`: Remaining requests
  - `X-RateLimit-Reset`: Unix timestamp of reset time

---

## 🔄 Pagination

List endpoints support pagination with:

- `page`: Page number (default: 1)
- `pageSize`: Items per page (default: 20, max: 100)

Response format:

```json
{
  "items": [...],
  "total": 150,
  "page": 1,
  "pageSize": 20,
  "totalPages": 8
}
```

---

## 📚 Code Examples

### JavaScript/Node.js

```javascript
const axios = require('axios');

const client = axios.create({
  baseURL: 'https://api.helios.example.com/api/v1'
});

// Login
const loginResponse = await client.post('/auth/login', {
  username: 'user@example.com',
  password: 'password'
});

const accessToken = loginResponse.data.accessToken;
client.defaults.headers.common['Authorization'] = `Bearer ${accessToken}`;

// Create task
const taskResponse = await client.post('/tasks', {
  name: 'My Task',
  type: 'immediate'
});

console.log(taskResponse.data);
```

### Python

```python
import requests

BASE_URL = 'https://api.helios.example.com/api/v1'

# Login
response = requests.post(f'{BASE_URL}/auth/login', json={
    'username': 'user@example.com',
    'password': 'password'
})

access_token = response.json()['accessToken']
headers = {'Authorization': f'Bearer {access_token}'}

# Create task
response = requests.post(f'{BASE_URL}/tasks', 
    json={'name': 'My Task', 'type': 'immediate'},
    headers=headers
)

print(response.json())
```

### cURL

```bash
# Login
TOKEN=$(curl -s -X POST https://api.helios.example.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"user@example.com","password":"password"}' \
  | jq -r '.accessToken')

# Create task
curl -X POST https://api.helios.example.com/api/v1/tasks \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"My Task","type":"immediate"}'
```

---

**API Reference Complete** ✅

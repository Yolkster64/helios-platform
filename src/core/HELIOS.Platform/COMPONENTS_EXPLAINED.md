# 🧩 HELIOS Components Explained

This file explains what each component does and how they work together.

## Quick Reference

| Component | Purpose | Key Classes | File Location |
|-----------|---------|-------------|----------------|
| **HeliosDeployment** | Main orchestrator | DeploymentOrchestrator | `HeliosDeployment.cs` |
| **Analytics Service** | Performance tracking | AnalyticsService | `BackendServices/Analytics/` |
| **Auth Service** | Authentication | JwtTokenService | `BackendServices/AuthService/` |
| **Cache Service** | Data caching | CacheService | `BackendServices/DataService/` |
| **AI Integration** | AI service management | AIIntegrationService | `BackendServices/AIIntegration/` |
| **API Gateway** | Request routing | RateLimitAndCircuitBreaker | `BackendServices/ApiGateway/` |
| **Task Orchestrator** | Workflow automation | TaskOrchestrator | `BackendServices/TaskOrchestrator/` |

---

## 📍 Component Locations

```
src/HELIOS.Platform/
├── HeliosDeployment.cs                  ← Main entry point - orchestrates all phases
├── Components/
│   └── ComponentClasses.cs              ← Component interface definitions
└── BackendServices/
    ├── Analytics/
    │   └── AnalyticsService.cs          ← Metrics & performance tracking
    ├── AuthService/
    │   └── JwtTokenService.cs           ← JWT token generation & validation
    ├── DataService/
    │   └── CacheService.cs              ← Redis caching layer
    ├── AIIntegration/
    │   └── AIIntegrationService.cs      ← AI service orchestration
    ├── ApiGateway/
    │   └── RateLimitAndCircuitBreaker.cs ← Request protection & routing
    └── TaskOrchestrator/
        └── TaskOrchestrator.cs          ← Workflow & job management
```

---

## 🏗️ How Components Work Together

```
User Request
    ↓
API Gateway (RateLimitAndCircuitBreaker)
    ├─ Rate limit check
    ├─ Circuit breaker check
    └─ Route to service
    ↓
Authentication (JwtTokenService)
    └─ Validate credentials
    ↓
Caching Layer (CacheService)
    ├─ Check if data cached
    ├─ Return cached = DONE
    └─ Not cached = fetch from DB
    ↓
Service Logic (Analytics, AI, etc)
    └─ Process request
    ↓
Task Orchestrator (TaskOrchestrator)
    ├─ Queue background jobs
    └─ Schedule follow-up tasks
    ↓
Analytics (AnalyticsService)
    ├─ Record metrics
    ├─ Check performance
    └─ Alert if issues
    ↓
Response to User
```

---

## 🔍 Detailed Component Descriptions

### **1. HeliosDeployment** 🎬

**What it is**: Main orchestrator that coordinates all deployment phases.

**What it does**:

- Validates all components before deployment
- Executes deployment in phases (0-7)
- Tracks deployment state and progress
- Handles rollback if needed
- Provides status reporting

**Key Methods**:

- `ValidateAsync()` - Checks all components ready
- `DeployAsync(tier)` - Runs deployment phases
- `GetStatusAsync()` - Current status
- `RollbackAsync(phase)` - Rollback to phase
- `UndeployAsync()` - Remove everything

**Example Usage**:

```csharp
var deployment = new HeliosDeployment();
await deployment.ValidateAsync();
var result = await deployment.DeployAsync(DeploymentTier.Enterprise);
```

---

### **2. API Gateway** 🚪

**File**: `BackendServices/ApiGateway/RateLimitAndCircuitBreaker.cs`

**What it is**: Intelligent gateway that protects backend services.

**What it does**:

- **Rate Limiting**: Restricts requests per client (prevents abuse)
- **Circuit Breaker**: Stops requests to failing services (prevent cascades)
- **Request Tracking**: Logs all incoming requests
- **Error Handling**: Gracefully handles failures

**How it works**:

1. Request arrives
2. Check rate limit for client
3. If exceeded, return 429 (Too Many Requests)
4. Check circuit breaker status
5. If broken, return 503 (Service Unavailable)
6. Forward to backend service
7. Log metrics

**Configuration**:

- Max requests per minute: configurable
- Circuit breaker threshold: 50% errors in 10s
- Timeout: 30 seconds

---

### **3. Authentication Service** 🔐

**File**: `BackendServices/AuthService/JwtTokenService.cs`

**What it is**: JWT token manager for authentication.

**What it does**:

- Generate JWT tokens for users
- Validate token signatures
- Check token expiration
- Extract claims from tokens
- Manage token refresh

**Key Methods**:

- `GenerateToken(userId, claims)` - Create new token
- `ValidateToken(token)` - Check token is valid
- `RefreshToken(token)` - Get new token
- `GetClaims(token)` - Extract claims

**Token Format**:

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.
eyJzdWIiOiJ1c2VyMTIzIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.
SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
```

---

### **4. Caching Service** 💾

**File**: `BackendServices/DataService/CacheService.cs`

**What it is**: Redis-based caching layer.

**What it does**:

- Stores frequently accessed data in memory
- Reduces database queries
- Speeds up responses
- Manages cache expiration
- Tracks cache hit/miss rates

**How it improves performance**:

- DB query: 100ms
- Cache hit: 1ms
- **100x faster!**

**Cache Strategy**:

- Time-based expiration: 5-60 minutes
- LRU eviction: Remove old data when full
- Invalidation: Clear when data changes

**Example**:

```csharp
// Check cache
var cached = cache.Get("user:123");
if (cached != null) return cached;

// Not in cache, fetch from DB
var user = db.GetUser(123);

// Store in cache for 10 minutes
cache.Set("user:123", user, TimeSpan.FromMinutes(10));
return user;
```

---

### **5. Analytics Service** 📊

**File**: `BackendServices/Analytics/AnalyticsService.cs`

**What it is**: Metrics collection and performance tracking.

**What it does**:

- Records every request (endpoint, method, status, latency)
- Calculates statistics (average, min, max response time)
- Detects anomalies (unusual patterns)
- Generates reports
- Sends alerts on problems

**Metrics Tracked**:

- Request count (per endpoint)
- Response times (avg, min, max, p95, p99)
- Error rates
- Cache hit rates
- Database query times
- AI service response times

**Performance Thresholds**:

- Warning: Response time > 1 second
- Critical: Response time > 5 seconds
- Alert: Error rate > 5%

**Usage**:

```csharp
analytics.RecordRequest(
    endpoint: "/api/users",
    method: "GET",
    statusCode: 200,
    latencyMs: 45
);
```

---

### **6. AI Integration Service** 🤖

**File**: `BackendServices/AIIntegration/AIIntegrationService.cs`

**What it is**: Manager for multiple AI services.

**What it does**:

- Connects to Ollama, Azure AI, Claude, etc.
- Routes requests to best service
- Handles model loading/unloading
- Manages API keys and credentials
- Provides fallback if service fails

**Supported Services**:
| Service | Latency | Cost | Best For |
|---------|---------|------|----------|
| Ollama | Low | Free | Local processing |
| Azure OpenAI | Medium | Medium | Enterprise GPT-4 |
| Claude | Medium | Low | Reasoning tasks |
| Copilot | Low | Free | Code tasks |

**Routing Logic**:

```
Request comes in
  ↓
Analyze task complexity & data sensitivity
  ↓
Choose optimal service:
  - Local data? → Ollama
  - Code? → Copilot
  - Reasoning? → Claude
  - High volume? → Azure OpenAI
  ↓
Send request
  ↓
Get response
  ↓
Return to user
```

---

### **7. Task Orchestrator** ⚙️

**File**: `BackendServices/TaskOrchestrator/TaskOrchestrator.cs`

**What it is**: Workflow and job management system.

**What it does**:

- Creates and manages long-running tasks
- Handles task dependencies
- Schedules tasks for future execution
- Retries failed tasks
- Provides task status tracking
- Queues background work

**Task Lifecycle**:

```
1. Create task
2. Queue (waiting)
3. Dequeue (running)
4. Process (executing)
5. Complete/Fail
6. Log result
```

**Example Task**:

```csharp
var task = orchestrator.CreateTask(
    name: "ProcessUserReport",
    inputs: new { userId = 123 },
    priority: TaskPriority.High,
    retryCount: 3
);
```

---

## 🔄 Data Flow Examples

### **Example 1: User Login**

```
1. User sends login request
   POST /auth/login { username, password }

2. API Gateway
   ├─ Rate limit check ✓
   ├─ Circuit breaker check ✓
   └─ Forward to Auth service

3. Auth Service
   ├─ Validate credentials
   ├─ Generate JWT token
   └─ Return token

4. Analytics
   ├─ Record login event
   ├─ Track authentication rate
   └─ Check for anomalies

5. Response to user
   { token: "jwt...", expiresIn: 3600 }
```

### **Example 2: Fetch User Profile**

```
1. Request with auth token
   GET /api/users/123
   Authorization: Bearer jwt...

2. API Gateway
   ├─ Rate limit check ✓
   ├─ Forward to Cache

3. Cache Service
   ├─ Check if user:123 cached
   ├─ YES → Return cached data (1ms)
   └─ NO → Continue

4. Database
   ├─ Query user from DB (100ms)
   └─ Return user data

5. Cache
   ├─ Store in cache (5 min TTL)
   └─ Continue

6. Analytics
   ├─ Record cache miss
   ├─ Record latency (100ms)
   └─ Check thresholds

7. Response
   { id: 123, name: "John", email: "john@example.com" }
```

### **Example 3: AI Analysis**

```
1. Request AI analysis
   POST /api/analyze { text: "..." }

2. AI Integration Service
   ├─ Analyze request complexity
   ├─ Check data sensitivity (private?)
   ├─ Select service
   │   ├─ If private → Ollama (local)
   │   ├─ If code → Copilot
   │   └─ Otherwise → Azure OpenAI
   └─ Send to chosen service

3. Selected Service
   ├─ Process request
   └─ Return analysis

4. Analytics
   ├─ Track AI service latency
   ├─ Record cost
   └─ Check accuracy

5. Task Orchestrator
   ├─ Queue follow-up task
   │   "Store analysis results"
   └─ Schedule in 1 second

6. Response
   { analysis: "...", confidence: 0.95, model: "gpt-4" }
```

---

## 🎯 Component Responsibilities Matrix

| Task | Component |
|------|-----------|
| Protect from abuse | API Gateway |
| Verify user identity | Auth Service |
| Speed up responses | Cache Service |
| Track performance | Analytics Service |
| Run AI models | AI Service |
| Execute workflows | Task Orchestrator |
| Coordinate all | HeliosDeployment |

---

## 📈 Performance Optimization Points

1. **Caching** - 10-100x faster (100ms → 1-10ms)
2. **Rate Limiting** - Prevents overload
3. **Circuit Breaking** - Stops cascading failures
4. **AI Service Selection** - Use cheapest/fastest option
5. **Task Queueing** - Don't block on long tasks
6. **Metrics** - Detect problems early

---

## 🚀 Next Steps

- **Deploy**: [INSTALLATION_GUIDE](../../docs/INSTALLATION_GUIDE.md)
- **Understand APIs**: [API.md](../../docs/API.md)
- **Configure**: [CONFIGURATION.md](../../docs/CONFIGURATION.md)
- **Troubleshoot**: [TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md)

---

**Last Updated**: April 2026  
**Maintained By**: HELIOS Development Team

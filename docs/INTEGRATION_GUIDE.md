# HELIOS v4.0 - Integration Guide

## Table of Contents

1. [Overview](#overview)
2. [Getting Started](#getting-started)
3. [Component Integration](#component-integration)
4. [API Contracts](#component-integration)
5. [Event Formats](#event-formats)
6. [Error Codes](#error-codes)
7. [Best Practices](#best-practices)
8. [Anti-Patterns](#anti-patterns)

---

## Overview

This guide explains how to integrate with HELIOS v4.0 components. Each component exposes both REST APIs and event-driven interfaces.

**Base URL:** `https://api.helios.app/v1`
**Authentication:** Bearer token in Authorization header
**Response Format:** JSON with ISO 8601 timestamps

---

## Getting Started

### Authentication

```bash
# Get authentication token
curl -X POST https://api.helios.app/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "secure_password"
  }'

# Response
{
  "access_token": "eyJhbGc...",
  "refresh_token": "eyJhbGc...",
  "expires_in": 3600,
  "token_type": "Bearer"
}

# Use in subsequent requests
curl -H "Authorization: Bearer eyJhbGc..." https://api.helios.app/v1/...
```

### Connection Setup

```javascript
import HELIOSClient from '@helios/client';

const client = new HELIOSClient({
  apiKey: 'your-api-key',
  baseURL: 'https://api.helios.app/v1',
  timeout: 30000,
  retryPolicy: {
    maxRetries: 3,
    backoffMultiplier: 2
  }
});

// Establish WebSocket connection for real-time updates
await client.connect();
```

---

## Component Integration

### 1. AI Service Integration

**Capabilities:**

- Suggestions
- Semantic search
- Entity extraction
- Text classification

#### Generate Suggestions

```javascript
// Request
const suggestions = await client.ai.generateSuggestions({
  input: 'user',
  count: 5,
  context: 'email_draft',
  filters: ['professional']
});

// Response
{
  "suggestions": [
    {
      "id": "sugg_123",
      "text": "user account",
      "confidence": 0.95,
      "reason": "Common completion in professional context",
      "category": "noun_phrase"
    },
    {
      "id": "sugg_124",
      "text": "user interface",
      "confidence": 0.87,
      "reason": "Frequently paired in technical context",
      "category": "noun_phrase"
    }
  ],
  "processingTime": 145
}
```

#### Semantic Search

```javascript
// Search using natural language
const results = await client.ai.search({
  query: 'Show me emails from Q3 with high priority',
  limit: 20,
  threshold: 0.8
});

// Response
{
  "results": [
    {
      "id": "doc_123",
      "title": "Q3 Project Status",
      "relevance": 0.92,
      "excerpt": "...high priority items...",
      "matchedFields": ["title", "content"]
    }
  ],
  "totalCount": 42,
  "processingTime": 234
}
```

#### Entity Extraction

```javascript
// Extract entities from text
const entities = await client.ai.extractEntities({
  text: 'John Smith from Acme Corp sent the proposal on 2026-04-13',
  types: ['PERSON', 'ORGANIZATION', 'DATE']
});

// Response
{
  "entities": [
    {
      "type": "PERSON",
      "value": "John Smith",
      "confidence": 0.98,
      "start": 0,
      "end": 10
    },
    {
      "type": "ORGANIZATION",
      "value": "Acme Corp",
      "confidence": 0.95,
      "start": 16,
      "end": 25
    },
    {
      "type": "DATE",
      "value": "2026-04-13",
      "confidence": 0.99,
      "start": 45,
      "end": 55
    }
  ]
}
```

**Error Handling:**

```javascript
try {
  const suggestions = await client.ai.generateSuggestions({
    input: '',
    count: 5
  });
} catch (error) {
  if (error.code === 'INVALID_INPUT') {
    console.log('Input validation failed');
  } else if (error.code === 'RATE_LIMITED') {
    console.log('Rate limit exceeded, retry after:', error.retryAfter);
  } else if (error.code === 'SERVICE_UNAVAILABLE') {
    // Fallback to cached results
    const cached = await client.ai.getCachedSuggestions(input);
  }
}
```

---

### 2. Analytics Service Integration

**Capabilities:**

- Event tracking
- Dashboard metrics
- Trend analysis
- Custom reports

#### Track Custom Events

```javascript
// Track event
await client.analytics.trackEvent({
  name: 'feature_used',
  userId: 'user_123',
  properties: {
    featureName: 'cloudSync',
    duration: 1250,
    success: true,
    syncedItems: 42
  },
  timestamp: new Date().toISOString()
});

// Batch multiple events
await client.analytics.batchEvents([
  { name: 'user_login', properties: { userId: 'user_123' } },
  { name: 'document_created', properties: { docType: 'memo' } },
  { name: 'sync_completed', properties: { itemCount: 100 } }
]);
```

#### Get Dashboard Metrics

```javascript
// Get metrics for dashboard
const metrics = await client.analytics.getDashboard({
  timeRange: '24h',
  metrics: ['requests', 'latency', 'errors', 'cache_hit_rate'],
  granularity: '1h'
});

// Response
{
  "data": {
    "requests": {
      "points": [
        { "timestamp": "2026-04-13T00:00:00Z", "value": 15000 },
        { "timestamp": "2026-04-13T01:00:00Z", "value": 16200 }
      ],
      "total": 360000,
      "average": 15000
    },
    "latency": {
      "p50": 125,
      "p95": 287,
      "p99": 512,
      "percentiles": { ... }
    },
    "errors": {
      "total": 42,
      "by_type": {
        "timeout": 15,
        "auth_failed": 12,
        "validation": 15
      }
    },
    "cache_hit_rate": 0.82
  }
}
```

#### Query Events

```javascript
// Query events with filtering
const events = await client.analytics.queryEvents({
  filters: {
    eventName: 'feature_used',
    userId: 'user_123',
    timeRange: ['2026-04-12', '2026-04-13']
  },
  limit: 1000,
  orderBy: 'timestamp'
});
```

---

### 3. Sync Engine Integration

**Capabilities:**

- Multi-device sync
- Conflict resolution
- Offline queue management
- Sync status monitoring

#### Sync Data

```javascript
// Initiate sync
const result = await client.sync.syncData({
  strategy: 'lastWrite',
  forceRefresh: false,
  include: ['documents', 'notes']
});

// Response
{
  "status": "completed",
  "itemsSynced": 42,
  "itemsSkipped": 2,
  "conflicts": 1,
  "conflictsResolved": 1,
  "duration": 1250,
  "startedAt": "2026-04-13T12:00:00Z",
  "completedAt": "2026-04-13T12:00:02.5Z",
  "changes": {
    "created": 5,
    "updated": 35,
    "deleted": 2
  }
}
```

#### Resolve Conflicts

```javascript
// Get conflict details
const conflicts = await client.sync.getConflicts();

// Resolve conflict
await client.sync.resolveConflict({
  conflictId: 'conflict_123',
  resolution: {
    strategy: 'manual',
    chosenVersion: 'local', // or 'remote'
    mergedData: { ... } // for custom merge
  }
});
```

#### Manage Offline Queue

```javascript
// Get offline queue status
const queue = await client.sync.getOfflineQueue();
// { pending: 5, failed: 1, retrying: 0 }

// Retry failed items
await client.sync.retryFailed();

// Clear queue on logout
await client.sync.clearQueue({ force: true });
```

---

### 4. Plugin System Integration

**Capabilities:**

- Plugin installation
- Lifecycle management
- Sandbox communication
- Resource monitoring

#### Install Plugin

```javascript
// Install from plugin registry
const plugin = await client.plugins.install({
  pluginId: 'my-plugin',
  version: 'latest',
  permissions: [
    'ai:suggestions',
    'storage:read',
    'events:emit'
  ]
});

// Response
{
  "id": "my-plugin",
  "version": "1.0.0",
  "status": "installed",
  "permissions": [...],
  "sandbox": {
    "type": "worker",
    "memory": "10MB",
    "cpu": "100m"
  }
}
```

#### Call Plugin API

```javascript
// Call plugin method
const result = await client.plugins.call({
  pluginId: 'my-plugin',
  method: 'processData',
  args: {
    data: [...],
    options: {...}
  }
});
```

#### Listen to Plugin Events

```javascript
// Register plugin event listener
client.plugins.on('my-plugin', 'dataProcessed', (event) => {
  console.log('Plugin event:', event.data);
});

// Or use async iteration
for await (const event of client.plugins.listen('my-plugin')) {
  console.log('Plugin event:', event);
}
```

---

### 5. PWA Features Integration

**Capabilities:**

- Offline mode management
- Push notifications
- Real-time WebSocket
- Service worker updates

#### Enable Offline Mode

```javascript
// Enable offline mode and cache data
const cached = await client.pwa.enableOfflineMode({
  includeEntities: ['documents', 'contacts'],
  maxAgeSeconds: 86400
});

// Response
{
  "mode": "offline",
  "cachedItems": 150,
  "cachedSize": "25MB",
  "queuedOperations": 3,
  "nextSyncAt": "2026-04-13T13:00:00Z"
}
```

#### Manage Notifications

```javascript
// Request notification permission
const permission = await client.pwa.requestNotificationPermission();

// Subscribe to notifications
await client.pwa.subscribeNotifications({
  categories: ['sync_complete', 'error', 'mention'],
  sound: true,
  vibrate: true
});

// Listen to notification events
client.pwa.on('notification', (notification) => {
  console.log('Notification received:', notification);
});
```

#### WebSocket Connection

```javascript
// Connect to real-time updates
client.ws.connect();

// Listen to specific channels
client.ws.subscribe('sync:updates', (event) => {
  console.log('Sync update:', event);
});

client.ws.subscribe('user:activity', (event) => {
  console.log('User activity:', event);
});

// Handle disconnection
client.ws.on('disconnect', () => {
  console.log('WebSocket disconnected, using polling');
});

client.ws.on('reconnect', () => {
  console.log('WebSocket reconnected');
});
```

---

### 6. Cloud Storage Integration

**Capabilities:**

- Backup management
- Restore operations
- Multi-region replication
- Disaster recovery

#### Create Backup

```javascript
// Create backup
const backup = await client.cloud.createBackup({
  encrypt: true,
  regions: ['us-east-1', 'eu-west-1'],
  retention: 30
});

// Response
{
  "id": "backup_123",
  "status": "completed",
  "size": 1073741824, // 1 GB
  "compression": "gzip",
  "encryption": {
    "algorithm": "AES-256",
    "keyId": "key_123"
  },
  "createdAt": "2026-04-13T12:00:00Z",
  "expiresAt": "2026-05-13T12:00:00Z",
  "regions": {
    "us-east-1": "completed",
    "eu-west-1": "completed"
  }
}
```

#### List and Restore Backups

```javascript
// List available backups
const backups = await client.cloud.listBackups({
  limit: 10,
  offset: 0
});

// Restore from backup
const restore = await client.cloud.restoreBackup({
  backupId: 'backup_123',
  targetRegion: 'us-east-1',
  verifyIntegrity: true
});

// Monitor restore progress
const status = await client.cloud.getRestoreStatus(restore.id);
// { progress: 45, itemsRestored: 12500, itemsTotal: 27500 }
```

---

### 7. Security & Authentication

**Capabilities:**

- Token management
- MFA setup
- RBAC operations
- Audit logging

#### Multi-Factor Authentication

```javascript
// Enable MFA
const mfa = await client.security.enableMFA({
  method: 'totp' // or 'sms', 'email'
});

// Response
{
  "secret": "JBSWY3DPEBLW64TMMQ...",
  "qrCode": "data:image/png;base64,...",
  "backupCodes": ["12345678", "87654321", ...],
  "verificationRequired": true
}

// Verify MFA setup
await client.security.verifyMFA({
  code: '123456',
  method: 'totp'
});
```

#### Manage Access Control

```javascript
// Get user roles
const roles = await client.security.getUserRoles();

// Check permission
const hasPermission = await client.security.hasPermission('documents:write');

// Audit log query
const logs = await client.security.getAuditLog({
  timeRange: '7d',
  actions: ['create', 'delete'],
  resources: ['documents']
});
```

---

## Event Formats

### Standard Event Envelope

```json
{
  "id": "evt_123",
  "type": "sync:completed",
  "version": "1.0",
  "timestamp": "2026-04-13T12:00:00Z",
  "userId": "user_123",
  "sessionId": "sess_456",
  "data": {
    "itemsSynced": 42,
    "conflicts": 0
  },
  "metadata": {
    "source": "mobile",
    "region": "us-east-1"
  }
}
```

### Sync Events

```json
{
  "type": "sync:started",
  "data": {
    "syncId": "sync_123",
    "strategy": "lastWrite",
    "entities": ["documents"]
  }
}
```

```json
{
  "type": "sync:completed",
  "data": {
    "syncId": "sync_123",
    "itemsSynced": 42,
    "duration": 1250,
    "conflicts": 0
  }
}
```

```json
{
  "type": "sync:conflict",
  "data": {
    "conflictId": "conflict_123",
    "documentId": "doc_456",
    "localVersion": { ... },
    "remoteVersion": { ... },
    "resolutionRequired": true
  }
}
```

### Analytics Events

```json
{
  "type": "analytics:event",
  "data": {
    "eventName": "feature_used",
    "userId": "user_123",
    "properties": {
      "featureName": "cloudSync",
      "success": true
    }
  }
}
```

### AI Service Events

```json
{
  "type": "ai:suggestion_generated",
  "data": {
    "requestId": "req_123",
    "suggestions": [
      {
        "text": "suggestion",
        "confidence": 0.95
      }
    ]
  }
}
```

---

## Error Codes

### Standard Error Response

```json
{
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "Document not found",
    "details": {
      "resourceId": "doc_123",
      "resourceType": "document"
    },
    "requestId": "req_456",
    "timestamp": "2026-04-13T12:00:00Z"
  }
}
```

### Authentication Errors

| Code | Status | Message | Solution |
|------|--------|---------|----------|
| INVALID_CREDENTIALS | 401 | Email or password incorrect | Verify credentials |
| TOKEN_EXPIRED | 401 | Authentication token expired | Refresh token |
| INVALID_TOKEN | 401 | Token is malformed | Login again |
| MFA_REQUIRED | 401 | Multi-factor authentication required | Complete MFA |
| INSUFFICIENT_PERMISSIONS | 403 | User lacks required permissions | Request access |

### Validation Errors

| Code | Status | Message | Solution |
|------|--------|---------|----------|
| INVALID_INPUT | 400 | Input validation failed | Check request format |
| MISSING_REQUIRED_FIELD | 400 | Required field missing | Provide all required fields |
| INVALID_EMAIL_FORMAT | 400 | Email format invalid | Use valid email |
| PASSWORD_TOO_WEAK | 400 | Password doesn't meet requirements | Use stronger password |

### Resource Errors

| Code | Status | Message | Solution |
|------|--------|---------|----------|
| RESOURCE_NOT_FOUND | 404 | Resource not found | Verify resource ID |
| RESOURCE_ALREADY_EXISTS | 409 | Resource already exists | Use different ID |
| RESOURCE_DELETED | 410 | Resource has been deleted | Use recent backup |
| QUOTA_EXCEEDED | 429 | Resource quota exceeded | Upgrade plan |

### Sync Errors

| Code | Status | Message | Solution |
|------|--------|---------|----------|
| SYNC_CONFLICT | 409 | Data conflict detected | Resolve conflict |
| SYNC_TIMEOUT | 504 | Sync operation timed out | Retry sync |
| SYNC_FAILED | 500 | Sync operation failed | Check connectivity |
| OFFLINE_QUEUE_FULL | 507 | Offline queue is full | Clear queue |

### AI Service Errors

| Code | Status | Message | Solution |
|------|--------|---------|----------|
| AI_MODEL_UNAVAILABLE | 503 | AI model not available | Use cached results |
| AI_RATE_LIMITED | 429 | Rate limit exceeded | Retry after delay |
| AI_INVALID_INPUT | 400 | Invalid input for AI | Check input format |

### Server Errors

| Code | Status | Message | Solution |
|------|--------|---------|----------|
| INTERNAL_SERVER_ERROR | 500 | Unexpected error | Retry later |
| SERVICE_UNAVAILABLE | 503 | Service temporarily down | Check status page |
| DATABASE_ERROR | 500 | Database error | Retry later |

---

## Best Practices

### 1. Error Handling

```javascript
async function syncWithRetry(maxRetries = 3) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await client.sync.syncData();
    } catch (error) {
      if (error.code === 'SYNC_TIMEOUT' && i < maxRetries - 1) {
        // Exponential backoff
        await new Promise(resolve => 
          setTimeout(resolve, Math.pow(2, i) * 1000)
        );
        continue;
      }
      throw error;
    }
  }
}
```

### 2. Offline Support

```javascript
async function processDataOfflineFirst(data) {
  try {
    // Try cloud operation
    return await client.cloud.upload(data);
  } catch (error) {
    if (error.offline) {
      // Queue for later
      await client.sync.queueOperation({
        type: 'upload',
        data: data
      });
      return { queued: true };
    }
    throw error;
  }
}
```

### 3. Rate Limiting

```javascript
// Use exponential backoff
const DEFAULT_RETRIES = 3;
const BASE_DELAY = 1000;

async function withExponentialBackoff(fn) {
  for (let attempt = 0; attempt < DEFAULT_RETRIES; attempt++) {
    try {
      return await fn();
    } catch (error) {
      if (error.code === 'RATE_LIMITED' || error.status === 429) {
        if (attempt < DEFAULT_RETRIES - 1) {
          const delay = BASE_DELAY * Math.pow(2, attempt);
          await new Promise(resolve => setTimeout(resolve, delay));
          continue;
        }
      }
      throw error;
    }
  }
}
```

### 4. Batch Operations

```javascript
// Batch events for better performance
const events = [];
for (let i = 0; i < 100; i++) {
  events.push({
    name: 'action_performed',
    properties: { index: i }
  });
}

// Send in batch instead of individual requests
await client.analytics.batchEvents(events);
```

### 5. Caching

```javascript
const cache = new Map();

async function getCachedData(key, fn, ttl = 60000) {
  const cached = cache.get(key);
  if (cached && Date.now() - cached.timestamp < ttl) {
    return cached.value;
  }
  
  const value = await fn();
  cache.set(key, { value, timestamp: Date.now() });
  return value;
}

// Usage
const suggestions = await getCachedData(
  'suggestions_user',
  () => client.ai.generateSuggestions({ input: 'user' }),
  300000 // 5 minutes
);
```

---

## Anti-Patterns

### ❌ Don't: Poll continuously

```javascript
// BAD: Polling every 100ms
setInterval(async () => {
  const status = await client.sync.getStatus();
}, 100);
```

### ✅ Do: Use WebSocket or Events

```javascript
// GOOD: Event-driven
client.ws.subscribe('sync:updates', (event) => {
  console.log('Sync status:', event.status);
});
```

### ❌ Don't: Ignore errors

```javascript
// BAD: No error handling
await client.sync.syncData();
```

### ✅ Do: Handle errors gracefully

```javascript
// GOOD: Proper error handling
try {
  await client.sync.syncData();
} catch (error) {
  if (error.code === 'OFFLINE') {
    console.log('Offline, queuing operation');
  } else {
    console.error('Sync failed:', error);
  }
}
```

### ❌ Don't: Ignore rate limits

```javascript
// BAD: No rate limit handling
for (let i = 0; i < 10000; i++) {
  await client.ai.generateSuggestions({ input });
}
```

### ✅ Do: Batch and respect limits

```javascript
// GOOD: Batch operations
const suggestions = await Promise.all(
  inputs.map(input => 
    client.ai.generateSuggestions({ input })
  )
);
```

---

**Document Version:** 4.0.0
**Last Updated:** 2026-04-13

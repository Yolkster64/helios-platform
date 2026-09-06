# HELIOS Platform - Complete API Reference

## Overview

The HELIOS Platform provides comprehensive APIs for integrating with all core services. The API supports REST, GraphQL, WebSocket, and webhook-based communication patterns.

## Core API Services

### API Gateway Service

Routes all API requests, handles authentication, and applies rate limiting.

**Key Methods**:

- `RouteRequestAsync(APIRequest)` - Route request to handler
- `AuthenticateAsync(username, password, claims)` - Get JWT token
- `ApplyRateLimitAsync(clientId, config)` - Set rate limits
- `RegisterRouteAsync(APIRoute)` - Register new route
- `ClearCacheAsync(pattern)` - Clear response cache

**Example**:

```csharp
var gateway = serviceProvider.GetRequiredService<IAPIGateway>();
var response = await gateway.RouteRequestAsync(new APIRequest 
{ 
    Path = "/api/v1/health", 
    Method = HTTPMethod.GET 
});
```

### Event Bus Service

Implements publish-subscribe pattern for domain events.

**Key Methods**:

- `PublishAsync(DomainEvent)` - Publish single event
- `PublishBatchAsync(List<DomainEvent>)` - Publish multiple events
- `SubscribeAsync(eventType, handler)` - Subscribe to events
- `GetEventsByTypeAsync(eventType, from, to)` - Query events
- `ReplayEventsAsync(eventType, handler)` - Replay events

**Example**:

```csharp
var eventBus = serviceProvider.GetRequiredService<IEventBus>();
await eventBus.PublishAsync(new DomainEvent 
{ 
    EventType = "ProfileCreated",
    AggregateId = profileId,
    Data = profileData 
});
```

### Plugin Marketplace Service

Manages plugin lifecycle and marketplace operations.

**Key Methods**:

- `DiscoverPluginsAsync(searchTerm)` - Find plugins
- `InstallPluginAsync(pluginId, version)` - Install plugin
- `UninstallPluginAsync(pluginId)` - Remove plugin
- `GetPluginAsync(pluginId)` - Get plugin details

### Session Manager Service

Manages user sessions and authentication state.

**Key Methods**:

- `CreateSessionAsync(userId, credentials)` - Create session
- `InvalidateSessionAsync(sessionId)` - Logout user
- `GetCurrentUserAsync(sessionId)` - Get user info
- `RefreshTokenAsync(oldToken)` - Refresh JWT token

### Notification Service

Sends notifications via multiple channels.

**Key Methods**:

- `SendEmailAsync(userId, subject, body)` - Send email
- `SendPushAsync(deviceId, title, message)` - Send push notification
- `SendSmsAsync(phoneNumber, message)` - Send SMS

## Error Codes

| Code | HTTP Status | Meaning |
|------|-------------|---------|
| `INVALID_REQUEST` | 400 | Invalid request parameters |
| `UNAUTHORIZED` | 401 | Missing or invalid authentication |
| `FORBIDDEN` | 403 | Insufficient permissions |
| `NOT_FOUND` | 404 | Resource doesn't exist |
| `CONFLICT` | 409 | Resource already exists |
| `RATE_LIMITED` | 429 | Rate limit exceeded |
| `INTERNAL_ERROR` | 500 | Server error |
| `SERVICE_UNAVAILABLE` | 503 | Service temporarily unavailable |

## Rate Limiting

All API endpoints respect rate limiting via headers:

- `X-RateLimit-Limit`: Maximum requests allowed
- `X-RateLimit-Remaining`: Requests remaining in window
- `X-RateLimit-Reset`: Unix timestamp when limit resets

**Default Quotas**:

- Basic: 60 req/min
- Professional: 1,000 req/min
- Enterprise: 10,000 req/min

## Versioning

API follows semantic versioning (MAJOR.MINOR.PATCH):

- `/api/v1` - Current version
- `/api/v2` - Future version

Breaking changes follow 12-month deprecation timeline.

## References

- **Architecture**: See [ARCHITECTURE_COMPLETE.md](./ARCHITECTURE_COMPLETE.md)
- **Quick Start**: See [QUICKSTART.md](./QUICKSTART.md)
- **Contributing**: See [CONTRIBUTING.md](./CONTRIBUTING.md)

---

**Last Updated**: Phase 7, Stream 8 - Documentation Expansion
**Status**: Production Ready

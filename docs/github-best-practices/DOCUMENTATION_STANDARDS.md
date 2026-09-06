# Documentation Standards for HELIOS Platform

Standards and templates for creating clear, maintainable documentation.

---

## Table of Contents

1. [README.md Structure](#readmemd-structure)
2. [API Documentation](#api-documentation)
3. [Component Documentation](#component-documentation)
4. [Phase Documentation](#phase-documentation)
5. [Tutorial Format](#tutorial-format)
6. [Example Format](#example-format)
7. [Troubleshooting Guide Format](#troubleshooting-guide-format)

---

## README.md Structure

### Template

````markdown
# Project Name

Brief one-line description of what this project is.

## Overview

2-3 paragraph overview of the project. Explain:
- What problem it solves
- Who should use it
- Key features

## Features

- Feature 1: Brief description
- Feature 2: Brief description
- Feature 3: Brief description

## Quick Start

### Prerequisites
- Node.js 16+
- npm 8+
- Git

### Installation

```bash
git clone https://github.com/your-repo/project.git
cd project
npm install
```

### Basic Usage

```bash
# Start development server
npm start

# Run tests
npm test

# Build for production
npm run build
```

## Documentation

- [Getting Started Guide](docs/GETTING_STARTED.md)
- [API Documentation](docs/API.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Contributing Guide](CONTRIBUTING.md)
- [FAQ](docs/FAQ.md)

## Examples

### Example 1: Basic Usage

```typescript
// Code example
const service = new MyService();
const result = await service.doSomething();
console.log(result);
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| API_URL | API endpoint | http://localhost:3000 |
| LOG_LEVEL | Logging level | info |

### Configuration File

See `.env.template` for all available options.

## Project Structure

```
project/
├── src/              # Source code
├── tests/            # Test files
├── docs/             # Documentation
├── public/           # Static files
└── package.json      # Project metadata
```

## Development

### Setting Up Development Environment

1. Clone the repository
2. Install dependencies: `npm install`
3. Create `.env` from `.env.template`
4. Run tests: `npm test`
5. Start dev server: `npm start`

### Running Tests

```bash
# Run all tests
npm test

# Run tests in watch mode
npm test:watch

# Run tests with coverage
npm test:coverage
```

### Building for Production

```bash
npm run build
```

## Troubleshooting

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues.

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file.

## Support

- 📧 Email: support@example.com
- 💬 Slack: #helios-platform
- 🐛 Issues: [GitHub Issues](https://github.com/your-repo/project/issues)
- 📖 Docs: [Full Documentation](docs/INDEX.md)

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.

## Authors

- Your Name (@username)
- Team Members

---

**Last Updated:** April 2026

````

### README.md Best Practices

```markdown
✓ Keep it focused and concise
✓ First paragraph explains purpose
✓ Include quick start section
✓ Show real examples
✓ Explain configuration
✓ Link to detailed docs
✓ Include troubleshooting link
✓ Show support/contact info
✓ Add license information
✓ Update when functionality changes

✗ Don't overwhelm with details
✗ Don't assume prior knowledge
✗ Don't use outdated examples
✗ Don't forget configuration options
✗ Don't omit support information
```

---

## API Documentation

### Template

````markdown
# API Documentation

## Base URL

```

https://api.example.com/v1

```

## Authentication

All endpoints require authentication via Bearer token.

```bash
Authorization: Bearer <token>
```

## Error Handling

Errors follow standard HTTP status codes:

| Code | Meaning | Example |
|------|---------|---------|
| 200 | Success | Request completed successfully |
| 400 | Bad Request | Invalid parameters |
| 401 | Unauthorized | Missing/invalid token |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource not found |
| 500 | Server Error | Internal server error |

## Endpoints

### GET /users

Get list of users.

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| page | integer | No | Page number (default: 1) |
| limit | integer | No | Results per page (default: 20) |
| role | string | No | Filter by role |

**Example Request:**

```bash
curl -X GET "https://api.example.com/v1/users?page=1&limit=10" \
  -H "Authorization: Bearer token123"
```

**Example Response (200):**

```json
{
  "data": [
    {
      "id": "user-123",
      "email": "user@example.com",
      "role": "admin",
      "created_at": "2026-04-13T10:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "limit": 10,
    "total": 50
  }
}
```

**Example Error Response (400):**

```json
{
  "error": "invalid_parameter",
  "message": "limit must be between 1 and 100",
  "code": 400
}
```

### POST /users

Create a new user.

**Request Body:**

```json
{
  "email": "newuser@example.com",
  "password": "SecurePassword123",
  "role": "user",
  "name": "New User"
}
```

**Example Request:**

```bash
curl -X POST "https://api.example.com/v1/users" \
  -H "Authorization: Bearer token123" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "newuser@example.com",
    "password": "SecurePassword123",
    "role": "user",
    "name": "New User"
  }'
```

**Example Response (201):**

```json
{
  "id": "user-456",
  "email": "newuser@example.com",
  "role": "user",
  "name": "New User",
  "created_at": "2026-04-13T10:00:00Z"
}
```

### GET /users/:id

Get user details.

**URL Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| id | string | Yes | User ID |

**Example Request:**

```bash
curl -X GET "https://api.example.com/v1/users/user-123" \
  -H "Authorization: Bearer token123"
```

**Example Response (200):**

```json
{
  "id": "user-123",
  "email": "user@example.com",
  "role": "admin",
  "name": "John Doe",
  "created_at": "2026-04-13T10:00:00Z"
}
```

## Rate Limiting

API rate limits: 1000 requests per hour per API key.

Response headers:

```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1681383600
```

## Webhooks

Your application can receive webhooks for certain events.

### Webhook Events

| Event | When |
|-------|------|
| user.created | User account created |
| user.updated | User profile updated |
| user.deleted | User account deleted |

### Webhook Payload

```json
{
  "event": "user.created",
  "timestamp": "2026-04-13T10:00:00Z",
  "data": {
    "id": "user-123",
    "email": "user@example.com"
  }
}
```

## Changelog

### v1.1.0 (2026-04-01)

- Added webhook support
- Added rate limiting

### v1.0.0 (2026-03-15)

- Initial release

````

### API Documentation Best Practices

```markdown
✓ Include authentication method
✓ Document all endpoints
✓ Show request/response examples
✓ Document error responses
✓ Include query parameters
✓ Show status codes
✓ Document rate limits
✓ Include changelog
✓ Keep updated with changes
✓ Provide curl examples

✗ Don't omit error cases
✗ Don't leave responses undocumented
✗ Don't use incomplete examples
✗ Don't forget edge cases
✗ Don't update without version notes
```

---

## Component Documentation

### Template

````markdown
# Component: Button

Reusable button component for forms and actions.

## Usage

```typescript
import { Button } from '@/components/Button';

export function MyComponent() {
  return (
    <Button onClick={() => console.log('clicked')}>
      Click me
    </Button>
  );
}
```

## Props

| Prop | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| children | ReactNode | Yes | - | Button text/content |
| onClick | Function | No | - | Click handler |
| type | 'button' \| 'submit' \| 'reset' | No | 'button' | Button type |
| variant | 'primary' \| 'secondary' \| 'danger' | No | 'primary' | Button style variant |
| size | 'small' \| 'medium' \| 'large' | No | 'medium' | Button size |
| disabled | boolean | No | false | Disable button |
| loading | boolean | No | false | Show loading state |
| className | string | No | - | Additional CSS classes |

## Examples

### Basic Button

```typescript
<Button>Save</Button>
```

### Button Variants

```typescript
<Button variant="primary">Primary</Button>
<Button variant="secondary">Secondary</Button>
<Button variant="danger">Delete</Button>
```

### Button Sizes

```typescript
<Button size="small">Small</Button>
<Button size="medium">Medium</Button>
<Button size="large">Large</Button>
```

### With Loading State

```typescript
const [loading, setLoading] = useState(false);

return (
  <Button
    loading={loading}
    onClick={() => {
      setLoading(true);
      // Do something...
    }}
  >
    Save
  </Button>
);
```

## Accessibility

- ✓ Keyboard accessible (Tab, Enter, Space)
- ✓ Screen reader compatible
- ✓ High contrast support
- ✓ Focus indicators

## Testing

```typescript
import { render, screen } from '@testing-library/react';
import { Button } from '@/components/Button';

it('should render button with text', () => {
  render(<Button>Click me</Button>);
  expect(screen.getByText('Click me')).toBeInTheDocument();
});

it('should call onClick when clicked', () => {
  const onClick = jest.fn();
  render(<Button onClick={onClick}>Click me</Button>);
  screen.getByText('Click me').click();
  expect(onClick).toHaveBeenCalled();
});
```

## Related Components

- [Link Component](./Link.md)
- [IconButton Component](./IconButton.md)
- [ButtonGroup Component](./ButtonGroup.md)

````

---

## Phase Documentation

### Template

````markdown
# Phase 1: Foundation Setup

Complete setup of core infrastructure and development environment.

## Overview

This phase establishes the foundation for the entire project.

## Duration

3 weeks (April 1 - April 21, 2026)

## Objectives

- [ ] Development environment ready
- [ ] CI/CD pipeline configured
- [ ] Database schema designed
- [ ] Authentication system implemented
- [ ] API documentation created

## Deliverables

| Item | Status | Deadline |
|------|--------|----------|
| Development environment | ✓ Complete | April 1 |
| CI/CD pipeline | In Progress | April 7 |
| Database schema | Pending | April 14 |
| Authentication system | Pending | April 21 |

## Technical Requirements

- Node.js 16+
- PostgreSQL 13+
- Docker for containerization
- GitHub for version control

## Acceptance Criteria

- [ ] Dev environment works for all team members
- [ ] CI/CD runs all checks automatically
- [ ] Database can handle production load
- [ ] Authentication works with OAuth2
- [ ] API documentation is complete

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Database performance | Load testing before production |
| CI/CD delays | Parallel setup with other work |
| Team onboarding | Comprehensive setup guide |

## Next Phase

[Phase 2: Core Features](./PHASE_2.md)
````

---

## Tutorial Format

### Template

````markdown
# Tutorial: Building Your First Component

Learn how to create reusable React components in HELIOS.

## Prerequisites

- React 18+ knowledge
- Node.js 16+ installed
- Project cloned and running

## Time Required

30 minutes

## What You'll Learn

- ✓ Component structure
- ✓ Props and state
- ✓ Testing components
- ✓ Publishing components

## Step 1: Create Component File

Create `src/components/MyButton.tsx`:

```typescript
interface MyButtonProps {
  label: string;
  onClick?: () => void;
}

export const MyButton: React.FC<MyButtonProps> = ({
  label,
  onClick
}) => {
  return (
    <button onClick={onClick}>
      {label}
    </button>
  );
};
```

## Step 2: Add Styling

Create `src/components/MyButton.css`:

```css
button {
  padding: 10px 20px;
  background-color: #007bff;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
}

button:hover {
  background-color: #0056b3;
}
```

## Step 3: Write Tests

Create `src/components/MyButton.test.tsx`:

```typescript
import { render, screen } from '@testing-library/react';
import { MyButton } from './MyButton';

it('renders button with label', () => {
  render(<MyButton label="Click me" />);
  expect(screen.getByText('Click me')).toBeInTheDocument();
});
```

## Step 4: Export Component

Update `src/components/index.ts`:

```typescript
export { MyButton } from './MyButton';
```

## Next Steps

- [Advanced Component Patterns](./advanced-components.md)
- [Component Library Guide](./component-library.md)

## Troubleshooting

See [Component Troubleshooting](../troubleshooting.md#components)

````

---

## Example Format

### Template

````markdown
# Example: API Integration

This example shows how to integrate with the HELIOS API.

## What This Example Shows

- Authentication with Bearer token
- Making API requests
- Error handling
- Caching responses

## Code

```typescript
import { useState, useEffect } from 'react';

interface User {
  id: string;
  email: string;
  name: string;
}

export function UserList() {
  const [users, setUsers] = useState<User[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchUsers();
  }, []);

  const fetchUsers = async () => {
    setLoading(true);
    try {
      const response = await fetch('/api/users', {
        headers: {
          'Authorization': `Bearer ${process.env.REACT_APP_API_TOKEN}`
        }
      });
      
      if (!response.ok) {
        throw new Error('Failed to fetch users');
      }
      
      const data = await response.json();
      setUsers(data.data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  };

  if (loading) return <div>Loading...</div>;
  if (error) return <div>Error: {error}</div>;
  
  return (
    <ul>
      {users.map(user => (
        <li key={user.id}>{user.name} ({user.email})</li>
      ))}
    </ul>
  );
}
```

## Key Points

- Use Bearer token for authentication
- Handle loading and error states
- Provide user feedback
- Use TypeScript for type safety

## Related Examples

- [Form Submission Example](./form-submission.md)
- [Real-time Updates Example](./realtime-updates.md)

````

---

## Troubleshooting Guide Format

### Template

````markdown
# Troubleshooting

## Issue: API Returns 401 Unauthorized

### Symptoms
- Getting "401 Unauthorized" error from API
- Cannot access protected endpoints
- Authentication token rejected

### Possible Causes
- Missing API token
- Expired token
- Invalid token format
- Insufficient permissions

### Solutions

**Check 1: Verify token is set**
```bash
echo $API_TOKEN
# Should output: your-token-here
```

**Check 2: Verify token format**
Token should be Bearer token:

```
Authorization: Bearer your-token-here
```

NOT:

```
Authorization: your-token-here
Authorization: Bearer Bearer your-token-here
```

**Check 3: Token expiration**

```bash
# Check token expiration
curl https://api.example.com/v1/token/verify \
  -H "Authorization: Bearer $API_TOKEN"
```

**Check 4: Request format**

```bash
# Correct format
curl -X GET https://api.example.com/v1/users \
  -H "Authorization: Bearer $API_TOKEN"
```

### Resolution

1. Verify token exists: `echo $API_TOKEN`
2. Verify token format: `Bearer <token>`
3. Verify token not expired
4. Get new token if needed: [Get API Token Guide](./get-token.md)

---

## Issue: Database Connection Fails

### Symptoms

- "ECONNREFUSED" error
- "Cannot connect to database"
- Application won't start

### Solutions

**Check 1: Database running**

```bash
# Check if PostgreSQL is running
psql --version
```

**Check 2: Connection string**

```bash
# Verify connection string in .env
DATABASE_URL=postgresql://user:pass@localhost:5432/dbname
```

**Check 3: Credentials**

```bash
# Test connection
psql $DATABASE_URL
```

**Check 4: Port availability**

```bash
# Check if port 5432 is in use
lsof -i :5432
```

### Resolution

1. Start database service
2. Verify connection string
3. Check database is accessible
4. Verify correct credentials

---

## Issue: Tests Fail with Timeout

### Symptoms

- Tests timeout after 5000ms
- "Timeout - Async callback was not invoked"
- Tests are very slow

### Solutions

**Increase timeout**

```typescript
it('should do something', async () => {
  // ...
}, 10000); // 10 second timeout
```

**Fix slow tests**

```typescript
// Bad: Actual network call
it('should fetch users', async () => {
  const users = await fetch('/api/users');
  // ...
});

// Good: Mocked API call
it('should fetch users', async () => {
  jest.mock('fetch', () => ({
    users: [{ id: 1, name: 'John' }]
  }));
  // ...
});
```

### Prevention

- Mock external API calls
- Use fast test database
- Run tests in parallel
- Profile slow tests

---

## Getting Help

- 📖 [Full Documentation](../README.md)
- 💬 [Community Slack](https://slack.example.com)
- 🐛 [Report Bug](https://github.com/your-repo/issues)
- 📧 [Email Support](mailto:support@example.com)

````

---

## Documentation Best Practices

```markdown
General Guidelines:
✓ Keep it up-to-date with code
✓ Use clear, simple language
✓ Include examples
✓ Test examples
✓ Link to related docs
✓ Use consistent formatting
✓ Add table of contents
✓ Update version with changes
✓ Provide troubleshooting
✓ Give attribution for sources

✗ Don't assume deep knowledge
✗ Don't use outdated examples
✗ Don't skip edge cases
✗ Don't forget error states
✗ Don't create disconnected docs
✗ Don't use inconsistent formatting
✗ Don't update without notes
```

---

**Last Updated:** April 2026  
**Version:** 1.0

See also: [README.md](../../README.md), [CONTRIBUTING.md](../../CONTRIBUTING.md)

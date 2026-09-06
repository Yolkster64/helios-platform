# HELIOS Platform - Best Practices Guide

## Architecture & Design

### Component Organization

**Best Practice:** Organize components by feature, not by type

```
✓ GOOD:
src/Components/UserManagement/
  - UserService.cs
  - UserViewModel.cs
  - UserView.xaml
  - UserRepository.cs

✗ BAD:
src/Services/
  - UserService.cs
src/ViewModels/
  - UserViewModel.cs
src/Views/
  - UserView.xaml
```

### Dependency Injection

**Best Practice:** Always use constructor injection, never service locator pattern

```csharp
// ✓ GOOD
public class UserService
{
    private readonly IRepository<User> _repository;
    public UserService(IRepository<User> repository) => _repository = repository;
}

// ✗ BAD
public class UserService
{
    public UserService() => _repository = ServiceLocator.GetService<IRepository>();
}
```

### Async Operations

**Best Practice:** Always use async/await, never block on async code

```csharp
// ✓ GOOD
public async Task LoadDataAsync()
{
    var data = await _service.GetDataAsync();
    ProcessData(data);
}

// ✗ BAD
public void LoadData()
{
    var data = _service.GetDataAsync().Result;  // Blocks!
    ProcessData(data);
}
```

### Error Handling

**Best Practice:** Use specific exception types, never bare catch blocks

```csharp
// ✓ GOOD
try
{
    await _service.ConnectAsync();
}
catch (ConnectionException ex)
{
    ToastNotificationManager.ShowError("Connection Failed", ex.Message);
}
catch (TimeoutException ex)
{
    ToastNotificationManager.ShowWarning("Timeout", "Operation took too long");
}

// ✗ BAD
try { await _service.ConnectAsync(); }
catch { }  // Silent failure!
```

---

## Code Quality

### Naming Conventions

**Best Practice:** Use clear, descriptive names that indicate purpose

```csharp
// ✓ GOOD
private readonly ILogger _logger;
private int _maxRetryAttempts = 3;
public async Task ProcessPaymentAsync() { }

// ✗ BAD
private ILogger log;
private int max = 3;
public async Task Proc() { }
```

### Method Size

**Best Practice:** Keep methods small and focused (< 30 lines)

```csharp
// ✓ GOOD
public async Task<Result> ValidateAndSaveUserAsync(UserInput input)
{
    if (!ValidateInput(input, out var error))
        return Result.Failure(error);
    
    var user = MapToUser(input);
    await _repository.SaveAsync(user);
    return Result.Success();
}

private bool ValidateInput(UserInput input, out string error) { }
private User MapToUser(UserInput input) { }

// ✗ BAD
public async Task<Result> DoStuff(dynamic data)
{
    // 200 lines of mixed concerns...
}
```

### Documentation

**Best Practice:** Document public APIs with XML comments

```csharp
// ✓ GOOD
/// <summary>
/// Retrieves user by ID from the repository
/// </summary>
/// <param name="userId">The unique user identifier</param>
/// <returns>User object or null if not found</returns>
/// <exception cref="ArgumentException">Thrown if userId is invalid</exception>
public async Task<User> GetUserByIdAsync(int userId)
{
    if (userId <= 0)
        throw new ArgumentException("userId must be positive", nameof(userId));
    
    return await _repository.GetByIdAsync(userId);
}

// ✗ BAD
public async Task<User> GetUser(int id) { }  // No documentation
```

### Constants

**Best Practice:** Use named constants instead of magic numbers

```csharp
// ✓ GOOD
private const int MaxPasswordLength = 64;
private const int MinPasswordLength = 12;
private const int PasswordExpirationDays = 90;

// ✗ BAD
if (password.Length < 12 || password.Length > 64) { }
```

---

## UI/UX Best Practices

### Animations

**Best Practice:** Use animations purposefully for feedback and transitions

```csharp
// ✓ GOOD
// Fade in new content
GUIPolishManager.ApplyFadeInAnimation(newPanel, 300);

// Pop for confirmation
GUIPolishManager.ApplyPopAnimation(successIcon, 300);

// ✗ BAD
// Excessive animations
GUIPolishManager.ApplyPulseAnimation(everyElement);
```

### User Feedback

**Best Practice:** Provide immediate feedback for all user actions

```csharp
// ✓ GOOD
try
{
    await _service.SaveAsync(data);
    ToastNotificationManager.ShowSuccess("Success", "Changes saved");
}
catch (Exception ex)
{
    ToastNotificationManager.ShowError("Error", ex.Message);
}

// ✗ BAD
// No feedback
await _service.SaveAsync(data);
```

### Input Validation

**Best Practice:** Validate input with helpful error messages

```csharp
// ✓ GOOD
if (!InputValidator.ValidateEmail(email, out var error))
{
    ToastNotificationManager.ShowError("Invalid Email", error);
    return;
}

// ✗ BAD
if (!email.Contains("@")) { }  // Vague validation
```

### Loading States

**Best Practice:** Show loading states for long operations

```csharp
// ✓ GOOD
try
{
    _isLoading = true;
    GUIPolishManager.ApplySpinAnimation(spinner);
    await LongOperation();
}
finally
{
    _isLoading = false;
    spinner.Stop();
}

// ✗ BAD
// No indication of work happening
await LongOperation();
```

---

## Security Best Practices

### Secrets Management

**Best Practice:** Never store secrets in code or config files

```csharp
// ✓ GOOD
private string _apiKey = Environment.GetEnvironmentVariable("API_KEY");
private string _dbPassword = config["Database:Password"];

// ✗ BAD
private string _apiKey = "sk_live_abc123xyz";
private string _dbPassword = "admin123";
```

### Input Validation

**Best Practice:** Validate all external input

```csharp
// ✓ GOOD
public async Task<User> GetUserAsync(string id)
{
    if (string.IsNullOrWhiteSpace(id))
        throw new ArgumentException("User ID required", nameof(id));
    
    if (!IsValidUserId(id))
        throw new ArgumentException("Invalid User ID format", nameof(id));
    
    return await _repository.GetAsync(id);
}

// ✗ BAD
public async Task<User> GetUserAsync(string id)
{
    return await _repository.GetAsync(id);  // No validation
}
```

### SQL Injection Prevention

**Best Practice:** Always use parameterized queries

```csharp
// ✓ GOOD
var query = "SELECT * FROM Users WHERE Email = @Email";
using var command = new SqlCommand(query, connection);
command.Parameters.AddWithValue("@Email", email);

// ✗ BAD
var query = $"SELECT * FROM Users WHERE Email = '{email}'";  // SQL Injection risk!
```

### TLS/SSL

**Best Practice:** Always use HTTPS in production

```yaml
# ✓ GOOD
security:
  require_https: true
  tls:
    min_version: "1.3"

# ✗ BAD
security:
  require_https: false  # HTTP only - insecure!
```

---

## Performance Best Practices

### Caching

**Best Practice:** Cache appropriate data with reasonable TTL

```csharp
// ✓ GOOD
private const int CacheTtlSeconds = 3600;
var cachedUser = await _cache.GetAsync<User>($"user:{userId}");
if (cachedUser != null) return cachedUser;

var user = await _repository.GetAsync(userId);
await _cache.SetAsync($"user:{userId}", user, TimeSpan.FromSeconds(CacheTtlSeconds));
return user;

// ✗ BAD
// No caching - repeated DB queries
var user = await _repository.GetAsync(userId);
```

### Connection Pooling

**Best Practice:** Configure appropriate connection pool sizes

```yaml
# ✓ GOOD
database:
  pool:
    size: 20          # Adequate for typical load
    min_size: 5
    timeout: 30000

# ✗ BAD
database:
  pool:
    size: 100        # Too large - wastes resources
```

### Query Optimization

**Best Practice:** Write efficient queries with proper indexing

```csharp
// ✓ GOOD
var users = await _context.Users
    .Where(u => u.Status == UserStatus.Active)
    .Include(u => u.Roles)  // Eager load related data
    .OrderBy(u => u.Name)
    .Take(100)
    .ToListAsync();

// ✗ BAD
var users = await _context.Users.ToListAsync();  // Load all then filter in memory
foreach (var user in users)
{
    var roles = await _context.Roles  // N+1 query problem
        .Where(r => r.UserId == user.Id)
        .ToListAsync();
}
```

### Logging

**Best Practice:** Log at appropriate levels to avoid performance impact

```csharp
// ✓ GOOD
if (_logger.IsEnabled(LogLevel.Debug))
{
    _logger.LogDebug("Processing {Count} items", items.Count);  // Only computed if debug enabled
}

// ✗ BAD
_logger.LogDebug($"Processing {ExpensiveCalculation()} items");  // Always computed!
```

---

## Testing Best Practices

### Unit Testing

**Best Practice:** Write focused unit tests for single responsibility

```csharp
// ✓ GOOD
[Fact]
public async Task GetUserAsync_WithValidId_ReturnsUser()
{
    // Arrange
    var repository = new Mock<IRepository<User>>();
    var expectedUser = new User { Id = 1, Name = "Test" };
    repository.Setup(r => r.GetAsync(1)).ReturnsAsync(expectedUser);
    var service = new UserService(repository.Object);
    
    // Act
    var result = await service.GetUserAsync(1);
    
    // Assert
    Assert.Equal(expectedUser, result);
}

// ✗ BAD
[Fact]
public void TestUserService()
{
    var service = new UserService();
    var user = service.GetUser(1);
    var orders = service.GetOrders(1);
    var payments = service.GetPayments(1);
    // Too many assertions, testing multiple concerns
}
```

### Integration Testing

**Best Practice:** Test component integration with real dependencies

```csharp
// ✓ GOOD
[Collection("Database Collection")]
public class UserServiceIntegrationTests
{
    [Fact]
    public async Task SaveUserAsync_PersistsToDatabase()
    {
        // Use real database for integration test
        using var context = new TestDbContext();
        var service = new UserService(new Repository(context));
        
        await service.SaveAsync(new User { Name = "Test" });
        
        var saved = await context.Users.FirstAsync(u => u.Name == "Test");
        Assert.NotNull(saved);
    }
}
```

---

## Documentation Best Practices

### XML Documentation

**Best Practice:** Document public APIs thoroughly

```csharp
/// <summary>
/// Processes a batch of users for registration
/// </summary>
/// <remarks>
/// This method validates each user and persists them to the database.
/// It uses transaction for atomicity. If any user fails validation,
/// the entire batch is rejected and no data is persisted.
/// </remarks>
/// <param name="users">Collection of users to process</param>
/// <returns>Result indicating success or failure with error details</returns>
/// <exception cref="ArgumentNullException">Thrown if users is null</exception>
/// <example>
/// <code>
/// var users = new[] { new User { Email = "user@example.com" } };
/// var result = await service.ProcessBatchAsync(users);
/// if (result.Success)
///     Console.WriteLine("Users registered successfully");
/// </code>
/// </example>
public async Task<Result> ProcessBatchAsync(User[] users)
{
    // Implementation
}
```

### README Files

**Best Practice:** Keep README files up-to-date with current information

---

## Version Control Best Practices

### Commit Messages

**Best Practice:** Write clear, descriptive commit messages

```
✓ GOOD:
feat: add user authentication with JWT tokens

- Implement JWT token generation and validation
- Add secure password hashing with bcrypt
- Include token refresh mechanism

✗ BAD:
fix stuff
updated code
```

### Branch Strategy

**Best Practice:** Use meaningful branch names

```
✓ GOOD:
feature/user-authentication
bugfix/memory-leak-in-cache
docs/api-reference-update

✗ BAD:
feature1
fix-bug
update
```

---

## Release Best Practices

### Version Numbering

**Best Practice:** Follow Semantic Versioning

```
MAJOR.MINOR.PATCH

1.0.0  - Initial release
1.1.0  - New features (backward compatible)
1.1.1  - Bug fix (backward compatible)
2.0.0  - Breaking changes
```

### Release Notes

**Best Practice:** Document all changes clearly

```markdown
## v1.1.0 - 2026-04-17

### New Features
- User authentication with JWT tokens
- Dashboard redesign with improved UX

### Bug Fixes
- Fixed memory leak in cache
- Resolved connection timeout issues

### Breaking Changes
- Removed deprecated API endpoints

### Migration Guide
See MIGRATION_GUIDE.md for upgrade instructions
```

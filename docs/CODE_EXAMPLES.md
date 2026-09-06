# HELIOS Platform - Code Examples

## Table of Contents

1. [Branding & UI](#branding--ui)
2. [Animations & Effects](#animations--effects)
3. [Input Validation](#input-validation)
4. [Toast Notifications](#toast-notifications)
5. [Console Output](#console-output)
6. [Icon Generation](#icon-generation)

---

## Branding & UI

### Using Brand Colors in XAML

```xaml
<Window xmlns:local="clr-namespace:HELIOS.Platform.Presentation.Assets">
    <Window.Resources>
        <ResourceDictionary Source="Assets/Themes.xaml"/>
    </Window.Resources>
    
    <Grid Background="{StaticResource BackgroundBrush}">
        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
            <Border Background="{StaticResource PrimaryBrush}" 
                    CornerRadius="8" Padding="16">
                <TextBlock Text="Welcome to HELIOS" 
                          Foreground="White" FontSize="24" FontWeight="Bold"/>
            </Border>
            
            <Button Background="{StaticResource AccentBrush}" 
                   Foreground="White" Padding="12,8" Margin="0,16,0,0">
                Get Started
            </Button>
        </StackPanel>
    </Grid>
</Window>
```

### Using Brand Colors in Code-Behind

```csharp
using HELIOS.Platform.Presentation.Assets;

// Create button with branding
var button = new Button
{
    Content = "Deploy",
    Background = HeliosBranding.PrimaryBrush,
    Foreground = new SolidColorBrush(Colors.White),
    Padding = new Thickness(12, 8, 12, 8),
    FontSize = 14,
    FontWeight = FontWeights.SemiBold
};

// Apply state-based color
var statusText = new TextBlock
{
    Text = "Processing...",
    Foreground = HeliosBranding.GetStateBrush("info")
};

// Semantic color feedback
var successMessage = new TextBlock
{
    Text = "✓ Operation completed",
    Foreground = HeliosBranding.SuccessBrush
};
```

### Theme Resources Usage

```xaml
<TextBlock FontSize="{StaticResource FontSizeLarge}" 
          FontFamily="{StaticResource PrimaryFont}"
          Foreground="{StaticResource TextBrush}"
          Margin="{StaticResource SpacingMedium}"/>

<Border CornerRadius="{StaticResource CornerRadiusMedium}"
       Padding="{StaticResource SpacingLarge}"/>
```

---

## Animations & Effects

### Fade-In Animation

```csharp
using HELIOS.Platform.Presentation.Components;

// Fade in a new panel when it appears
public void ShowNewPanel(Panel newPanel)
{
    mainGrid.Children.Add(newPanel);
    GUIPolishManager.ApplyFadeInAnimation(newPanel, duration: 500);
}
```

### Pop Animation for Confirmation

```csharp
// Show success confirmation with pop
private async void OnSaveSuccess()
{
    successIcon.Visibility = Visibility.Visible;
    GUIPolishManager.ApplyPopAnimation(successIcon, duration: 300);
    
    await Task.Delay(2000);
    successIcon.Visibility = Visibility.Collapsed;
}
```

### Slide-In Animation

```csharp
// Slide in notifications from right
public void ShowNotificationPanel(NotificationPanel notification)
{
    notificationContainer.Children.Add(notification);
    GUIPolishManager.ApplySlideInAnimation(notification, distance: 200, duration: 400);
}
```

### Pulse Animation for Attention

```csharp
// Pulse animation for important alerts
public void HighlightCriticalAlert(Panel alertPanel)
{
    alertPanel.BorderBrush = HeliosBranding.ErrorBrush;
    GUIPolishManager.ApplyPulseAnimation(alertPanel, duration: 1500);
}
```

### Loading Spinner

```csharp
// Show loading spinner during async operation
private async void LoadData()
{
    try
    {
        loadingSpinner.Visibility = Visibility.Visible;
        GUIPolishManager.ApplySpinAnimation(loadingSpinner, duration: 1000);
        
        var data = await _service.GetDataAsync();
        DisplayData(data);
    }
    finally
    {
        loadingSpinner.Visibility = Visibility.Collapsed;
    }
}
```

---

## Input Validation

### Form Validation Example

```csharp
using HELIOS.Platform.Presentation.Components;

public class UserRegistrationForm
{
    private TextBox _usernameInput;
    private TextBox _emailInput;
    private PasswordBox _passwordInput;
    
    public bool ValidateForm()
    {
        // Validate username
        if (!InputValidator.ValidateNotEmpty(_usernameInput.Text, "Username", out var usernameError))
        {
            ToastNotificationManager.ShowError("Validation Error", usernameError);
            return false;
        }
        
        // Validate email
        if (!InputValidator.ValidateEmail(_emailInput.Text, out var emailError))
        {
            ToastNotificationManager.ShowError("Validation Error", emailError);
            return false;
        }
        
        // Validate password
        if (!InputValidator.ValidateLength(_passwordInput.Password, 12, 64, "Password", out var passwordError))
        {
            ToastNotificationManager.ShowError("Validation Error", passwordError);
            return false;
        }
        
        ToastNotificationManager.ShowSuccess("Success", "Form validation passed");
        return true;
    }
}
```

### Custom Validation with Friendly Feedback

```csharp
public bool ValidateConfiguration(string endpoint, string port, string apiKey)
{
    // Validate endpoint URL
    if (!InputValidator.ValidateUrl(endpoint, out var urlError))
    {
        ToastNotificationManager.ShowError("Invalid Configuration", urlError);
        return false;
    }
    
    // Validate port number
    if (!InputValidator.ValidateNumeric(port, out var portError))
    {
        ToastNotificationManager.ShowError("Invalid Configuration", portError);
        return false;
    }
    
    // Validate API key length
    if (!InputValidator.ValidateLength(apiKey, 32, 128, "API Key", out var keyError))
    {
        ToastNotificationManager.ShowError("Invalid Configuration", keyError);
        return false;
    }
    
    return true;
}
```

---

## Toast Notifications

### Success Notification

```csharp
using HELIOS.Platform.Presentation.Components;

// Show success notification
private async void OnDeploymentSuccess()
{
    ToastNotificationManager.ShowSuccess(
        title: "Deployment Complete",
        message: "Application deployed to production successfully",
        duration: 3000
    );
}
```

### Error Notification

```csharp
// Show error with exception message
private async void OnOperationFailed(Exception ex)
{
    ToastNotificationManager.ShowError(
        title: "Operation Failed",
        message: ex.Message,
        duration: 5000
    );
}
```

### Warning Notification

```csharp
// Show warning about resource limit
private void OnHighMemoryUsage(double usagePercent)
{
    ToastNotificationManager.ShowWarning(
        title: "Memory Warning",
        message: $"Memory usage is {usagePercent}% - consider restarting services",
        duration: 5000
    );
}
```

### Info Notification

```csharp
// Show informational notification
private void OnUpdate Available()
{
    ToastNotificationManager.ShowInfo(
        title: "Update Available",
        message: "HELIOS Platform v1.1.0 is now available. Restart to update.",
        duration: 7000
    );
}
```

### Complex Notification Workflow

```csharp
public async Task<Result> DeployAsync(string environment)
{
    ToastNotificationManager.ShowInfo("Deployment", $"Starting deployment to {environment}...");
    
    try
    {
        // Show progress updates as info toasts
        ToastNotificationManager.ShowInfo("Progress", "Step 1/4: Validating configuration");
        await ValidateConfigAsync();
        
        ToastNotificationManager.ShowInfo("Progress", "Step 2/4: Preparing resources");
        await PrepareResourcesAsync();
        
        ToastNotificationManager.ShowInfo("Progress", "Step 3/4: Deploying application");
        await DeployApplicationAsync();
        
        ToastNotificationManager.ShowInfo("Progress", "Step 4/4: Running tests");
        await RunTestsAsync();
        
        ToastNotificationManager.ShowSuccess(
            "Deployment Complete",
            $"Successfully deployed to {environment}",
            duration: 4000
        );
        
        return Result.Success();
    }
    catch (Exception ex)
    {
        ToastNotificationManager.ShowError("Deployment Failed", ex.Message);
        return Result.Failure(ex.Message);
    }
}
```

---

## Console Output

### Status Report

```csharp
using HELIOS.Platform.Presentation.Components;

public void PrintSystemStatus()
{
    ConsoleFormatter.PrintHeader("System Status Report");
    
    var headers = new[] { "Component", "Status", "Version", "Latency" };
    var rows = new[]
    {
        new[] { "Core Engine", "✓ OK", "1.0.0", "45ms" },
        new[] { "Database", "✓ OK", "latest", "12ms" },
        new[] { "API Gateway", "✓ OK", "1.0.0", "38ms" },
        new[] { "Cache", "✓ OK", "6.2", "2ms" }
    };
    
    ConsoleFormatter.PrintTable(headers, rows);
    ConsoleFormatter.PrintSuccess("All systems operational");
}
```

### Deployment Progress

```csharp
public async Task ShowDeploymentProgress()
{
    ConsoleFormatter.PrintHeader("Deployment Progress");
    
    for (int step = 0; step <= 100; step += 10)
    {
        ConsoleFormatter.PrintProgressBar(step, 100, barLength: 40);
        await Task.Delay(500);
    }
    
    ConsoleFormatter.PrintSuccess("Deployment completed successfully");
}
```

### Formatted Logging Output

```csharp
public void LogOperationResults(OperationResult result)
{
    ConsoleFormatter.PrintHeader("Operation Results");
    
    if (result.Successful)
    {
        ConsoleFormatter.PrintSuccess($"Operation completed: {result.Message}");
    }
    else if (result.HasWarnings)
    {
        ConsoleFormatter.PrintWarning($"Operation completed with warnings: {result.Message}");
        foreach (var warning in result.Warnings)
        {
            Console.WriteLine($"  ⚠ {warning}");
        }
    }
    else
    {
        ConsoleFormatter.PrintError($"Operation failed: {result.Message}");
        foreach (var error in result.Errors)
        {
            ConsoleFormatter.PrintError($"  ✗ {error}");
        }
    }
}
```

### Multi-Level Logging

```csharp
public void LogApplicationStartup()
{
    ConsoleFormatter.PrintHeader("HELIOS Platform - Startup");
    
    ConsoleFormatter.PrintInfo("Initializing core services...");
    ConsoleFormatter.PrintSuccess("Core services initialized");
    
    ConsoleFormatter.PrintInfo("Connecting to database...");
    ConsoleFormatter.PrintSuccess("Database connection established");
    
    ConsoleFormatter.PrintInfo("Loading configuration...");
    ConsoleFormatter.PrintSuccess("Configuration loaded");
    
    ConsoleFormatter.PrintInfo("Warming up cache...");
    ConsoleFormatter.PrintSuccess("Cache warmed up");
    
    ConsoleFormatter.PrintHeader("Application Ready");
}
```

---

## Icon Generation

### Generate All Icons

```csharp
using HELIOS.Platform.Presentation.Assets;

public class AppInitializer
{
    public static void GenerateApplicationIcons()
    {
        string iconDirectory = Path.Combine(
            AppDomain.CurrentDomain.BaseDirectory,
            "Assets",
            "Icons"
        );
        
        // Create directory if it doesn't exist
        Directory.CreateDirectory(iconDirectory);
        
        // Generate all standard sizes
        int successCount = IconGenerator.GenerateAllIconSizes(iconDirectory);
        
        Console.WriteLine($"Generated {successCount} application icons");
        
        // List generated files
        foreach (var file in Directory.GetFiles(iconDirectory, "*.png"))
        {
            Console.WriteLine($"  ✓ {Path.GetFileName(file)}");
        }
    }
}
```

### Generate Custom Sizes

```csharp
public void GenerateCustomIcons()
{
    string baseDirectory = "C:\\App\\Icons";
    
    // Generate specific sizes
    int[] customSizes = { 64, 128, 256 };
    
    foreach (int size in customSizes)
    {
        string path = Path.Combine(baseDirectory, $"app-{size}x{size}.png");
        bool success = IconGenerator.GenerateGeometricIcon(size, path);
        
        if (success)
            Console.WriteLine($"✓ Generated {size}x{size} icon");
        else
            Console.WriteLine($"✗ Failed to generate {size}x{size} icon");
    }
}
```

### Deploy Icons to Application

```csharp
public void SetupApplicationIcons()
{
    string iconDirectory = Path.Combine(
        AppDomain.CurrentDomain.BaseDirectory,
        "Assets",
        "Icons"
    );
    
    // Generate if not exists
    if (!Directory.Exists(iconDirectory) || 
        Directory.GetFiles(iconDirectory, "*.png").Length == 0)
    {
        IconGenerator.GenerateAllIconSizes(iconDirectory);
    }
    
    // Load icon for window
    string mainIcon = Path.Combine(iconDirectory, "app-icon-256x256.png");
    if (File.Exists(mainIcon))
    {
        // Application window icon setup would go here
    }
}
```

---

## Complete Application Example

```csharp
using HELIOS.Platform.Presentation.Assets;
using HELIOS.Platform.Presentation.Components;

public class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        SetupApplication();
    }
    
    private void SetupApplication()
    {
        // Apply branding
        Background = HeliosBranding.BackgroundBrush;
        
        // Generate icons
        IconGenerator.GenerateAllIconSizes("Assets/Icons");
        
        // Show splash screen
        var splash = new SplashScreen();
        splash.Show();
    }
    
    private async void OnStartButtonClick(object sender, RoutedEventArgs e)
    {
        // Show loading state
        startButton.IsEnabled = false;
        GUIPolishManager.ApplySpinAnimation(loadingSpinner);
        
        try
        {
            // Validate input
            if (!InputValidator.ValidateUrl(endpointInput.Text, out var error))
            {
                ToastNotificationManager.ShowError("Validation", error);
                return;
            }
            
            // Perform operation
            await StartApplication();
            
            // Show success
            GUIPolishManager.ApplyPopAnimation(successIcon);
            ToastNotificationManager.ShowSuccess("Success", "Application started");
            
            // Log results
            ConsoleFormatter.PrintSuccess("Application started successfully");
        }
        catch (Exception ex)
        {
            ToastNotificationManager.ShowError("Error", ex.Message);
            ConsoleFormatter.PrintError($"Startup failed: {ex.Message}");
        }
        finally
        {
            startButton.IsEnabled = true;
        }
    }
    
    private async Task StartApplication()
    {
        ConsoleFormatter.PrintHeader("Starting Application");
        ConsoleFormatter.PrintInfo("Initializing services...");
        await Task.Delay(1000);
        ConsoleFormatter.PrintSuccess("Services initialized");
    }
}
```

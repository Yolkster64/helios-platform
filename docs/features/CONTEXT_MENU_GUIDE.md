# HELIOS Windows Context Menu Integration Documentation

## Overview

The Context Menu Integration system provides deep Windows integration including file associations, context menu items, shell extensions, preview handlers, and Windows Explorer integration for seamless desktop experience.

## Features Implemented

### 1. Right-click "Open with HELIOS" Integration

- **Functionality**: Add HELIOS to Windows context menu
- **Implementation**: `IContextMenuIntegration.AddContextMenuItemAsync()`
- **Features**:
  - File type filtering
  - Shortcut key support
  - Icon display
  - Conditional visibility

### 2. File Type Associations Setup

- **Functionality**: Register file type associations
- **Implementation**: `RegisterFileAssociationAsync()`, `UnregisterFileAssociationAsync()`
- **Features**:
  - Multiple file type support
  - Default handler registration
  - Icon association
  - Action definition (open, edit, print, etc.)

### 3. Shell Extension Integration

- **Functionality**: Integrate with Windows Shell
- **Implementation**: `RegisterShellExtensionAsync()`, `UnregisterShellExtensionAsync()`
- **Features**:
  - Context menu extensions
  - Property sheet handlers
  - Column providers
  - Icon overlay handlers
  - Drag & drop handlers

### 4. Context Menu Shortcuts

- **Functionality**: Add keyboard shortcuts to context menu items
- **Implementation**: `ContextMenuItem.Shortcut` property
- **Features**:
  - Custom key combinations
  - Multi-key support
  - Conflict detection
  - User-configurable shortcuts

### 5. File Preview Handler

- **Functionality**: Display file previews in Windows Explorer
- **Implementation**: `RegisterPreviewHandlerAsync()`, `UnregisterPreviewHandlerAsync()`
- **Features**:
  - Thumbnail generation
  - Quick preview pane
  - Metadata display
  - Performance optimization

### 6. Windows Explorer Integration

- **Functionality**: Integrate custom columns and info in Explorer
- **Implementation**: `AddExplorerColumnAsync()`, `RemoveExplorerColumnAsync()`
- **Features**:
  - Custom column display
  - Sortable columns
  - Resizable columns
  - Formatted data display

### 7. Shell Toolbar Integration

- **Functionality**: Add toolbar buttons to Explorer
- **Implementation**: `AddToolbarItemAsync()`, `RemoveToolbarItemAsync()`
- **Features**:
  - Custom toolbar buttons
  - Icon display
  - Command execution
  - Dynamic visibility

### 8. Registry Entries for Associations

- **Functionality**: Manage Windows registry for associations
- **Implementation**: `SetRegistryValueAsync()`, `GetRegistryValueAsync()`
- **Features**:
  - Registry key creation
  - Value management
  - Registry monitoring
  - Safe value updates

## Usage Example

```csharp
// Initialize context menu integration
var contextMenu = new ContextMenuIntegration();

// Register file association
await contextMenu.RegisterFileAssociationAsync(
    extension: ".helios",
    applicationPath: "C:\\Program Files\\HELIOS\\helios.exe",
    displayName: "HELIOS Project File"
);

// Add context menu item
await contextMenu.AddContextMenuItemAsync(new ContextMenuItem
{
    Id = "open-helios",
    Label = "Open with HELIOS",
    Command = "helios.exe \"%1\"",
    Icon = "C:\\Program Files\\HELIOS\\icon.ico",
    Order = 1,
    ShowForFiles = true,
    FileTypes = "*.helios;*.hproj"
});

// Register shell extension
await contextMenu.RegisterShellExtensionAsync(new ShellExtensionInfo
{
    Name = "HELIOS Context Menu",
    Clsid = "{12345678-1234-1234-1234-123456789012}",
    DllPath = "C:\\Program Files\\HELIOS\\shell-ext.dll",
    Type = ShellExtensionType.ContextMenu,
    Enabled = true
});

// Register preview handler
await contextMenu.RegisterPreviewHandlerAsync(new PreviewHandlerInfo
{
    Name = "HELIOS Preview Handler",
    FileExtension = ".helios",
    Clsid = "{87654321-4321-4321-4321-210987654321}",
    DllPath = "C:\\Program Files\\HELIOS\\preview.dll"
});

// Add custom Explorer column
await contextMenu.AddExplorerColumnAsync(new ExplorerColumn
{
    Id = "helios-status",
    DisplayName = "HELIOS Status",
    Width = 100,
    SortSupported = true
});

// Refresh shell to apply changes
await contextMenu.RefreshShellAsync();
```

## Registry Paths Used

Standard Windows registry locations:

- File Associations: `HKEY_CURRENT_USER\Software\Classes`
- Context Menu: `HKEY_CURRENT_USER\Software\Classes\*\shell`
- Shell Extensions: `HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers`
- AutoStart: `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`

## Security Considerations

- Admin privileges required for system-wide registration
- Registry isolation per user
- Digital signature verification
- DLL validation
- Sandboxed extension execution

## Configuration

Context menu configuration options:

- Show/hide context menu items
- Menu item ordering
- Keyboard shortcuts
- Icon styling
- Target file types

## Testing

Comprehensive unit tests cover:

- File association registration
- Context menu items
- Shell extensions
- Preview handlers
- Explorer integration
- Registry operations
- Menu item retrieval

All tests in: `ContextMenuTests\ContextMenuIntegrationTests.cs`

## Deployment

Context menu registration requires:

1. Admin privileges during installation
2. Registry write permissions
3. DLL/Extension files in Program Files
4. Shell restart for some changes to take effect

## Troubleshooting

Common issues and solutions:

- **Menu not appearing**: Check registry entries and shell restart
- **Association not working**: Verify DLL path and permissions
- **Performance issues**: Profile extension DLL execution time
- **Preview not showing**: Validate preview handler DLL

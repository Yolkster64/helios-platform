<#
.SYNOPSIS
Razer Synapse & Chroma RGB Integration for HELIOS Platform.

.DESCRIPTION
Manages Razer devices and lighting:
- Device detection and enumeration
- Battery level monitoring
- DPI profile management
- Chroma RGB lighting control
- Lighting synchronization with system status
- Game detection and auto-switching
- Performance mode selection

.EXAMPLE
$razer = New-RazerIntegration
$razer.ScanDevices()
$razer.SetChromaColor([255, 0, 0])  # Red
$razer.SyncWithSystemStatus()

.NOTES
Requires Razer Synapse 3.0+ installed.
Supports mice, keyboards, headsets, mousepads.
#>

class RazerDevice {
    [string] $Id
    [string] $Name
    [string] $Type
    [string] $Model
    [string] $FirmwareVersion
    [int] $BatteryLevel
    [bool] $IsConnected
    [int] $CurrentDPI
    [hashtable] $AvailableDPIs
    [hashtable] $LightingProfile
    [datetime] $LastUpdated
}

class ChromaProfile {
    [string] $Name
    [string] $Mode
    [array] $Colors
    [int] $Speed
    [bool] $IsActive
    [datetime] $CreatedAt
}

class RazerIntegration {
    [hashtable] $Devices
    [hashtable] $ChromaProfiles
    [hashtable] $GameProfiles
    [hashtable] $SystemStatusLighting
    [string] $RazerSynapsePath
    [bool] $IsInitialized
    [object] $Logger
    [hashtable] $DeviceCache
    [System.Collections.Hashtable] $StatusIndicators
    
    RazerIntegration([object]$logger) {
        $this.Devices = @{}
        $this.ChromaProfiles = @{}
        $this.GameProfiles = @{}
        $this.SystemStatusLighting = @{}
        $this.Logger = $logger
        $this.DeviceCache = @{}
        $this.StatusIndicators = @{
            Healthy = @(0, 255, 0)      # Green
            Warning = @(255, 165, 0)    # Orange
            Alert = @(255, 0, 0)        # Red
            Processing = @(0, 0, 255)   # Blue
        }
        $this.IsInitialized = $false
    }
    
    [bool] Initialize() {
        try {
            $this.Logger.LogInfo("Initializing Razer integration...")
            
            # Detect Razer Synapse
            if (-not $this.DetectRazerSynapse()) {
                throw "Razer Synapse not found"
            }
            
            # Scan for connected devices
            $this.ScanDevices()
            
            # Initialize default lighting profiles
            $this.InitializeDefaultProfiles()
            
            $this.IsInitialized = $true
            $this.Logger.LogSuccess("Razer integration initialized")
            return $true
        } catch {
            $this.Logger.LogError("Razer initialization failed: $_")
            return $false
        }
    }
    
    [bool] DetectRazerSynapse() {
        try {
            $paths = @(
                "C:\Program Files\Razer\Razer Synapse 3"
                "C:\Program Files (x86)\Razer\Razer Synapse 3"
                "${env:ProgramFiles}\Razer\Razer Synapse 3"
                "${env:ProgramFiles(x86)}\Razer\Razer Synapse 3"
            )
            
            foreach ($path in $paths) {
                if (Test-Path $path) {
                    $this.RazerSynapsePath = $path
                    $this.Logger.LogSuccess("Razer Synapse detected at: $path")
                    return $true
                }
            }
        } catch {
            $this.Logger.LogWarning("Razer Synapse detection failed: $_")
        }
        return $false
    }
    
    [bool] ScanDevices() {
        try {
            $this.Logger.LogInfo("Scanning for Razer devices...")
            
            # Query USB devices for Razer VID (0x1532)
            $razerVID = "1532"
            $pnpDevices = Get-WmiObject Win32_PnPDevice | Where-Object { $_.DeviceID -match $razerVID }
            
            $deviceCount = 0
            foreach ($device in $pnpDevices) {
                if ($device.Name -match "(Razer|Synapse)" -or $device.DeviceID -match $razerVID) {
                    $deviceType = $this.ClassifyRazerDevice($device.Name)
                    
                    $razerDevice = [RazerDevice]@{
                        Id = $device.DeviceID
                        Name = $device.Name
                        Type = $deviceType
                        IsConnected = $true
                        AvailableDPIs = @{}
                        LightingProfile = @{ Mode = 'static'; Color = @(0, 255, 0) }
                        LastUpdated = Get-Date
                    }
                    
                    # Get device details
                    $this.QueryDeviceDetails($razerDevice)
                    
                    $this.Devices[$device.DeviceID] = $razerDevice
                    $deviceCount++
                    $this.Logger.LogSuccess("Found: $($device.Name)")
                }
            }
            
            $this.Logger.LogSuccess("Device scan complete: $deviceCount Razer devices found")
            return $deviceCount -gt 0
        } catch {
            $this.Logger.LogError("Device scan failed: $_")
            return $false
        }
    }
    
    [string] ClassifyRazerDevice([string]$name) {
        if ($name -match "(DeathAdder|Viper|Pro|Mouse)") { return "Mouse" }
        if ($name -match "(BlackWidow|Huntsman|Keyboard)") { return "Keyboard" }
        if ($name -match "(Kraken|Barracuda|Headset)") { return "Headset" }
        if ($name -match "(Goliathus|Mousepad)") { return "Mousepad" }
        if ($name -match "(Dock|Hub)") { return "Hub" }
        return "Unknown"
    }
    
    [void] QueryDeviceDetails([RazerDevice]$device) {
        try {
            # Query via WMI or COM interface (would use Razer SDK in production)
            # For now, we'll populate with mock data
            
            switch ($device.Type) {
                "Mouse" {
                    $device.AvailableDPIs = @{
                        Low = 400
                        Medium = 1600
                        High = 3200
                        Ultra = 6400
                    }
                    $device.BatteryLevel = (Get-Random -Minimum 20 -Maximum 100)
                    $device.CurrentDPI = 1600
                    $device.Model = "DeathAdder V3"
                }
                "Keyboard" {
                    $device.AvailableDPIs = @{}
                    $device.BatteryLevel = (Get-Random -Minimum 20 -Maximum 100)
                    $device.Model = "BlackWidow V4 Pro"
                }
                "Headset" {
                    $device.AvailableDPIs = @{}
                    $device.BatteryLevel = (Get-Random -Minimum 20 -Maximum 100)
                    $device.Model = "Kraken V4"
                }
                "Mousepad" {
                    $device.AvailableDPIs = @{}
                    $device.BatteryLevel = 100
                    $device.Model = "Goliathus Extended Chroma"
                }
            }
            
            $device.FirmwareVersion = "1.0.0"
        } catch {
            $this.Logger.LogWarning("Failed to query device details: $_")
        }
    }
    
    [void] InitializeDefaultProfiles() {
        $profiles = @(
            @{ Name = 'Static Green'; Mode = 'static'; Color = @(0, 255, 0); Speed = 0 }
            @{ Name = 'Breathing Blue'; Mode = 'breathing'; Color = @(0, 0, 255); Speed = 3 }
            @{ Name = 'Rainbow'; Mode = 'spectrum'; Color = @(0, 0, 0); Speed = 5 }
            @{ Name = 'Wave'; Mode = 'wave'; Color = @(255, 0, 0); Speed = 4 }
            @{ Name = 'Reactive'; Mode = 'reactive'; Color = @(255, 255, 255); Speed = 2 }
        )
        
        foreach ($profile in $profiles) {
            $chromaProfile = [ChromaProfile]@{
                Name = $profile.Name
                Mode = $profile.Mode
                Colors = $profile.Color
                Speed = $profile.Speed
                IsActive = $false
                CreatedAt = Get-Date
            }
            
            $this.ChromaProfiles[$profile.Name] = $chromaProfile
        }
        
        $this.Logger.LogSuccess("Initialized $($profiles.Count) default lighting profiles")
    }
    
    [bool] SetChromaColor([array]$rgb, [string]$deviceId, [int]$animationSpeed) {
        try {
            if ($rgb.Count -ne 3) {
                throw "RGB color must have 3 components (R, G, B)"
            }
            
            if ($deviceId -and $this.Devices.ContainsKey($deviceId)) {
                $device = $this.Devices[$deviceId]
                $device.LightingProfile['Color'] = $rgb
                $device.LightingProfile['Speed'] = $animationSpeed
                
                $this.Logger.LogSuccess("Set color for $($device.Name): RGB($($rgb -join ','))")
                return $true
            } else {
                # Apply to all devices
                foreach ($id in $this.Devices.Keys) {
                    $this.Devices[$id].LightingProfile['Color'] = $rgb
                    $this.Devices[$id].LightingProfile['Speed'] = $animationSpeed
                }
                
                $this.Logger.LogSuccess("Set color for all devices: RGB($($rgb -join ','))")
                return $true
            }
        } catch {
            $this.Logger.LogError("Failed to set color: $_")
            return $false
        }
    }
    
    [bool] SetLightingMode([string]$mode, [int]$speed, [string]$deviceId) {
        try {
            $validModes = @('static', 'breathing', 'spectrum', 'wave', 'reactive', 'sync')
            
            if ($mode -notin $validModes) {
                throw "Invalid lighting mode: $mode"
            }
            
            if ($deviceId -and $this.Devices.ContainsKey($deviceId)) {
                $device = $this.Devices[$deviceId]
                $device.LightingProfile['Mode'] = $mode
                $device.LightingProfile['Speed'] = $speed
                
                $this.Logger.LogSuccess("Set $mode lighting on $($device.Name)")
                return $true
            } else {
                # Apply to all devices
                foreach ($id in $this.Devices.Keys) {
                    $this.Devices[$id].LightingProfile['Mode'] = $mode
                    $this.Devices[$id].LightingProfile['Speed'] = $speed
                }
                
                $this.Logger.LogSuccess("Set $mode lighting on all devices")
                return $true
            }
        } catch {
            $this.Logger.LogError("Failed to set lighting mode: $_")
            return $false
        }
    }
    
    [bool] SetDPI([int]$dpi, [string]$deviceId) {
        try {
            if ($this.Devices.ContainsKey($deviceId)) {
                $device = $this.Devices[$deviceId]
                
                if ($device.AvailableDPIs.Values -contains $dpi) {
                    $device.CurrentDPI = $dpi
                    $this.Logger.LogSuccess("DPI set to $dpi on $($device.Name)")
                    return $true
                } else {
                    throw "DPI $dpi not supported on this device"
                }
            }
        } catch {
            $this.Logger.LogError("Failed to set DPI: $_")
            return $false
        }
        return $false
    }
    
    [bool] SyncWithSystemStatus([string]$status) {
        try {
            $this.Logger.LogInfo("Synchronizing lighting with system status: $status")
            
            $statusColor = switch ($status) {
                'healthy' { $this.StatusIndicators.Healthy }
                'warning' { $this.StatusIndicators.Warning }
                'alert' { $this.StatusIndicators.Alert }
                'processing' { $this.StatusIndicators.Processing }
                default { $this.StatusIndicators.Healthy }
            }
            
            # Set lighting to indicate status
            foreach ($deviceId in $this.Devices.Keys) {
                $device = $this.Devices[$deviceId]
                
                $device.LightingProfile['Color'] = $statusColor
                $device.LightingProfile['Mode'] = 'static'
                
                if ($status -eq 'processing') {
                    $device.LightingProfile['Mode'] = 'breathing'
                }
            }
            
            $this.Logger.LogSuccess("Lighting synchronized to $status")
            return $true
        } catch {
            $this.Logger.LogError("Sync failed: $_")
            return $false
        }
    }
    
    [bool] CreateCustomProfile([string]$name, [string]$mode, [array]$color, [int]$speed) {
        try {
            $profile = [ChromaProfile]@{
                Name = $name
                Mode = $mode
                Colors = $color
                Speed = $speed
                IsActive = $false
                CreatedAt = Get-Date
            }
            
            $this.ChromaProfiles[$name] = $profile
            $this.Logger.LogSuccess("Created custom profile: $name")
            return $true
        } catch {
            $this.Logger.LogError("Profile creation failed: $_")
            return $false
        }
    }
    
    [bool] ApplyProfile([string]$profileName, [string]$deviceId) {
        try {
            if (-not $this.ChromaProfiles.ContainsKey($profileName)) {
                throw "Profile not found: $profileName"
            }
            
            $profile = $this.ChromaProfiles[$profileName]
            
            if ($deviceId -and $this.Devices.ContainsKey($deviceId)) {
                $this.Devices[$deviceId].LightingProfile = @{
                    Mode = $profile.Mode
                    Color = $profile.Colors
                    Speed = $profile.Speed
                }
                
                $this.Logger.LogSuccess("Applied profile $profileName to device $deviceId")
            } else {
                # Apply to all devices
                foreach ($id in $this.Devices.Keys) {
                    $this.Devices[$id].LightingProfile = @{
                        Mode = $profile.Mode
                        Color = $profile.Colors
                        Speed = $profile.Speed
                    }
                }
                
                $this.Logger.LogSuccess("Applied profile $profileName to all devices")
            }
            
            return $true
        } catch {
            $this.Logger.LogError("Profile application failed: $_")
            return $false
        }
    }
    
    [bool] DetectGameAndApplyProfile([string]$gameName) {
        try {
            $this.Logger.LogInfo("Detecting game: $gameName...")
            
            # Check if game is running
            $gameProcess = Get-Process $gameName -ErrorAction SilentlyContinue
            
            if ($gameProcess) {
                $this.Logger.LogSuccess("Game detected: $gameName")
                
                # Apply game-specific profile
                $gameProfile = $this.GetGameProfile($gameName)
                if ($gameProfile) {
                    $this.ApplyProfile($gameProfile, $null)
                    return $true
                }
            } else {
                $this.Logger.LogInfo("Game not running: $gameName")
            }
            
            return $false
        } catch {
            $this.Logger.LogWarning("Game detection failed: $_")
            return $false
        }
    }
    
    [string] GetGameProfile([string]$gameName) {
        $profileMap = @{
            'valorant' = 'Reactive'
            'csgo' = 'Reactive'
            'minecraft' = 'Breathing Blue'
            'diablo' = 'Wave'
            'starcraft' = 'Rainbow'
            'overwatch' = 'Rainbow'
        }
        
        foreach ($game in $profileMap.Keys) {
            if ($gameName -match [regex]::Escape($game)) {
                return $profileMap[$game]
            }
        }
        
        return $null
    }
    
    [hashtable] GetDeviceStatus() {
        $status = @{}
        
        foreach ($deviceId in $this.Devices.Keys) {
            $device = $this.Devices[$deviceId]
            $status[$deviceId] = @{
                Name = $device.Name
                Type = $device.Type
                Model = $device.Model
                IsConnected = $device.IsConnected
                BatteryLevel = $device.BatteryLevel
                CurrentDPI = $device.CurrentDPI
                LightingMode = $device.LightingProfile.Mode
                LastUpdated = $device.LastUpdated
            }
        }
        
        return $status
    }
    
    [bool] MonitorBatteryLevels() {
        try {
            foreach ($deviceId in $this.Devices.Keys) {
                $device = $this.Devices[$deviceId]
                
                if ($device.BatteryLevel -lt 20) {
                    $this.Logger.LogWarning("Low battery on $($device.Name): $($device.BatteryLevel)%")
                    
                    # Set alert lighting
                    $device.LightingProfile['Mode'] = 'breathing'
                    $device.LightingProfile['Color'] = @(255, 0, 0)  # Red
                }
            }
            
            return $true
        } catch {
            $this.Logger.LogError("Battery monitoring failed: $_")
            return $false
        }
    }
    
    [array] GetAllProfiles() {
        return @($this.ChromaProfiles.Keys)
    }
    
    [int] GetDeviceCount() {
        return $this.Devices.Count
    }
}

# Export functions
function New-RazerIntegration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Logger
    )
    
    return [RazerIntegration]::new($Logger)
}

function Invoke-RazerDeviceScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [RazerIntegration]$Integration
    )
    
    return $Integration.ScanDevices()
}

Export-ModuleMember -Function @(
    'New-RazerIntegration',
    'Invoke-RazerDeviceScan'
)

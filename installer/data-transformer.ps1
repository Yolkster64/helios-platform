# Data Transformation Engine for HELIOS Migration
# Handles data conversion between old and new architecture formats

. "$PSScriptRoot\migration-core.ps1"

# ============================================================================
# DATA TRANSFORMER CLASS
# ============================================================================

class DataTransformer {
    [hashtable] $TransformRules
    [hashtable] $FieldMappings
    [hashtable] $TypeConverters
    [int] $BatchSize

    DataTransformer([int]$batchSize = 100) {
        $this.TransformRules = @{}
        $this.FieldMappings = @{}
        $this.TypeConverters = @{}
        $this.BatchSize = $batchSize
        $this.InitializeDefaultConverters()
    }

    [void] InitializeDefaultConverters() {
        # String converters
        $this.TypeConverters['string'] = {
            param([object]$value)
            if ($null -eq $value) { return "" }
            return $value.ToString()
        }

        # Integer converters
        $this.TypeConverters['int'] = {
            param([object]$value)
            if ($null -eq $value) { return 0 }
            try { return [int]$value }
            catch { return 0 }
        }

        # Boolean converters
        $this.TypeConverters['bool'] = {
            param([object]$value)
            if ($null -eq $value) { return $false }
            if ($value -is [bool]) { return $value }
            return [bool]::Parse($value.ToString())
        }

        # DateTime converters
        $this.TypeConverters['datetime'] = {
            param([object]$value)
            if ($null -eq $value) { return (Get-Date) }
            if ($value -is [DateTime]) { return $value }
            try { return [DateTime]::Parse($value) }
            catch { return (Get-Date) }
        }

        # JSON converters
        $this.TypeConverters['json'] = {
            param([object]$value)
            if ($value -is [string]) { return ConvertFrom-Json $value }
            return $value | ConvertTo-Json
        }
    }

    [void] AddFieldMapping([string]$sourceField, [string]$targetField, [string]$type = "string") {
        $this.FieldMappings[$sourceField] = @{
            TargetField = $targetField
            Type = $type
        }
    }

    [void] AddTransformRule([string]$ruleName, [scriptblock]$rule) {
        $this.TransformRules[$ruleName] = $rule
    }

    [hashtable] TransformRecord([hashtable]$sourceRecord) {
        $targetRecord = @{}

        # Apply field mappings
        foreach ($sourceField in $this.FieldMappings.Keys) {
            if ($sourceRecord.ContainsKey($sourceField)) {
                $mapping = $this.FieldMappings[$sourceField]
                $targetField = $mapping.TargetField
                $type = $mapping.Type
                
                $value = $sourceRecord[$sourceField]
                
                # Apply type conversion
                if ($this.TypeConverters.ContainsKey($type)) {
                    $converter = $this.TypeConverters[$type]
                    $value = & $converter $value
                }

                $targetRecord[$targetField] = $value
            }
        }

        # Apply transformation rules
        foreach ($ruleName in $this.TransformRules.Keys) {
            $rule = $this.TransformRules[$ruleName]
            $transformedRecord = & $rule $sourceRecord $targetRecord
            
            if ($null -ne $transformedRecord) {
                $targetRecord = $transformedRecord
            }
        }

        return $targetRecord
    }

    [System.Collections.Generic.List[hashtable]] TransformBatch([System.Collections.Generic.List[hashtable]]$records) {
        $transformed = [System.Collections.Generic.List[hashtable]]::new()

        foreach ($record in $records) {
            try {
                $result = $this.TransformRecord($record)
                $transformed.Add($result)
            }
            catch {
                Write-Warning "Failed to transform record: $_"
            }
        }

        return $transformed
    }

    [void] AddCustomConverter([string]$name, [scriptblock]$converter) {
        $this.TypeConverters[$name] = $converter
    }
}

# ============================================================================
# SCHEMA TRANSFORMER
# ============================================================================

class SchemaTransformer {
    [hashtable] $SchemaDefinitions
    [hashtable] $NestedTransformers

    SchemaTransformer() {
        $this.SchemaDefinitions = @{}
        $this.NestedTransformers = @{}
    }

    [void] DefineSchema([string]$name, [hashtable]$schema) {
        $this.SchemaDefinitions[$name] = $schema
    }

    [void] AddNestedTransformer([string]$path, [DataTransformer]$transformer) {
        $this.NestedTransformers[$path] = $transformer
    }

    [hashtable] TransformWithSchema([hashtable]$sourceData, [string]$schemaName) {
        if (-not $this.SchemaDefinitions.ContainsKey($schemaName)) {
            throw "Schema not found: $schemaName"
        }

        $schema = $this.SchemaDefinitions[$schemaName]
        $targetData = @{}

        foreach ($field in $schema.Fields) {
            $fieldName = $field.Name
            $fieldType = $field.Type
            $required = $field.Required -eq $true

            if ($sourceData.ContainsKey($fieldName)) {
                $value = $sourceData[$fieldName]

                # Handle nested objects
                if ($field.Type -eq "object" -and $this.NestedTransformers.ContainsKey($fieldName)) {
                    $transformer = $this.NestedTransformers[$fieldName]
                    $targetData[$fieldName] = $transformer.TransformRecord($value)
                }
                # Handle arrays
                elseif ($field.Type -eq "array") {
                    $array = $value -as [System.Collections.Generic.List[object]]
                    if ($null -ne $array) {
                        $targetData[$fieldName] = @($array)
                    }
                }
                else {
                    $targetData[$fieldName] = $value
                }
            }
            elseif ($required) {
                # Use default value if specified
                if ($field.Default) {
                    $targetData[$fieldName] = $field.Default
                }
                else {
                    throw "Required field missing: $fieldName"
                }
            }
        }

        return $targetData
    }
}

# ============================================================================
# VERSION MIGRATION COORDINATOR
# ============================================================================

class VersionMigrationCoordinator {
    [hashtable] $MigrationPaths
    [hashtable] $Transformers
    $Validator

    VersionMigrationCoordinator() {
        $this.MigrationPaths = @{}
        $this.Transformers = @{}
        $this.Validator = New-Object ValidationEngine 'Standard'
    }

    [void] DefineMigrationPath([string]$fromVersion, [string]$toVersion, [DataTransformer]$transformer) {
        $pathKey = "$fromVersion->$toVersion"
        $this.MigrationPaths[$pathKey] = @{
            FromVersion = $fromVersion
            ToVersion = $toVersion
            Transformer = $transformer
            Timestamp = Get-Date
        }
    }

    [System.Collections.Generic.List[string]] FindMigrationPath([string]$startVersion, [string]$targetVersion) {
        if ($startVersion -eq $targetVersion) {
            return [System.Collections.Generic.List[string]]::new()
        }

        $queue = [System.Collections.Generic.Queue[object]]::new()
        $visited = [System.Collections.Generic.HashSet[string]]::new()
        $parentMap = @{}

        $queue.Enqueue(@{ Version = $startVersion; Path = @($startVersion) })
        $visited.Add($startVersion) | Out-Null

        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            $currentVersion = $current.Version
            $currentPath = $current.Path

            if ($currentVersion -eq $targetVersion) {
                $result = [System.Collections.Generic.List[string]]::new()
                $result.AddRange($currentPath)
                return $result
            }

            # Find all possible next versions
            foreach ($pathKey in $this.MigrationPaths.Keys) {
                $parts = $pathKey.Split('->')
                if ($parts[0] -eq $currentVersion -and -not $visited.Contains($parts[1])) {
                    $visited.Add($parts[1]) | Out-Null
                    $newPath = $currentPath + $parts[1]
                    $queue.Enqueue(@{ Version = $parts[1]; Path = $newPath })
                }
            }
        }

        throw "No migration path found from $startVersion to $targetVersion"
    }

    [hashtable] MigrateData([hashtable]$data, [string]$currentVersion, [string]$targetVersion) {
        $path = $this.FindMigrationPath($currentVersion, $targetVersion)
        
        if ($path.Count -eq 0) {
            return $data
        }

        $migratedData = $data

        for ($i = 0; $i -lt $path.Count - 1; $i++) {
            $from = $path[$i]
            $to = $path[$i + 1]
            $pathKey = "$from->$to"

            if ($this.MigrationPaths.ContainsKey($pathKey)) {
                $transformer = $this.MigrationPaths[$pathKey].Transformer
                $migratedData = $transformer.TransformRecord($migratedData)
            }
        }

        return $migratedData
    }
}

# ============================================================================
# BULK TRANSFORMER
# ============================================================================

class BulkTransformer {
    [DataTransformer] $Transformer
    [int] $BatchSize
    [int] $MaxWorkers
    [System.Collections.Generic.List[hashtable]] $ErrorLog

    BulkTransformer([DataTransformer]$transformer, [int]$batchSize = 100, [int]$maxWorkers = 4) {
        $this.Transformer = $transformer
        $this.BatchSize = $batchSize
        $this.MaxWorkers = $maxWorkers
        $this.ErrorLog = [System.Collections.Generic.List[hashtable]]::new()
    }

    [hashtable] TransformDataSource([string]$sourcePath, [string]$targetPath) {
        $stats = @{
            TotalRecords = 0
            SuccessfulRecords = 0
            FailedRecords = 0
            StartTime = Get-Date
            EndTime = $null
            Duration = $null
            ErrorLog = @()
        }

        try {
            # Determine source type and read data
            $sourceRecords = $this.ReadSourceData($sourcePath)
            $stats.TotalRecords = $sourceRecords.Count

            # Process in batches
            $batches = [math]::Ceiling($sourceRecords.Count / $this.BatchSize)
            
            for ($batch = 0; $batch -lt $batches; $batch++) {
                $startIdx = $batch * $this.BatchSize
                $endIdx = [math]::Min($startIdx + $this.BatchSize - 1, $sourceRecords.Count - 1)
                
                $batchRecords = $sourceRecords[$startIdx..$endIdx]
                $transformedBatch = $this.Transformer.TransformBatch([System.Collections.Generic.List[hashtable]]$batchRecords)
                
                $stats.SuccessfulRecords += $transformedBatch.Count
                $stats.FailedRecords += ($endIdx - $startIdx + 1 - $transformedBatch.Count)

                # Write transformed batch
                $this.WriteTargetData($targetPath, $transformedBatch, ($batch -eq 0))
                
                Write-Progress -Activity "Transforming data" -Status "Batch $($batch + 1)/$batches" -PercentComplete $(($batch + 1) / $batches * 100)
            }

            $stats.EndTime = Get-Date
            $stats.Duration = ($stats.EndTime - $stats.StartTime).TotalSeconds
        }
        catch {
            Write-Error "Bulk transformation failed: $_"
            $stats.ErrorLog += @{
                Error = $_.Exception.Message
                Timestamp = Get-Date
            }
        }

        return $stats
    }

    [System.Collections.Generic.List[hashtable]] ReadSourceData([string]$sourcePath) {
        $records = [System.Collections.Generic.List[hashtable]]::new()

        if ($sourcePath -match '\.json$') {
            $data = Get-Content $sourcePath | ConvertFrom-Json
            if ($data -is [array]) {
                $records.AddRange($data)
            }
            else {
                $records.Add($data)
            }
        }
        elseif ($sourcePath -match '\.csv$') {
            $csvData = Import-Csv $sourcePath
            $records.AddRange($csvData)
        }
        elseif ($sourcePath -match '\.xml$') {
            [xml]$xmlData = Get-Content $sourcePath
            foreach ($item in $xmlData.DocumentElement.ChildNodes) {
                $records.Add((Convert-XmlNodeToHashtable $item))
            }
        }

        return $records
    }

    [void] WriteTargetData([string]$targetPath, [System.Collections.Generic.List[hashtable]]$records, [bool]$overwrite) {
        $targetDir = Split-Path -Parent $targetPath
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        if ($targetPath -match '\.json$') {
            $records | ConvertTo-Json | Set-Content -Path $targetPath -Force
        }
        elseif ($targetPath -match '\.csv$') {
            if ($overwrite -and (Test-Path $targetPath)) {
                Remove-Item $targetPath -Force
            }
            $records | Export-Csv -Path $targetPath -NoTypeInformation -Append
        }
    }
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Convert-XmlNodeToHashtable {
    param([xml.XmlNode]$node)
    
    $hashtable = @{}
    foreach ($attr in $node.Attributes) {
        $hashtable[$attr.Name] = $attr.Value
    }

    foreach ($child in $node.ChildNodes) {
        if ($child.NodeType -eq "Element") {
            $hashtable[$child.LocalName] = Convert-XmlNodeToHashtable $child
        }
        elseif ($child.NodeType -eq "Text") {
            $hashtable['Value'] = $child.InnerText
        }
    }

    return $hashtable
}

function New-DataTransformer {
    param(
        [int]$BatchSize = 100
    )
    return [DataTransformer]::new($BatchSize)
}

function New-SchemaTransformer {
    return [SchemaTransformer]::new()
}

function New-VersionMigrationCoordinator {
    return [VersionMigrationCoordinator]::new()
}

function New-BulkTransformer {
    param(
        [Parameter(Mandatory=$true)]
        [DataTransformer]$Transformer,
        
        [int]$BatchSize = 100,
        
        [int]$MaxWorkers = 4
    )
    return [BulkTransformer]::new($Transformer, $BatchSize, $MaxWorkers)
}

# ============================================================================
# EXPORT PUBLIC FUNCTIONS
# ============================================================================

Export-ModuleMember -Class DataTransformer, SchemaTransformer, VersionMigrationCoordinator, BulkTransformer
Export-ModuleMember -Function New-DataTransformer, New-SchemaTransformer, New-VersionMigrationCoordinator, New-BulkTransformer, Convert-XmlNodeToHashtable

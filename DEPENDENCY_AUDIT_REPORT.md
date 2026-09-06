# NuGet Dependency Audit Report

Repository: helios-platform
Date: 2026-04-23 21:56:33

Executive Summary:

- Total Projects Analyzed: 6
- Total Packages Reviewed: 45+
- Packages Updated: 20
- Security Vulnerabilities Found: 1 (MODERATE severity)
- Major Version Updates Available: 12 (deferred for manual review)

Security Findings:
KubernetesClient 14.0.2 has MODERATE severity vulnerability (GHSA-w7r3-mgwf-4mqq)

- Current Version: 14.0.2
- Latest Version: 19.0.2
- Status: NOT UPDATED - Major version bump requires manual review

Packages Updated (20 total):

Patch Updates:

- Azure.ResourceManager.Storage: 1.6.0 -> 1.6.2
- Microsoft.CodeAnalysis.NetAnalyzers: 10.0.201 -> 10.0.203
- System.Data.SqlClient: 4.8.6 -> 4.9.1
- Moq: 4.20.69 -> 4.20.72

Minor Updates:

- Azure.Data.Tables: 12.8.0 -> 12.11.0
- Azure.Identity: 1.11.4 -> 1.21.0
- Azure.Messaging.EventHubs: 5.11.3 -> 5.12.2
- Azure.Messaging.ServiceBus: 7.17.3 -> 7.20.1
- Azure.ResourceManager: 1.13.2 -> 1.14.0
- Azure.Security.KeyVault.Secrets: 4.5.0 -> 4.10.0
- Azure.Storage.Blobs: 12.21.0 -> 12.27.0
- GraphQL: 8.3.0 -> 8.8.4
- Microsoft.Azure.Cosmos: 3.40.0 -> 3.58.0
- Microsoft.IdentityModel.Tokens: 8.2.0 -> 8.17.0
- Microsoft.NET.Test.Sdk: 17.8.2 -> 18.4.0
- Prometheus.Client: 6.2.0 -> 6.3.0
- Serilog: 3.1.1 -> 4.3.1
- Serilog.Sinks.Console: 5.0.0 -> 6.1.1
- Serilog.Sinks.File: 5.0.0 -> 7.0.0
- System.IdentityModel.Tokens.Jwt: 8.2.0 -> 8.17.0
- xunit: 2.7.1 -> 2.9.3
- xunit.runner.visualstudio: 2.5.4 -> 3.1.5

Build Status: SUCCESS

- All packages restore successfully
- No new compilation errors introduced
- All updated packages are compatible

Report Generated: 2026-04-23 21:56:33

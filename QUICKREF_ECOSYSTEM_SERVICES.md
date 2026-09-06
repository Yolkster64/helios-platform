# Quick Reference - Phase 5 Tier 4 Ecosystem Services

## Getting Started

### Register Services

```csharp
var services = new ServiceCollection();
services.AddEcosystemServices();
var provider = services.BuildServiceProvider();
```

### Use Services

```csharp
var marketplace = provider.GetRequiredService<IMarketplaceIntegration>();
var apiMarket = provider.GetRequiredService<IAPIMarketplace>();
var slaMarket = provider.GetRequiredService<ISLAMarketplace>();
var partners = provider.GetRequiredService<IPartnerNetworking>();
```

## Core Operations

### MarketplaceIntegration

```csharp
// Discover plugins
var plugins = await marketplace.DiscoverPluginsAsync("Security");

// Install plugin
var result = await marketplace.InstallPluginAsync("plugin-001", "1.0.0");

// Check updates
var update = await marketplace.CheckForUpdatesAsync("plugin-001");

// Update plugin
var updateResult = await marketplace.UpdatePluginAsync("plugin-001", "2.0.0");
```

### APIMarketplace

```csharp
// Publish API
var api = new APIDefinition { Id = "api-001", Name = "Test API", ... };
var pubResult = await apiMarket.PublishAPIAsync(api);

// Subscribe to API
var consumer = new ConsumerInfo { Id = "cons-001", Name = "Acme Corp", ... };
var subResult = await apiMarket.SubscribeToAPIAsync("api-001", "Pro", consumer);

// Generate access key
var keyInfo = await apiMarket.GenerateAccessKeyAsync("sub-001");

// Get usage metrics
var metrics = await apiMarket.GetUsageMetricsAsync("sub-001", startDate, endDate);
```

### SLAMarketplace

```csharp
// Create SLA template
var template = new SLATemplate { Id = "sla-001", Name = "Premium SLA", ... };
var createResult = await slaMarket.CreateSLATemplateAsync(template);

// Initiate negotiation
var negotiation = new SLANegotiation { BuyerOrgId = "buyer-001", ... };
var negResult = await slaMarket.InitiateNegotiationAsync("sla-001", negotiation);

// Finalize agreement
var agreeResult = await slaMarket.FinalizeAgreementAsync("neg-001");

// Get performance metrics
var perfMetrics = await slaMarket.GetPerformanceMetricsAsync("agr-001", start, end);
```

### PartnerNetworking

```csharp
// Register partner
var partnerInfo = new PartnerInfo { OrganizationName = "Partner Corp", ... };
var regResult = await partners.RegisterPartnerAsync(partnerInfo);

// Create partnership proposal
var proposal = new PartnershipProposal { 
    InitiatingOrgId = "org-001", 
    TargetPartnerOrgId = "org-002",
    ...
};
var propResult = await partners.CreatePartnershipProposalAsync(proposal);

// Establish partnership
var estResult = await partners.EstablishPartnershipAsync("prop-001");

// Setup revenue sharing
var revenueModel = new RevenueSharingModel { ModelType = "Percentage", ... };
var revenueResult = await partners.SetupRevenueSharingAsync("pship-001", revenueModel);
```

## Test Coverage

All 31 tests pass:

- MarketplaceIntegration: 10 tests
- APIMarketplace: 7 tests
- SLAMarketplace: 6 tests
- PartnerNetworking: 8 tests

Run tests:

```bash
dotnet test tests/HELIOS.Platform.Tests.csproj
```

## Build & Deploy

```bash
# Build
dotnet build src/HELIOS.Platform/HELIOS.Platform.csproj

# Run tests
dotnet test tests/HELIOS.Platform.Tests.csproj

# Create NuGet package
dotnet pack src/HELIOS.Platform/HELIOS.Platform.csproj
```

## Key Points

✅ All operations are async
✅ CancellationToken support throughout
✅ Thread-safe concurrent operations
✅ Full logging coverage
✅ Comprehensive error handling
✅ XML documentation on all public APIs
✅ No external dependencies (beyond .NET)

## Troubleshooting

**Operations timing out?**

- Increase CancellationToken timeout
- Check logging for details

**Thread-safety issues?**

- All operations are designed to be thread-safe
- Use ConfigureAwait(false) in libraries

**Need custom configuration?**

- Use EcosystemServiceOptions to customize
- Pass to AddEcosystemServices()

## Support

For issues, check:

1. Log output (enable debug logging)
2. Test cases for usage examples
3. XML documentation in Visual Studio IntelliSense
4. GitHub Issues (when available)

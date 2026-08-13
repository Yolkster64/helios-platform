using System.Runtime.CompilerServices;
using Azure.AI.Agents.Persistent;
using Azure.Identity;

namespace HELIOS.AIHub.Providers;

/// <summary>One persistent agent's identity as reported by the Foundry Agent Service.</summary>
public sealed record FoundryAgentSummary(
    string Id,
    string? Name,
    string? Model,
    DateTimeOffset Created,
    string? Description = null);

/// <summary>
/// Result of listing persistent agents. Unconfigured is a state, not an error
/// (same contract as <see cref="FoundryAgentProvider"/>): when
/// AZURE_FOUNDRY_PROJECT_ENDPOINT is unset, <see cref="Configured"/> is false and
/// <see cref="Hint"/> names the exact fix — the call never throws for absence.
/// </summary>
public sealed record FoundryAgentListResult(
    bool Configured,
    string? Hint,
    IReadOnlyList<FoundryAgentSummary> Agents);

/// <summary>
/// Minimal administration seam over the Foundry Agent Service, so the list/create
/// logic is testable without network or credentials. The only production
/// implementation is <see cref="FoundryAgentAdministration"/>; tests substitute a fake.
/// </summary>
public interface IFoundryAgentAdministration
{
    /// <summary>Streams existing agents, newest pages first per service default.</summary>
    IAsyncEnumerable<FoundryAgentSummary> ListAgentsAsync(int pageSize, CancellationToken cancellationToken);

    /// <summary>Creates exactly one agent. No retries — a retry could double-create.</summary>
    Task<FoundryAgentSummary> CreateAgentAsync(
        string model, string name, string instructions, string? description, CancellationToken cancellationToken);
}

/// <summary>
/// SDK-backed seam: PersistentAgentsClient.Administration over the project endpoint
/// with DefaultAzureCredential, exactly like <see cref="FoundryAgentProvider"/>.
/// </summary>
public sealed class FoundryAgentAdministration : IFoundryAgentAdministration
{
    private readonly PersistentAgentsAdministrationClient _administration;

    public FoundryAgentAdministration(string projectEndpoint)
    {
        _administration = new PersistentAgentsClient(projectEndpoint, new DefaultAzureCredential()).Administration;
    }

    public async IAsyncEnumerable<FoundryAgentSummary> ListAgentsAsync(
        int pageSize, [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        // AsyncPageable pages transparently; the caller bounds total enumeration.
        await foreach (PersistentAgent agent in _administration
            .GetAgentsAsync(limit: pageSize, cancellationToken: cancellationToken)
            .ConfigureAwait(false))
        {
            yield return ToSummary(agent);
        }
    }

    public async Task<FoundryAgentSummary> CreateAgentAsync(
        string model, string name, string instructions, string? description, CancellationToken cancellationToken)
    {
        PersistentAgent created = await _administration.CreateAgentAsync(
            model: model,
            name: name,
            description: description,
            instructions: instructions,
            cancellationToken: cancellationToken).ConfigureAwait(false);
        return ToSummary(created);
    }

    private static FoundryAgentSummary ToSummary(PersistentAgent agent) =>
        new(agent.Id, agent.Name, agent.Model, agent.CreatedAt, agent.Description);
}

/// <summary>
/// Read/create administration surface over the persistent agents on the configured
/// Foundry project — the service the MCP tools helios_foundry_agent_list and
/// helios_foundry_agent_create wrap. Distinct from <see cref="FoundryAgentProvider"/>
/// (which chats through short-lived agents it manages itself): this service inspects
/// and provisions long-lived agents on the project. Missing endpoint is the standard
/// Unconfigured state — construction never throws, listing reports the hint, and only
/// the explicit create mutation refuses to proceed.
/// </summary>
public sealed class FoundryAgentService
{
    public const string EndpointEnvironmentVariable = "AZURE_FOUNDRY_PROJECT_ENDPOINT";

    /// <summary>Same wording as <see cref="FoundryAgentProvider.ConfigurationHint"/>.</summary>
    public const string UnconfiguredHint =
        "Set AZURE_FOUNDRY_PROJECT_ENDPOINT to the Foundry project endpoint (infra output 'projectEndpoint').";

    /// <summary>Service-side page-size bounds for listing agents (limit is 1–100).</summary>
    public const int MaxListLimit = 100;
    public const int DefaultListLimit = 50;

    private readonly Lazy<IFoundryAgentAdministration>? _administration;

    public FoundryAgentService()
        : this(Environment.GetEnvironmentVariable(EndpointEnvironmentVariable))
    {
    }

    /// <summary>
    /// <paramref name="administrationFactory"/> is the test seam; null uses the real
    /// SDK client. Lazy so no credential work happens until a tool actually runs.
    /// </summary>
    public FoundryAgentService(string? projectEndpoint, Func<IFoundryAgentAdministration>? administrationFactory = null)
    {
        if (!string.IsNullOrWhiteSpace(projectEndpoint))
        {
            var endpoint = projectEndpoint;
            _administration = new Lazy<IFoundryAgentAdministration>(
                administrationFactory ?? (() => new FoundryAgentAdministration(endpoint)));
        }
    }

    public bool IsConfigured => _administration is not null;

    /// <summary>
    /// Lists up to <paramref name="limit"/> persistent agents. Unconfigured returns a
    /// hint-carrying result instead of throwing; invalid <paramref name="limit"/> throws
    /// before any network call.
    /// </summary>
    public async Task<FoundryAgentListResult> ListAgentsAsync(
        int limit = DefaultListLimit, CancellationToken cancellationToken = default)
    {
        if (limit is < 1 or > MaxListLimit)
        {
            throw new ArgumentOutOfRangeException(
                nameof(limit), limit, $"limit must be between 1 and {MaxListLimit}.");
        }

        if (_administration is null)
        {
            return new FoundryAgentListResult(false, UnconfiguredHint, Array.Empty<FoundryAgentSummary>());
        }

        var agents = new List<FoundryAgentSummary>();
        await foreach (var agent in _administration.Value
            .ListAgentsAsync(limit, cancellationToken).ConfigureAwait(false))
        {
            agents.Add(agent);
            if (agents.Count >= limit)
            {
                // limit is the caller's total budget, not just the page size — the
                // pageable would otherwise keep walking every page on the project.
                break;
            }
        }
        return new FoundryAgentListResult(true, null, agents);
    }

    /// <summary>
    /// Creates exactly one persistent agent. All parameters are validated and the
    /// configuration checked BEFORE any network call; the underlying seam performs a
    /// single create with no retries, so a failure can never double-create.
    /// </summary>
    /// <exception cref="ArgumentException">A required parameter is missing or blank.</exception>
    /// <exception cref="InvalidOperationException">AZURE_FOUNDRY_PROJECT_ENDPOINT is unset.</exception>
    public async Task<FoundryAgentSummary> CreateAgentAsync(
        string name, string model, string instructions, string? description = null,
        CancellationToken cancellationToken = default)
    {
        var validName = RequireValue(name, nameof(name), "the agent's display name");
        var validModel = RequireValue(model, nameof(model), "the model DEPLOYMENT name on the Foundry project (e.g. gpt-5-mini)");
        var validInstructions = RequireValue(instructions, nameof(instructions), "the agent's system instructions");
        var trimmedDescription = string.IsNullOrWhiteSpace(description) ? null : description.Trim();

        if (_administration is null)
        {
            throw new InvalidOperationException($"Azure AI Foundry is unconfigured — {UnconfiguredHint}");
        }

        return await _administration.Value
            .CreateAgentAsync(validModel, validName, validInstructions, trimmedDescription, cancellationToken)
            .ConfigureAwait(false);
    }

    private static string RequireValue(string? value, string parameterName, string meaning)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException($"'{parameterName}' is required: pass {meaning}.", parameterName);
        }
        return value.Trim();
    }
}

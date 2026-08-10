using System.Diagnostics;
using System.Text;
using Azure.AI.Agents.Persistent;
using Azure.Identity;
using HELIOS.AIHub.Abstractions;

namespace HELIOS.AIHub.Providers;

/// <summary>
/// Azure AI Foundry Agent Service over the project endpoint (the infra/main.bicep
/// `projectEndpoint` output). Creates one persistent agent lazily, then runs each request
/// on its own thread: create thread → post message → run → poll → read reply.
/// Tools, files, and connected resources are follow-up scope (see ROADMAP_MULTI_LLM.md).
/// </summary>
public sealed class FoundryAgentProvider : ProviderAgentBase
{
    private const string AgentName = "helios-aihub";

    private readonly string? _projectEndpoint;
    private readonly Lazy<PersistentAgentsClient>? _client;
    private readonly SemaphoreSlim _agentGate = new(1, 1);

    // Keyed by (model, instructions): a persistent agent bakes both in at creation,
    // so reusing one agent across requests would silently pin every caller to the
    // first request's model and system prompt. Bounded: dynamic per-request system
    // prompts would otherwise grow this cache (and the service-side agent list)
    // without limit — the oldest agent is evicted and best-effort deleted remotely.
    private const int MaxCachedAgents = 8;
    private readonly Dictionary<(string Model, string Instructions), PersistentAgent> _agents = new();
    private readonly Queue<(string Model, string Instructions)> _agentOrder = new();

    public FoundryAgentProvider(string provider, string displayName, string? defaultModel, string? projectEndpoint)
        : base(provider, displayName, defaultModel)
    {
        _projectEndpoint = projectEndpoint;
        if (!string.IsNullOrWhiteSpace(projectEndpoint))
        {
            _client = new Lazy<PersistentAgentsClient>(() =>
                new PersistentAgentsClient(projectEndpoint, new DefaultAzureCredential()));
        }
    }

    public override ProviderReadiness Readiness =>
        _client is null ? ProviderReadiness.Unconfigured : ProviderReadiness.Ready;

    public override string? ConfigurationHint =>
        _client is null
            ? "Set AZURE_FOUNDRY_PROJECT_ENDPOINT to the Foundry project endpoint (infra output 'projectEndpoint')."
            : null;

    protected override async Task<ChatResult> ChatCoreAsync(ChatRequest request, CancellationToken cancellationToken)
    {
        var client = _client!.Value;
        var model = request.Model ?? DefaultModel ?? "gpt-5-mini";
        var stopwatch = Stopwatch.StartNew();

        var agent = await GetOrCreateAgentAsync(client, model, request.System, cancellationToken).ConfigureAwait(false);

        PersistentAgentThread thread = await client.Threads
            .CreateThreadAsync(cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        await client.Messages
            .CreateMessageAsync(thread.Id, MessageRole.User, request.Prompt, cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        ThreadRun run = await client.Runs
            .CreateRunAsync(thread.Id, agent.Id, cancellationToken: cancellationToken)
            .ConfigureAwait(false);

        while (run.Status == RunStatus.Queued || run.Status == RunStatus.InProgress)
        {
            await Task.Delay(TimeSpan.FromMilliseconds(500), cancellationToken).ConfigureAwait(false);
            run = await client.Runs.GetRunAsync(thread.Id, run.Id, cancellationToken).ConfigureAwait(false);
        }

        if (run.Status != RunStatus.Completed)
        {
            return new ChatResult(false, null, Provider, model, stopwatch.Elapsed,
                Error: $"Foundry run ended as {run.Status}: {run.LastError?.Message ?? "no detail"}");
        }

        var text = new StringBuilder();
        await foreach (PersistentThreadMessage message in client.Messages
            .GetMessagesAsync(thread.Id, order: ListSortOrder.Ascending, cancellationToken: cancellationToken)
            .ConfigureAwait(false))
        {
            if (message.Role != MessageRole.Agent)
            {
                continue;
            }
            foreach (MessageContent content in message.ContentItems)
            {
                if (content is MessageTextContent textContent)
                {
                    text.Append(textContent.Text);
                }
            }
        }

        return new ChatResult(true, text.ToString(), Provider, model, stopwatch.Elapsed);
    }

    private async Task<PersistentAgent> GetOrCreateAgentAsync(
        PersistentAgentsClient client, string model, string? instructions, CancellationToken cancellationToken)
    {
        var effectiveInstructions = instructions ?? "You are the HELIOS platform's Azure AI Foundry agent.";
        var key = (model, effectiveInstructions);

        await _agentGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (!_agents.TryGetValue(key, out var agent))
            {
                agent = await client.Administration.CreateAgentAsync(
                    model: model,
                    name: AgentName,
                    instructions: effectiveInstructions,
                    cancellationToken: cancellationToken).ConfigureAwait(false);
                _agents[key] = agent;
                _agentOrder.Enqueue(key);

                while (_agents.Count > MaxCachedAgents)
                {
                    var oldest = _agentOrder.Dequeue();
                    if (_agents.Remove(oldest, out var evicted))
                    {
                        try
                        {
                            await client.Administration
                                .DeleteAgentAsync(evicted.Id, cancellationToken)
                                .ConfigureAwait(false);
                        }
                        catch (Azure.RequestFailedException)
                        {
                            // Best-effort: an orphaned service-side agent is preferable to
                            // failing the caller's request over cleanup.
                        }
                    }
                }
            }
            return agent;
        }
        finally
        {
            _agentGate.Release();
        }
    }
}

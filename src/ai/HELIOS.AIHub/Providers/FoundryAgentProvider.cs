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

    // Eviction must not delete an agent a concurrent request is still using: the
    // remote delete is deferred until the last in-flight request releases it.
    private readonly Dictionary<string, int> _agentsInFlight = new();
    private readonly List<PersistentAgent> _pendingDeletion = new();

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
        try
        {

            PersistentAgentThread thread = await client.Threads
                .CreateThreadAsync(cancellationToken: cancellationToken)
                .ConfigureAwait(false);

            try
            {
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

                return new ChatResult(true, text.ToString(), Provider, model, stopwatch.Elapsed,
                    InputTokens: run.Usage?.PromptTokens,
                    OutputTokens: run.Usage?.CompletionTokens);
            }
            finally
            {
                // Threads are per-request; leaving them behind accumulates service-side
                // state forever. CancellationToken.None: cleanup must run for a cancelled
                // caller too, and it's a single quick delete.
                try
                {
                    await client.Threads.DeleteThreadAsync(thread.Id, CancellationToken.None).ConfigureAwait(false);
                }
                catch (Azure.RequestFailedException)
                {
                    // Best-effort: an orphaned thread is preferable to masking the result.
                }
            }
        }
        finally
        {
            // Pairs with the in-flight count taken in GetOrCreateAgentAsync: the
            // last release performs any eviction-deferred remote delete.
            await ReleaseAgentAsync(client, agent).ConfigureAwait(false);
        }
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
                        if (_agentsInFlight.GetValueOrDefault(evicted.Id) > 0)
                        {
                            // A concurrent request is mid-run on this agent; the last
                            // release performs the remote delete.
                            _pendingDeletion.Add(evicted);
                        }
                        else
                        {
                            try
                            {
                                await client.Administration
                                    .DeleteAgentAsync(evicted.Id, cancellationToken)
                                    .ConfigureAwait(false);
                            }
                            catch (Azure.RequestFailedException)
                            {
                                // Best-effort: an orphaned service-side agent is preferable
                                // to failing the caller's request over cleanup.
                            }
                        }
                    }
                }
            }

            _agentsInFlight[agent.Id] = _agentsInFlight.GetValueOrDefault(agent.Id) + 1;
            return agent;
        }
        finally
        {
            _agentGate.Release();
        }
    }

    private async Task ReleaseAgentAsync(PersistentAgentsClient client, PersistentAgent agent)
    {
        PersistentAgent? deleteNow = null;
        await _agentGate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
        try
        {
            var remaining = _agentsInFlight.GetValueOrDefault(agent.Id) - 1;
            if (remaining <= 0)
            {
                _agentsInFlight.Remove(agent.Id);
                var pendingIndex = _pendingDeletion.FindIndex(p => p.Id == agent.Id);
                if (pendingIndex >= 0)
                {
                    deleteNow = _pendingDeletion[pendingIndex];
                    _pendingDeletion.RemoveAt(pendingIndex);
                }
            }
            else
            {
                _agentsInFlight[agent.Id] = remaining;
            }
        }
        finally
        {
            _agentGate.Release();
        }

        if (deleteNow is not null)
        {
            try
            {
                await client.Administration
                    .DeleteAgentAsync(deleteNow.Id, CancellationToken.None)
                    .ConfigureAwait(false);
            }
            catch (Azure.RequestFailedException)
            {
            }
        }
    }
}

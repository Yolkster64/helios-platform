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
    private PersistentAgent? _agent;

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
        var model = request.Model ?? DefaultModel ?? "gpt-4o-mini";
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
        if (_agent is not null)
        {
            return _agent;
        }

        await _agentGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            _agent ??= await client.Administration.CreateAgentAsync(
                model: model,
                name: AgentName,
                instructions: instructions ?? "You are the HELIOS platform's Azure AI Foundry agent.",
                cancellationToken: cancellationToken).ConfigureAwait(false);
            return _agent;
        }
        finally
        {
            _agentGate.Release();
        }
    }
}

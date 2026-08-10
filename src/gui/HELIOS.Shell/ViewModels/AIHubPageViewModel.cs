using System.Collections.ObjectModel;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using HELIOS.Shell.Services;
using Microsoft.UI.Dispatching;

namespace HELIOS.Shell.ViewModels;

/// <summary>
/// View model for the AI Hub provider dashboard. Pulls provider status from
/// helios-ai-api (<c>GET /v1/status</c>) and degrades to an explicit "API not running"
/// state when the endpoint is unreachable — an unreachable API is a state to display,
/// not an exception to surface (csharp-orchestrator: never throw for expected absence).
/// </summary>
public partial class AIHubPageViewModel : ObservableObject
{
    private readonly AIHubApiClient _api;

    // Captured at construction ON THE UI THREAD (winui3-shell skill:
    // GetForCurrentThread() returns null on worker threads — never fetch it in a
    // callback). The refresh path leaves the UI thread via ConfigureAwait(false), so
    // every bound-property/collection update below marshals through this queue.
    private readonly DispatcherQueue _dispatcherQueue;

    [ObservableProperty]
    private bool _isLoading;

    [ObservableProperty]
    private bool _isApiUnavailable;

    [ObservableProperty]
    private string _statusMessage = "Not refreshed yet.";

    public AIHubPageViewModel(AIHubApiClient api)
    {
        _api = api;
        _dispatcherQueue = DispatcherQueue.GetForCurrentThread()
            ?? throw new InvalidOperationException(
                $"{nameof(AIHubPageViewModel)} must be constructed on the UI thread so it can capture the DispatcherQueue.");
    }

    /// <summary>Provider rows; mutated only on the UI thread via the dispatcher queue.</summary>
    public ObservableCollection<ProviderItemViewModel> Providers { get; } = [];

    /// <summary>Resolved API base URL (HELIOS_API_URL or the localhost default), for display.</summary>
    public string ApiBaseUrl => _api.BaseAddress.ToString();

    [RelayCommand]
    private async Task RefreshAsync(CancellationToken cancellationToken)
    {
        IsLoading = true; // still on the UI thread here
        try
        {
            var status = await _api.GetStatusAsync(cancellationToken).ConfigureAwait(false);

            // Off the UI thread now — every property/collection touch goes through the queue.
            _dispatcherQueue.TryEnqueue(() =>
            {
                Providers.Clear();
                foreach (var provider in status)
                {
                    Providers.Add(ProviderItemViewModel.From(provider));
                }
                IsApiUnavailable = false;
                StatusMessage = $"{Providers.Count} providers · refreshed {DateTimeOffset.Now:HH:mm:ss}";
                IsLoading = false;
            });
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // User-initiated cancellation: just stop spinning, keep whatever is shown.
            _dispatcherQueue.TryEnqueue(() => IsLoading = false);
        }
        catch (HttpRequestException ex) when (ex.StatusCode == HttpStatusCode.Unauthorized)
        {
            _dispatcherQueue.TryEnqueue(() =>
            {
                IsApiUnavailable = true;
                StatusMessage =
                    $"helios-ai-api rejected access at {ApiBaseUrl}. Set " +
                    $"{AIHubApiClient.AccessKeyEnvVar} to the server's access key for " +
                    "Docker or remote URLs.";
                IsLoading = false;
            });
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            // HttpRequestException: connection refused / DNS — the API is not running.
            // TaskCanceledException (token NOT cancelled): the client's 5 s timeout.
            // JsonException: something answered, but it is not helios-ai-api.
            _dispatcherQueue.TryEnqueue(() =>
            {
                IsApiUnavailable = true;
                StatusMessage =
                    $"helios-ai-api is not reachable at {ApiBaseUrl}. " +
                    "Start it with: dotnet run --project src/ai/HELIOS.AIHub.Api " +
                    $"(override the URL with the {AIHubApiClient.BaseUrlEnvVar} environment variable).";
                IsLoading = false;
            });
        }
    }
}

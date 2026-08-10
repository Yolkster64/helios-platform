using Azure;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;

namespace HELIOS.AIHub.Configuration;

/// <summary>Resolves provider secrets without ever failing startup.</summary>
public interface ISecretResolver
{
    /// <summary>
    /// Resolution order: environment variable, then Key Vault (when AZURE_KEY_VAULT_URI is
    /// set), then null. Null means the provider surfaces as Unconfigured — never an exception.
    /// </summary>
    string? Resolve(string? envName, string? secretName);
}

public sealed class SecretResolver : ISecretResolver
{
    private readonly Lazy<SecretClient?> _keyVault;
    private readonly Dictionary<string, string?> _cache = new();
    private readonly object _gate = new();

    public SecretResolver(string? keyVaultUri = null)
    {
        var uri = keyVaultUri ?? Environment.GetEnvironmentVariable("AZURE_KEY_VAULT_URI");
        _keyVault = new Lazy<SecretClient?>(() =>
            string.IsNullOrWhiteSpace(uri)
                ? null
                : new SecretClient(new Uri(uri), new DefaultAzureCredential()));
    }

    public string? Resolve(string? envName, string? secretName)
    {
        if (!string.IsNullOrWhiteSpace(envName))
        {
            var fromEnv = Environment.GetEnvironmentVariable(envName);
            if (!string.IsNullOrWhiteSpace(fromEnv))
            {
                return fromEnv;
            }
        }

        if (string.IsNullOrWhiteSpace(secretName))
        {
            return null;
        }

        lock (_gate)
        {
            if (_cache.TryGetValue(secretName, out var cached))
            {
                return cached;
            }
        }

        string? value;
        try
        {
            value = _keyVault.Value?.GetSecret(secretName).Value.Value;
        }
        catch (RequestFailedException)
        {
            value = null;
        }
        catch (AuthenticationFailedException)
        {
            value = null;
        }

        lock (_gate)
        {
            _cache[secretName] = value;
        }
        return value;
    }
}

using HELIOS.AIHub;
using HELIOS.AIHub.Api;

var builder = WebApplication.CreateBuilder(args);

// One hub for the process: provider registry, circuit breakers, and the neural/linear
// routing learners all carry state that must be shared across requests.
// Config resolution matches the CLI: --aihub-config, then AIHUB_CONFIG, then walk up.
builder.Services.AddSingleton(_ => AIHubService.CreateFromConfig(
    builder.Configuration["aihub-config"] ?? Environment.GetEnvironmentVariable("AIHUB_CONFIG")));
builder.Services.AddSingleton<HELIOS.AIHub.Learning.PythonInsightsSpoke>();

var app = builder.Build();

app.MapAIHubApi();

app.Run();

public partial class Program;

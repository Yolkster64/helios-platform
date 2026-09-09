using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.IdentityModel.Tokens;
using ModelContextProtocol.AspNetCore;
using System.Threading.RateLimiting;

namespace HELIOS.RemoteMcp;

public static class Program
{
    public static Task Main(string[] args) => BuildApplication(args).RunAsync();

    // The callback is a host-composition seam for in-process tests, never exposed over HTTP.
    public static WebApplication BuildApplication(string[] args, Action<WebApplicationBuilder>? configure = null)
    {
        var builder = WebApplication.CreateBuilder(args);
        configure?.Invoke(builder);
        var options = RemoteMcpOptions.Load(builder.Configuration);
        builder.WebHost.ConfigureKestrel(server =>
        {
            server.Listen(options.ListenAddress, options.ListenUri.Port);
            server.Limits.MaxRequestBodySize = 64 * 1024;
            server.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(15);
        });
        // Headers, prompts, tokens and process output never go to application logs.
        builder.Logging.ClearProviders();
        builder.Logging.AddConsole();
        builder.Logging.AddFilter("Microsoft.AspNetCore", LogLevel.Warning);
        builder.Logging.AddFilter("Microsoft.IdentityModel", LogLevel.None);
        builder.Logging.AddFilter("ModelContextProtocol", LogLevel.None);
        builder.Services.AddSingleton(options);
        builder.Services.AddSingleton<RemoteRepository>();
        builder.Services.AddSingleton<ClaudeTextBridge>();
        builder.Services.AddHttpContextAccessor();
        builder.Services.AddRateLimiter(rate => rate.AddConcurrencyLimiter("mcp", limiter =>
        {
            limiter.PermitLimit = 8;
            limiter.QueueLimit = 0;
            limiter.QueueProcessingOrder = QueueProcessingOrder.OldestFirst;
        }));
        if (options.UsesEntra)
        {
            builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(jwt =>
            {
                jwt.Authority = options.Authority;
                jwt.Audience = options.Audience;
                jwt.RequireHttpsMetadata = true;
                jwt.MapInboundClaims = false;
                jwt.IncludeErrorDetails = false;
                jwt.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true, ValidIssuer = options.Authority,
                    ValidateAudience = true, ValidAudience = options.Audience,
                    ValidateLifetime = true, RequireExpirationTime = true,
                    RequireSignedTokens = true, ValidateIssuerSigningKey = true,
                    ClockSkew = TimeSpan.FromSeconds(30),
                    ValidAlgorithms = [SecurityAlgorithms.RsaSha256],
                };
                jwt.Events = new JwtBearerEvents
                {
                    OnChallenge = context =>
                    {
                        context.HandleResponse();
                        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                        context.Response.Headers.WWWAuthenticate =
                            $"Bearer resource_metadata=\"{options.MetadataUrl}\", scope=\"{options.OAuthScope(options.ReadScope)}\"";
                        return Task.CompletedTask;
                    },
                };
            });
            builder.Services.AddAuthorization(auth => auth.AddPolicy("remote-read", policy =>
                policy.RequireAuthenticatedUser().RequireAssertion(context => options.HasScope(context.User, options.ReadScope))));
        }
        var mcp = builder.Services.AddMcpServer().WithHttpTransport(transport =>
        {
            // Use the API shipped in the repository's pinned 2.1.0 package.
            // SessionMode is documented on the newer SDK documentation branch.
            transport.Stateless = true;
        }).WithTools<RemoteReadTools>().WithTools<RemoteHandoffTools>().WithTools<RemoteAgentCatalogTools>();
        if (options.ClaudeEnabled) mcp.WithTools<RemoteClaudeTools>();

        var app = builder.Build();
        app.Use(async (context, next) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            if (!options.AllowsRequest(context))
            {
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                return;
            }
            if (context.Request.ContentLength > 64 * 1024)
            {
                context.Response.StatusCode = StatusCodes.Status413PayloadTooLarge;
                return;
            }
            await next(context);
        });
        app.UseRateLimiter();
        if (options.UsesEntra)
        {
            app.UseAuthentication();
            app.UseAuthorization();
            object Metadata() => new
            {
                resource = options.Resource,
                resource_name = "HELIOS shared project",
                authorization_servers = new[] { options.Authority },
                scopes_supported = (options.ClaudeEnabled ? new[] { options.ReadScope, "handoff.write", options.ClaudeScope }
                    : new[] { options.ReadScope, "handoff.write" }).Select(options.OAuthScope).ToArray(),
                bearer_methods_supported = new[] { "header" },
            };
            app.MapGet("/.well-known/oauth-protected-resource", Metadata);
            app.MapGet("/.well-known/oauth-protected-resource/mcp", Metadata);
        }
        app.MapGet("/health", () => new { service = "helios-remote-mcp", status = "listening", productionEnabled = false });
        var endpoint = app.MapMcp("/mcp").RequireRateLimiting("mcp");
        if (options.UsesEntra) endpoint.RequireAuthorization("remote-read");
        return app;
    }
}

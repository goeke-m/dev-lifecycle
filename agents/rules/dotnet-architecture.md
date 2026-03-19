# .NET Architecture Conventions

## Prefer Minimal APIs over Controller-Based APIs

Minimal APIs are the preferred approach for new ASP.NET Core services. They reduce ceremony,
are more performant, and compose naturally with the rest of the .NET ecosystem.

### Use Minimal APIs by default

```csharp
// Good — minimal API endpoint
app.MapGet("/users/{id:guid}", async (Guid id, IUserService userService, CancellationToken ct) =>
{
    var user = await userService.GetByIdAsync(id, ct);
    return user is null ? Results.NotFound() : Results.Ok(user);
})
.WithName("GetUser")
.WithTags("Users")
.Produces<UserResponse>()
.ProducesProblem(StatusCodes.Status404NotFound);

// Avoid — controller-based API adds indirection without benefit
[ApiController]
[Route("users")]
public class UsersController : ControllerBase
{
    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetUser(Guid id) { ... }
}
```

### Organise endpoints with extension methods and route groups

Do not put all endpoints in `Program.cs`. Group related endpoints into extension methods:

```csharp
// Users/UserEndpoints.cs
public static class UserEndpoints
{
    public static IEndpointRouteBuilder MapUserEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/users")
            .WithTags("Users")
            .RequireAuthorization();

        group.MapGet("/",    GetAllUsers);
        group.MapGet("/{id:guid}", GetUser);
        group.MapPost("/",   CreateUser);
        group.MapPut("/{id:guid}",    UpdateUser);
        group.MapDelete("/{id:guid}", DeleteUser);

        return app;
    }

    private static async Task<IResult> GetUser(
        Guid id,
        IUserService userService,
        CancellationToken ct)
    {
        var user = await userService.GetByIdAsync(id, ct);
        return user is null ? Results.NotFound() : Results.Ok(user);
    }

    // ... other handlers
}

// Program.cs
app.MapUserEndpoints();
app.MapOrderEndpoints();
```

### Use typed results for discoverability and OpenAPI accuracy

```csharp
// Good — typed results enable accurate OpenAPI generation
private static async Task<Results<Ok<UserResponse>, NotFound, ValidationProblem>> CreateUser(
    CreateUserRequest request,
    IUserService userService,
    CancellationToken ct)
{
    if (!MiniValidator.TryValidate(request, out var errors))
        return TypedResults.ValidationProblem(errors);

    var user = await userService.CreateAsync(request, ct);
    return TypedResults.Ok(user);
}

// Avoid — IResult loses type information
private static async Task<IResult> CreateUser(...) { ... }
```

### When controller-based APIs are acceptable

- Integrating with an existing controller-based codebase where migration cost outweighs benefit
- Third-party libraries that require `ControllerBase` (e.g., some API versioning libraries)
- Complex OData scenarios

In all new greenfield services, default to Minimal APIs.

---

## Prefer .NET Aspire for Cloud-Native Applications

Use .NET Aspire when building multi-service or distributed applications. Aspire provides
orchestration, service discovery, health checks, and OpenTelemetry out of the box.

### Use Aspire for multi-service applications

```
MyApp.AppHost/          ← Aspire orchestration project
MyApp.ServiceDefaults/  ← Shared telemetry, health, resilience config
MyApp.Api/              ← Minimal API service
MyApp.Worker/           ← Background worker service
MyApp.Web/              ← Frontend (Blazor or other)
```

### AppHost wires services together

```csharp
// AppHost/Program.cs
var builder = DistributedApplication.CreateBuilder(args);

var postgres = builder.AddPostgres("postgres")
    .WithDataVolume()
    .WithPgAdmin();

var db = postgres.AddDatabase("myapp-db");

var cache = builder.AddRedis("cache");

var api = builder.AddProject<Projects.MyApp_Api>("api")
    .WithReference(db)
    .WithReference(cache)
    .WithHttpHealthCheck("/health");

builder.AddProject<Projects.MyApp_Web>("web")
    .WithReference(api)
    .WithExternalHttpEndpoints();

builder.Build().Run();
```

### Apply ServiceDefaults to every service

```csharp
// Every service calls this — do not skip it
builder.AddServiceDefaults();

// ServiceDefaults/Extensions.cs (generated, customise as needed)
// Adds: OpenTelemetry, health checks, service discovery, resilience
```

### Use Aspire's service discovery instead of hardcoded URLs

```csharp
// Good — service name resolves at runtime via Aspire
builder.Services.AddHttpClient<IOrderApiClient, OrderApiClient>(
    client => client.BaseAddress = new Uri("https+http://order-api"));

// Bad — hardcoded URL breaks across environments
builder.Services.AddHttpClient<IOrderApiClient, OrderApiClient>(
    client => client.BaseAddress = new Uri("https://localhost:7001"));
```

### Use Aspire resource integrations over manual configuration

Prefer Aspire's first-party integrations for infrastructure resources:

| Resource | Aspire integration |
|---|---|
| PostgreSQL | `builder.AddPostgres(...)` |
| SQL Server | `builder.AddSqlServer(...)` |
| Redis | `builder.AddRedis(...)` |
| Azure Service Bus | `builder.AddAzureServiceBus(...)` |
| Azure Blob Storage | `builder.AddAzureBlobStorage(...)` |
| RabbitMQ | `builder.AddRabbitMQ(...)` |

Aspire integrations handle connection strings, health checks, and telemetry automatically.

### When Aspire is not required

- Single-service applications with no external dependencies beyond a database
- Azure Functions or other serverless workloads
- Libraries (not applications)

For single-service apps, still use `ServiceDefaults` if OpenTelemetry and health checks are desired.

---

## Prefer `Results<T1, T2>` Problem Details over custom error shapes

Use RFC 9457 Problem Details consistently for error responses. Aspire and Minimal APIs support
this natively:

```csharp
// Program.cs
builder.Services.AddProblemDetails();

// Endpoint
return TypedResults.Problem(
    title: "Order not found",
    detail: $"No order with id '{orderId}' exists.",
    statusCode: StatusCodes.Status404NotFound);
```

Do not invent custom `{ success, error, data }` response envelopes. Use Problem Details for
errors and plain response types for success.

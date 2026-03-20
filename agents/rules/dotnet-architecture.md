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

## Database Migrations Run Automatically and Must Be Reversible

Migrations are bundled as part of the deployment artefact and applied automatically in every
environment — including production — without manual intervention. Every migration must have a
working `Down` method and must be safe to roll back without data loss.

### Bundle migrations with the application

Use EF Core migration bundles to produce a self-contained executable that is run as a
deployment step, not `dotnet ef database update` run manually on a developer machine.

```bash
# Generate the bundle (run in CI, not locally)
dotnet ef migrations bundle \
  --project src/MyApp.Infrastructure \
  --startup-project src/MyApp.Api \
  --output artifacts/migrationbundle \
  --self-contained \
  --runtime linux-x64
```

The bundle is a versioned artefact stored alongside the application image. The same bundle
that was tested in staging is what runs in production.

### Run migrations automatically on deployment

With .NET Aspire, add a dedicated migration runner that runs before dependent services start:

```csharp
// AppHost/Program.cs
var migrations = builder.AddProject<Projects.MyApp_Migrations>("migrations")
    .WithReference(db)
    .WithHttpHealthCheck("/health");

// API waits for migrations to complete before starting
var api = builder.AddProject<Projects.MyApp_Api>("api")
    .WithReference(db)
    .WaitForCompletion(migrations);
```

```csharp
// MyApp.Migrations/Program.cs — standalone migration runner service
var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();
builder.Services.AddDbContext<AppDbContext>(...);

var app = builder.Build();
app.MapHealthChecks("/health");

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();
}

await app.RunAsync();
```

Without Aspire, apply migrations at startup with a guard:

```csharp
// Startup migration — acceptable for simple single-instance deployments
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();
}
```

### Every migration must have a working Down method

The `Down` method must restore the schema to its exact prior state. A migration with an empty
or `throw new NotImplementedException()` `Down` method must not be merged.

```csharp
// Good — both directions are implemented and tested
public partial class AddOrderShippedAtColumn : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<DateTimeOffset>(
            name:      "ShippedAt",
            table:     "Orders",
            nullable:  true);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name:  "ShippedAt",
            table: "Orders");
    }
}

// Bad — rollback is impossible
protected override void Down(MigrationBuilder migrationBuilder)
    => throw new NotImplementedException();
```

### Use the expand/contract pattern for zero-downtime schema changes

Never make a breaking schema change in a single migration if the application is deployed
without downtime. Use the expand/contract pattern across multiple deployments:

**Phase 1 — Expand (additive, backward-compatible):**
Add the new column/table as nullable or with a default. Both old and new application code work.

```csharp
migrationBuilder.AddColumn<string>(
    name:         "PhoneNumber",
    table:        "Customers",
    nullable:     true,       // old code ignores it; new code writes it
    defaultValue: null);
```

**Phase 2 — Migrate data** (if needed, in a background job, not the migration itself):
```csharp
// Background job — not inside a migration
await _context.Customers
    .Where(c => c.PhoneNumber == null && c.LegacyPhone != null)
    .ExecuteUpdateAsync(s => s.SetProperty(c => c.PhoneNumber, c => c.LegacyPhone));
```

**Phase 3 — Contract (remove old column after all instances run new code):**
```csharp
migrationBuilder.DropColumn(name: "LegacyPhone", table: "Customers");
```

### Never drop columns or tables in the same migration that removes code referencing them

Dropping a column while the running application still references it causes immediate failures.
Always deploy the code removal first, verify, then drop the column in a subsequent release.

### Avoid data mutations inside migrations

Migrations change schema. Data backfills should be separate, idempotent background jobs.
Mixing data changes into migrations makes rollback dangerous and slows deployments.

```csharp
// Bad — data change inside a migration
migrationBuilder.Sql(
    "UPDATE Orders SET Status = 'Pending' WHERE Status IS NULL");

// Good — schema only in the migration; data fixed by a separate idempotent job
```

### Test rollback in CI

The migration pipeline in CI must apply the migration and then immediately roll it back,
verifying the `Down` method works against the same database state:

```yaml
# .github/workflows/test-migrations.yml (example CI step)
- name: Apply migration
  run: ./artifacts/migrationbundle --connection "${{ secrets.DB_CONNECTION }}"

- name: Roll back migration
  run: dotnet ef database update PreviousMigrationName \
         --project src/MyApp.Infrastructure \
         --startup-project src/MyApp.Api
```

---

## Prefer Smart Enums over plain C# enums

Plain `enum` types lack behaviour, are stringly-typed at the boundary, and cannot be extended
without breaking switch exhaustiveness. Use the Smart Enum pattern — an enumeration class that
encapsulates value, display name, and domain behaviour — instead.

Prefer the [Ardalis.SmartEnum](https://github.com/ardalis/SmartEnum) NuGet package rather than
rolling the base class from scratch.

### Define smart enums with Ardalis.SmartEnum

```csharp
// Good — behaviour lives with the value
public sealed class OrderStatus : SmartEnum<OrderStatus>
{
    public static readonly OrderStatus Pending    = new(nameof(Pending),    1);
    public static readonly OrderStatus Processing = new(nameof(Processing), 2);
    public static readonly OrderStatus Shipped    = new(nameof(Shipped),    3);
    public static readonly OrderStatus Delivered  = new(nameof(Delivered),  4);
    public static readonly OrderStatus Cancelled  = new(nameof(Cancelled),  5);

    private OrderStatus(string name, int value) : base(name, value) { }

    public virtual bool CanTransitionTo(OrderStatus next) =>
        (this == Pending    && next == Processing) ||
        (this == Processing && next == Shipped)    ||
        (this == Shipped    && next == Delivered)  ||
        (this             != Cancelled && next == Cancelled);
}

// Bad — behaviour must live elsewhere; invalid values possible at runtime
public enum OrderStatus { Pending = 1, Processing = 2, Shipped = 3, Delivered = 4, Cancelled = 5 }
```

### Add domain behaviour directly to the smart enum

```csharp
public sealed class PaymentMethod : SmartEnum<PaymentMethod>
{
    public static readonly PaymentMethod Card        = new(nameof(Card),        1, surchargeRate: 0m);
    public static readonly PaymentMethod BankTransfer = new(nameof(BankTransfer), 2, surchargeRate: 0m);
    public static readonly PaymentMethod CryptoCurrency = new(nameof(CryptoCurrency), 3, surchargeRate: 0.02m);

    public decimal SurchargeRate { get; }

    private PaymentMethod(string name, int value, decimal surchargeRate)
        : base(name, value)
    {
        SurchargeRate = surchargeRate;
    }

    public decimal CalculateSurcharge(decimal amount) => amount * SurchargeRate;
}

// Usage — no switch, no external mapping table
var surcharge = order.PaymentMethod.CalculateSurcharge(order.Total);
```

### Use SmartFlagEnum for flags

```csharp
public sealed class Permission : SmartFlagEnum<Permission>
{
    public static readonly Permission None    = new(nameof(None),    0);
    public static readonly Permission Read    = new(nameof(Read),    1);
    public static readonly Permission Write   = new(nameof(Write),   2);
    public static readonly Permission Delete  = new(nameof(Delete),  4);
    public static readonly Permission Admin   = new(nameof(Admin),   8);
    public static readonly Permission Full    = new(nameof(Full),    Read | Write | Delete | Admin);

    private Permission(string name, int value) : base(name, value) { }
}

// Usage
var userPermissions = Permission.Read | Permission.Write;
bool canDelete = userPermissions.HasFlag(Permission.Delete); // false
```

### Parse from external values safely

```csharp
// From a database value or API payload — never cast an int directly
if (!OrderStatus.TryFromValue(rawValue, out var status))
    throw new InvalidOperationException($"Unknown order status value: {rawValue}");

// From a name (e.g., JSON string)
var status = OrderStatus.FromName("Shipped");
```

### Serialise smart enums as their value or name

Configure JSON serialisation once at the composition root:

```csharp
// Store/transport as integer value
builder.Services.AddControllers()
    .AddJsonOptions(o =>
        o.JsonSerializerOptions.Converters.Add(new SmartEnumValueConverter<OrderStatus, int>()));

// Or as string name (more readable in APIs)
builder.Services.AddControllers()
    .AddJsonOptions(o =>
        o.JsonSerializerOptions.Converters.Add(new SmartEnumNameConverter<OrderStatus, int>()));
```

For EF Core, map to the underlying primitive:

```csharp
// Fluent API
builder.Property(o => o.Status)
    .HasConversion(s => s.Value, v => OrderStatus.FromValue(v));
```

### When plain enums are acceptable

- Simple flags with no behaviour and no external serialisation (e.g., internal switch in a single method)
- Interop with external libraries that require a plain `enum`
- Performance-critical hot paths where allocation from a class instance matters

In all other cases — especially domain model types that cross a persistence or API boundary —
prefer smart enums.

---

## Prefer the Query Specification Pattern for data access

Encapsulate query logic in specification objects rather than proliferating repository methods
or leaking query concerns into services.

### Define a base specification

```csharp
// Shared infrastructure — define once
public abstract class Specification<T>
{
    public Expression<Func<T, bool>>? Criteria { get; protected init; }
    public List<Expression<Func<T, object>>> Includes { get; } = [];
    public Expression<Func<T, object>>? OrderBy { get; protected init; }
    public Expression<Func<T, object>>? OrderByDescending { get; protected init; }
    public int? Take { get; protected init; }
    public int? Skip { get; protected init; }
}
```

### Write concrete specifications per query intent

```csharp
// Good — query logic lives in the specification, named for its intent
public sealed class ActiveOrdersByCustomerSpec : Specification<Order>
{
    public ActiveOrdersByCustomerSpec(Guid customerId, int pageSize, int page)
    {
        Criteria         = o => o.CustomerId == customerId && o.Status != OrderStatus.Cancelled;
        OrderByDescending = o => o.CreatedAt;
        Includes.Add(o => o.LineItems);
        Take = pageSize;
        Skip = pageSize * (page - 1);
    }
}

// Bad — a new repository method for every query variation
public interface IOrderRepository
{
    Task<List<Order>> GetActiveOrdersByCustomerAsync(Guid customerId, ...);
    Task<List<Order>> GetActiveOrdersByCustomerSortedByDateAsync(Guid customerId, ...);
    Task<List<Order>> GetActiveOrdersByCustomerWithItemsAsync(Guid customerId, ...);
    // grows without bound
}
```

### Keep the repository interface generic

```csharp
public interface IRepository<T> where T : class
{
    Task<T?>             GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<T?>             FirstOrDefaultAsync(Specification<T> spec, CancellationToken ct = default);
    Task<List<T>>        ListAsync(Specification<T> spec, CancellationToken ct = default);
    Task<int>            CountAsync(Specification<T> spec, CancellationToken ct = default);
    Task<bool>           AnyAsync(Specification<T> spec, CancellationToken ct = default);
    Task                 AddAsync(T entity, CancellationToken ct = default);
    Task                 UpdateAsync(T entity, CancellationToken ct = default);
    Task                 DeleteAsync(T entity, CancellationToken ct = default);
}
```

### Apply the specification in the repository implementation

```csharp
// EF Core implementation — evaluate spec once, not per call-site
public async Task<List<T>> ListAsync(Specification<T> spec, CancellationToken ct)
{
    var query = ApplySpecification(spec);
    return await query.ToListAsync(ct);
}

private IQueryable<T> ApplySpecification(Specification<T> spec)
{
    var query = _context.Set<T>().AsQueryable();

    if (spec.Criteria is not null)
        query = query.Where(spec.Criteria);

    query = spec.Includes.Aggregate(query,
        (current, include) => current.Include(include));

    if (spec.OrderBy is not null)
        query = query.OrderBy(spec.OrderBy);
    else if (spec.OrderByDescending is not null)
        query = query.OrderByDescending(spec.OrderByDescending);

    if (spec.Skip.HasValue)
        query = query.Skip(spec.Skip.Value);

    if (spec.Take.HasValue)
        query = query.Take(spec.Take.Value);

    return query;
}
```

### Use specifications in services, not raw queries

```csharp
// Good — service composes specs; no EF Core leaks
public async Task<PagedResult<OrderResponse>> GetCustomerOrdersAsync(
    Guid customerId, int page, int pageSize, CancellationToken ct)
{
    var spec  = new ActiveOrdersByCustomerSpec(customerId, pageSize, page);
    var count = new ActiveOrderCountByCustomerSpec(customerId);

    var orders = await _repository.ListAsync(spec, ct);
    var total  = await _repository.CountAsync(count, ct);

    return new PagedResult<OrderResponse>(
        orders.Select(OrderResponse.From),
        total,
        page,
        pageSize);
}

// Bad — EF Core / IQueryable leaks out of the data layer
public async Task<List<Order>> GetCustomerOrdersAsync(Guid customerId)
    => await _context.Orders
        .Where(o => o.CustomerId == customerId)
        .ToListAsync();
```

### Compose specifications for reuse

```csharp
public sealed class CompositeSpecification<T> : Specification<T>
{
    public CompositeSpecification(
        Specification<T> left,
        Specification<T> right,
        CompositeMode mode = CompositeMode.And)
    {
        Criteria = mode == CompositeMode.And
            ? left.Criteria!.And(right.Criteria!)
            : left.Criteria!.Or(right.Criteria!);
    }
}

// Reuse existing specs rather than duplicating criteria
var spec = new CompositeSpecification<Order>(
    new ActiveOrdersSpec(),
    new HighValueOrdersSpec(minimumValue: 1000m));
```

### Consider Ardalis.Specification for production use

Rather than implementing the pattern from scratch, prefer the
[Ardalis.Specification](https://github.com/ardalis/Specification) NuGet package which
provides a battle-tested base implementation with EF Core and Dapper evaluators.

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

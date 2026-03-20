# Performance Testing

Performance testing is a first-class part of the development lifecycle, not a pre-release
activity. Baselines are established early, regressions are caught in CI, and no optimisation
is made without a measurement proving it is needed.

---

## When to Write Performance Tests

Write a performance test when:

- A new endpoint, service, or background job is introduced that will handle meaningful load
- A change touches a hot path (tight loop, high-frequency query, serialisation, cache layer)
- A performance regression has been reported or observed — add a test to prevent recurrence
- An optimisation is being made — measure before and after; do not ship without proof

Do not optimise speculatively. Profile first, identify the bottleneck, then fix and measure.

---

## Types of Performance Tests

| Type | Question it answers | When to run |
|---|---|---|
| **Benchmark** | How fast is this code path in isolation? | On every PR touching the hot path |
| **Load test** | Does the system meet latency/throughput targets under expected load? | On every merge to main |
| **Stress test** | Where does the system break, and how does it recover? | Per release candidate |
| **Soak test** | Does performance degrade over time (memory leaks, connection pool exhaustion)? | Weekly scheduled run |

---

## What to Measure

Always report percentile latency — not averages. Averages hide tail behaviour.

| Metric | Target (set per project) |
|---|---|
| p50 latency | Typical user experience |
| p95 latency | SLA boundary — most users |
| p99 latency | Worst-case for real users |
| Throughput (req/s) | Capacity planning |
| Error rate | Must be 0% under normal load |
| Memory / GC pressure | Relevant for long-running services |

Define concrete targets in `.devlifecycle.json` or a `perf-budget.json` per service.
A test without a pass/fail threshold is an observation, not a test.

---

## C# — Benchmarking with BenchmarkDotNet

Use [BenchmarkDotNet](https://benchmarkdotnet.org) for micro-benchmarks of hot code paths.

### Structure benchmark projects separately

```
src/
  MyApp.Api/
  MyApp.Infrastructure/
tests/
  MyApp.Tests/
  MyApp.Benchmarks/        ← separate project, Release only
```

### Write focused benchmarks

```csharp
[MemoryDiagnoser]
[SimpleJob(RuntimeMoniker.Net90)]
public class OrderSerializationBenchmarks
{
    private Order _order = null!;
    private string _json = null!;

    [GlobalSetup]
    public void Setup()
    {
        _order = OrderFactory.CreateSample();
        _json  = JsonSerializer.Serialize(_order);
    }

    [Benchmark(Baseline = true)]
    public string Serialize_SystemTextJson()
        => JsonSerializer.Serialize(_order);

    [Benchmark]
    public Order? Deserialize_SystemTextJson()
        => JsonSerializer.Deserialize<Order>(_json);
}
```

```bash
# Always run benchmarks in Release mode
dotnet run --project tests/MyApp.Benchmarks -c Release -- --filter '*OrderSerialization*'
```

### Detect regressions with BenchmarkDotNet exporters

Export results as JSON and compare against a stored baseline in CI:

```csharp
[SimpleJob]
[JsonExporter]                 // writes BenchmarkDotNet.Artifacts/results/*.json
[MarkdownExporterAttribute.GitHub]
public class MyBenchmarks { ... }
```

---

## C# — Load Testing with NBomber

Use [NBomber](https://nbomber.com) for HTTP load tests written in C#, keeping the test
toolchain consistent with the rest of the codebase.

```csharp
// tests/MyApp.LoadTests/OrderEndpointLoadTests.cs
public class OrderEndpointLoadTest
{
    [Fact]
    public void CreateOrder_MeetsLatencyTargetUnderLoad()
    {
        var httpClient = new HttpClient { BaseAddress = new Uri("https://localhost:7001") };

        var scenario = Scenario.Create("create_order", async context =>
        {
            var request = new CreateOrderRequest(
                CustomerId: Guid.NewGuid(),
                LineItems: [new(ProductId: Guid.NewGuid(), Quantity: 1, UnitPrice: 9.99m)]);

            var response = await httpClient.PostAsJsonAsync("/orders", request);

            return response.IsSuccessStatusCode ? Response.Ok() : Response.Fail();
        })
        .WithLoadSimulations(
            Simulation.Inject(rate: 100, interval: TimeSpan.FromSeconds(1), during: TimeSpan.FromSeconds(30))
        );

        var stats = NBomberRunner
            .RegisterScenarios(scenario)
            .Run();

        // Assert against performance budget
        var scenarioStats = stats.ScenarioStats[0];
        Assert.True(scenarioStats.Ok.Latency.Percent95 < 200,  // p95 < 200ms
            $"p95 latency was {scenarioStats.Ok.Latency.Percent95}ms, expected < 200ms");
        Assert.True(scenarioStats.Ok.Latency.Percent99 < 500,  // p99 < 500ms
            $"p99 latency was {scenarioStats.Ok.Latency.Percent99}ms, expected < 500ms");
        Assert.Equal(0, scenarioStats.Fail.Request.Count);
    }
}
```

---

## TypeScript — Load Testing with k6

Use [k6](https://k6.io) for HTTP load tests in TypeScript/JavaScript services.

```typescript
// tests/load/create-order.ts
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const p95Latency = new Trend('p95_latency');
const errorRate  = new Rate('error_rate');

export const options = {
  stages: [
    { duration: '30s', target: 50  }, // ramp up
    { duration: '1m',  target: 100 }, // sustained load
    { duration: '15s', target: 0   }, // ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<200', 'p(99)<500'], // p95 < 200ms, p99 < 500ms
    http_req_failed:   ['rate<0.01'],               // < 1% errors
  },
};

export default function () {
  const payload = JSON.stringify({
    customerId: '00000000-0000-0000-0000-000000000001',
    lineItems: [{ productId: '00000000-0000-0000-0000-000000000002', quantity: 1, unitPrice: 9.99 }],
  });

  const res = http.post(`${__ENV.BASE_URL}/orders`, payload, {
    headers: { 'Content-Type': 'application/json' },
  });

  const ok = check(res, {
    'status is 200': r => r.status === 200,
    'p95 < 200ms':   r => r.timings.duration < 200,
  });

  errorRate.add(!ok);
  sleep(1);
}
```

```bash
k6 run --env BASE_URL=https://staging.myapp.com tests/load/create-order.ts
```

---

## CI Integration

### Run benchmarks on PRs that touch hot paths

```yaml
# .github/workflows/benchmarks.yml
name: Benchmarks
on:
  pull_request:
    paths:
      - 'src/MyApp.Infrastructure/**'
      - 'src/MyApp.Api/**'

jobs:
  benchmark:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '9.0.x'
      - name: Run benchmarks
        run: dotnet run --project tests/MyApp.Benchmarks -c Release -- --exporters json
      - name: Compare against baseline
        uses: benchmark-action/github-action-benchmark@v1
        with:
          tool: benchmarkdotnet
          output-file-path: BenchmarkDotNet.Artifacts/results/*.json
          alert-threshold: '120%'       # fail if > 20% slower than baseline
          fail-on-alert: true
          github-token: ${{ secrets.GITHUB_TOKEN }}
          auto-push: true
```

### Run load tests against staging on merge to main

```yaml
# .github/workflows/load-test.yml
name: Load Tests
on:
  push:
    branches: [main]

jobs:
  load-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run k6 load test
        uses: grafana/k6-action@v0.3.1
        with:
          filename: tests/load/create-order.ts
        env:
          BASE_URL: ${{ secrets.STAGING_URL }}
      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: k6-results
          path: results/
```

---

## Profiling Before Optimising

Never optimise based on intuition. Profile first to confirm the bottleneck.

**C#**
```bash
# dotnet-trace for CPU profiling
dotnet-trace collect --process-id <pid> --profile cpu-sampling

# dotnet-counters for live metrics
dotnet-counters monitor --process-id <pid> System.Runtime

# dotnet-dump for memory analysis
dotnet-dump collect --process-id <pid>
dotnet-dump analyze ./core_<pid>_<timestamp>.dmp
```

Use Visual Studio's built-in profiler or JetBrains dotMemory / dotTrace for local profiling sessions.

**TypeScript / Node**
```bash
# Built-in Node.js profiler
node --prof server.js
node --prof-process isolate-*.log > processed.txt

# Clinic.js for flame graphs and heap analysis
npx clinic flame -- node server.js
npx clinic heapprofiler -- node server.js
```

### Document profiling findings before the fix

When fixing a performance issue, include in the PR description:

1. **Before** — profiler output or benchmark result showing the problem
2. **Root cause** — what the bottleneck was (e.g., N+1 query, unnecessary allocation, missing index)
3. **After** — profiler output or benchmark result showing the improvement
4. **Trade-offs** — any complexity or maintainability cost of the fix

---

## Performance Budget

Define performance targets per service in `.devlifecycle.json`:

```json
"performance": {
  "budgets": {
    "api": {
      "p95LatencyMs": 200,
      "p99LatencyMs": 500,
      "maxErrorRatePct": 1,
      "minThroughputRps": 100
    }
  }
}
```

Budgets are enforced by load test thresholds. A build that misses a budget fails.

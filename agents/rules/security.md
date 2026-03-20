# Security

Security is a first-class concern, not an afterthought. Every feature and change must be
assessed for security impact before merging. The guidance below applies to both C# and
TypeScript projects.

---

## Identify What Needs Protecting

Before writing any code, identify and classify the assets at stake. Not everything needs
the same level of protection — misclassifying leads to either under-protection of sensitive
data or wasteful over-engineering of low-risk data.

**Asset classification:**

| Classification | Examples | Controls required |
|---|---|---|
| **Critical** | Credentials, private keys, payment data, PHI | Encryption at rest and in transit, strict access control, audit log |
| **Sensitive** | PII, business logic, internal config | Access control, log redaction, masked in non-prod |
| **Internal** | Application logs, metrics, non-personal config | Access restricted to operations team |
| **Public** | Marketing content, public API responses | Integrity only |

Document the classification for any new data type or storage system in an ADR.

---

## Identify Roles and Responsibilities

Security ownership must be explicit. For every system or service, the following roles must
be named — not left to assumption:

| Role | Responsibility |
|---|---|
| **Data owner** | Decides classification, approves access changes, accountable for breaches |
| **Service owner** | Ensures the service meets security standards, reviews security-touching PRs |
| **Operations** | Manages secrets rotation, monitors alerts, responds to incidents |
| **Developer** | Implements controls, follows these guidelines, flags risks in PRs |

Document role assignments in the project README or a `SECURITY.md` file in the repository.
When a role is vacant, escalate — do not leave it unowned.

---

## Threat Assessment Before You Code

Before implementing any feature that involves user input, authentication, authorisation,
data storage, or external integrations, ask:

1. **Who are the actors?** Authenticated users, anonymous users, internal services, admins.
2. **What can go wrong?** Walk the OWASP Top 10 relevant to the surface area.
3. **What is the blast radius?** If this is exploited, what data or systems are at risk?
4. **What controls already exist?** Don't duplicate — verify they actually cover this case.
5. **What residual risk remains?** Document it if it cannot be mitigated now.

Record significant decisions in an ADR. Do not rely on memory or verbal agreement.

---

## Input Validation

### Validate at every trust boundary

Validate all input from: HTTP requests, message queues, files, environment variables,
and any other external source. Do not assume upstream systems have validated.

**C#**
```csharp
// Use FluentValidation or DataAnnotations — validate before the handler runs
public sealed class CreateOrderRequestValidator : AbstractValidator<CreateOrderRequest>
{
    public CreateOrderRequestValidator()
    {
        RuleFor(r => r.CustomerId).NotEmpty();
        RuleFor(r => r.LineItems).NotEmpty().ForEach(item =>
        {
            item.ChildRules(li =>
            {
                li.RuleFor(i => i.ProductId).NotEmpty();
                li.RuleFor(i => i.Quantity).InclusiveBetween(1, 1000);
                li.RuleFor(i => i.UnitPrice).GreaterThan(0);
            });
        });
    }
}
```

**TypeScript**
```typescript
// Use Zod for runtime validation — parse, don't validate
const CreateOrderSchema = z.object({
  customerId: z.string().uuid(),
  lineItems: z.array(z.object({
    productId: z.string().uuid(),
    quantity:  z.number().int().min(1).max(1000),
    unitPrice: z.number().positive(),
  })).nonempty(),
});

// .parse() throws on invalid input; .safeParse() returns a result type
const order = CreateOrderSchema.parse(req.body);
```

### Reject unknown fields

Do not silently accept and ignore unknown input fields — they can be used for mass assignment attacks.

```csharp
// In ASP.NET Core, disallow extra properties in model binding
builder.Services.Configure<JsonOptions>(o =>
    o.JsonSerializerOptions.UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow);
```

---

## Injection Prevention

### Never concatenate user input into queries

```csharp
// Bad — SQL injection
var sql = $"SELECT * FROM Users WHERE Email = '{email}'";

// Good — parameterised query
var user = await _context.Users
    .Where(u => u.Email == email)
    .FirstOrDefaultAsync(ct);

// Good — raw SQL with parameters when necessary
var user = await _context.Users
    .FromSqlRaw("SELECT * FROM Users WHERE Email = {0}", email)
    .FirstOrDefaultAsync(ct);
```

```typescript
// Bad
const result = await db.query(`SELECT * FROM users WHERE email = '${email}'`);

// Good — parameterised
const result = await db.query('SELECT * FROM users WHERE email = $1', [email]);
```

### Sanitise and escape output to prevent XSS

In TypeScript/browser contexts, never set `innerHTML` from user-controlled data.
Use framework-provided escaping (React, Angular, Blazor all escape by default — do not
bypass with `dangerouslySetInnerHTML`, `[innerHTML]`, or `@Html.Raw` unless the content
is explicitly sanitised).

```typescript
// Bad
element.innerHTML = userInput;

// Good — React escapes by default
return <div>{userInput}</div>;

// If you must render HTML, sanitise first
import DOMPurify from 'dompurify';
element.innerHTML = DOMPurify.sanitize(userInput);
```

---

## Authentication and Authorisation

### Never implement your own security framework

Do not write custom authentication, authorisation, cryptography, or token handling from
scratch. These are well-understood, heavily audited problems with established solutions.
Rolling your own introduces vulnerabilities that are difficult to detect and costly to fix.

Use established identity providers and libraries:

- **ASP.NET Core**: ASP.NET Core Identity + OpenIddict, or Duende IdentityServer, or a
  managed provider (Azure AD, Auth0, Okta).
- **TypeScript**: Passport.js, Auth.js, or a managed provider SDK.

```csharp
// Require authorisation globally — opt out explicitly, not opt in
builder.Services.AddAuthorizationBuilder()
    .SetFallbackPolicy(new AuthorizationPolicyBuilder()
        .RequireAuthenticatedUser()
        .Build());

// Explicitly mark public endpoints
app.MapGet("/health", () => Results.Ok())
   .AllowAnonymous();
```

### Use policy-based authorisation — not role checks in business logic

```csharp
// Bad — role check in the service layer
if (!user.IsInRole("Admin"))
    throw new ForbiddenException();

// Good — express intent as a policy; enforce at the boundary
app.MapDelete("/users/{id:guid}", DeleteUser)
   .RequireAuthorization("CanDeleteUsers");

// Policy definition
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("CanDeleteUsers", p => p.RequireRole("Admin").RequireClaim("department", "IT"));
```

### Validate tokens server-side; never trust client-provided claims

```csharp
// Always validate: issuer, audience, expiry, signature
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.Authority = builder.Configuration["Auth:Authority"];
        o.Audience  = builder.Configuration["Auth:Audience"];
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer           = true,
            ValidateAudience         = true,
            ValidateLifetime         = true,
            ValidateIssuerSigningKey = true,
            ClockSkew                = TimeSpan.FromSeconds(30),
        };
    });
```

---

## Secrets Management

### Never commit secrets to source control

The following must never appear in committed code or config files:

- API keys, tokens, passwords, connection strings with credentials
- Private keys or certificates
- Environment-specific secrets of any kind

```csharp
// Bad — hardcoded secret
var client = new StorageClient("DefaultEndpointsProtocol=https;AccountName=prod;AccountKey=abc123...");

// Good — read from environment / secrets provider
var connectionString = builder.Configuration.GetConnectionString("BlobStorage")
    ?? throw new InvalidOperationException("BlobStorage connection string is required.");
```

Use:
- **Local dev**: `dotnet user-secrets` or `.env` files (git-ignored)
- **CI/CD**: GitHub Actions secrets / environment variables
- **Production**: Azure Key Vault, AWS Secrets Manager, HashiCorp Vault

### Rotate database passwords and credentials regularly

Credentials that never change become a permanent liability if they are leaked. Rotate all
database passwords, API keys, and service account credentials on a defined schedule:

- **Database passwords**: rotate every 90 days minimum; immediately on suspected compromise
- **API keys**: rotate every 180 days or on staff changes
- **Service account credentials**: rotate on team membership changes

Use your secrets provider's rotation features where available:

```bash
# Azure Key Vault — set an expiry and rotation policy
az keyvault secret set-attributes \
  --vault-name my-vault \
  --name db-password \
  --expires "$(date -u -d '+90 days' '+%Y-%m-%dT%H:%M:%SZ')"
```

Automate rotation where possible. Never require a deployment to rotate a credential —
applications must read secrets at runtime, not bake them into build artefacts.

### Add a `.gitignore` entry and pre-commit check for common secret file patterns

Ensure `.gitignore` excludes: `.env`, `*.pfx`, `*.p12`, `appsettings.*.json` (non-base),
`secrets.json`, `local.settings.json`.

---

## Dependency Vulnerability Scanning

### Run dependency scans regularly and in CI

**C# — NuGet**
```bash
dotnet list package --vulnerable --include-transitive
```

Enable Dependabot in `.github/dependabot.yml`:
```yaml
version: 2
updates:
  - package-ecosystem: nuget
    directory: "/"
    schedule:
      interval: weekly
    open-pull-requests-limit: 10
```

**TypeScript — npm/pnpm**
```bash
npm audit
pnpm audit
```

```yaml
# .github/dependabot.yml
  - package-ecosystem: npm
    directory: "/"
    schedule:
      interval: weekly
```

### Treat high/critical CVEs as blocking

A PR that introduces or fails to remediate a high or critical CVE must not merge.
Medium severity should be tracked and resolved within the current sprint.

---

## Log and Monitoring Security

Logs and monitoring tools are high-value targets — they often contain the information an
attacker needs to escalate privileges or understand a system. Treat them with the same
rigour as the database.

### Secure access to logs as strictly as the database

- Logs must not be publicly accessible or stored in unauthenticated storage buckets
- Apply the same role-based access controls to log infrastructure as to production databases
- Audit access to logs — who reads them and when should be recorded
- Retain logs for the period required by compliance policy, then delete them — do not keep
  logs indefinitely in unsecured cold storage

### Monitoring tools must not expose sensitive information

- Dashboards, alerting tools, and APM platforms (Grafana, Datadog, Azure Monitor, etc.)
  must be access-controlled — do not share unauthenticated dashboard links
- Ensure traces and spans do not capture request bodies that contain credentials or PII
- Redact or mask sensitive fields before they reach the monitoring pipeline:

```csharp
// Configure OpenTelemetry to redact sensitive headers
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation(o =>
        {
            o.Filter = ctx => !ctx.Request.Path.StartsWithSegments("/health");
            o.EnrichWithHttpRequest = (activity, request) =>
            {
                // Do not record Authorization header values
                activity.SetTag("http.request.header.authorization", "[redacted]");
            };
        }));
```

---

## Sensitive Data Handling

### Never log sensitive values

```csharp
// Bad
_logger.LogInformation("User {Email} authenticated with password {Password}", email, password);

// Good — log identity, never credentials or PII beyond what's needed
_logger.LogInformation("User {UserId} authenticated successfully", userId);
```

Sensitive fields include: passwords, tokens, card numbers, national IDs, full dates of birth,
private keys, and any PII regulated by GDPR/HIPAA or equivalent.

### Encrypt sensitive data at rest

Do not store plaintext passwords — always use a proper password hashing algorithm:

```csharp
// Use ASP.NET Core Identity's IPasswordHasher or BCrypt.Net-Next
var hashed = _passwordHasher.HashPassword(user, plainTextPassword);
var result = _passwordHasher.VerifyHashedPassword(user, user.PasswordHash, plainTextPassword);
```

Mark sensitive properties so they are excluded from logs and serialisation:

```csharp
public sealed record UserRecord(
    Guid Id,
    string Email,
    [property: JsonIgnore] string PasswordHash,  // never serialise
    [property: SensitiveData] string? PhoneNumber // custom attribute for log redaction
);
```

---

## Test and Non-Production Environment Hygiene

### Never restore production data to lower environments without scrubbing

Production data contains real PII, credentials, and business-sensitive information.
Restoring it to development, staging, or test environments — even temporarily — is a
data breach risk and a compliance violation.

Before any production data can be used in a lower environment:

1. **Scrub PII** — replace names, emails, phone numbers, addresses with synthetic values
2. **Nullify credentials** — clear password hashes, tokens, API keys; replace with known test values
3. **Mask financial data** — truncate or randomise card numbers, account numbers, balances
4. **Verify the scrub** — run a validation query to confirm no real values remain before import

Use a dedicated data masking tool or script, and treat the scrubbing script as a production
artefact — version-controlled, reviewed, and tested.

```sql
-- Example scrubbing script (PostgreSQL) — adapt per schema
UPDATE customers SET
  email      = 'user_' || id || '@example.com',
  name       = 'Test User ' || row_number() OVER (),
  phone      = NULL,
  created_at = created_at; -- preserve structure, not identity

UPDATE users SET
  password_hash = '$2a$12$testhashtesthashhhhhhhhhhhhhhhhhhhhhhhhhhhhh', -- known bcrypt
  refresh_token = NULL;
```

When possible, use generated synthetic data instead of scrubbed production data entirely.

---

## Security Headers and Transport

### Enforce HTTPS and add security headers in production

```csharp
// Redirect HTTP → HTTPS
app.UseHttpsRedirection();

// HSTS — tell browsers to only use HTTPS for this origin
app.UseHsts();

// Add security headers via a middleware or NWebSec / Helmet equivalent
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"]    = "nosniff";
    context.Response.Headers["X-Frame-Options"]           = "DENY";
    context.Response.Headers["Referrer-Policy"]           = "strict-origin-when-cross-origin";
    context.Response.Headers["Permissions-Policy"]        = "geolocation=(), microphone=()";
    await next();
});
```

**TypeScript (Node/Express)**
```typescript
import helmet from 'helmet';
app.use(helmet()); // sets X-Content-Type-Options, X-Frame-Options, CSP, and more
```

### Set a restrictive Content Security Policy

Avoid `unsafe-inline` and `unsafe-eval` in CSP. Start restrictive and loosen only when necessary.

---

## Security Review Checklist

Include the following in every PR that touches authentication, authorisation, data storage,
external integrations, or file/network I/O:

**Code**
- [ ] All user-supplied input is validated at the boundary before use
- [ ] No raw string concatenation into queries (SQL, LDAP, shell commands)
- [ ] No secrets, credentials, or PII committed to source control
- [ ] No custom authentication or cryptography — established libraries used throughout
- [ ] Authentication and authorisation enforced — not bypassed for convenience
- [ ] New endpoints have explicit authorisation policies (no accidental public exposure)
- [ ] HTTPS enforced; security headers present

**Data and Logging**
- [ ] Sensitive values are not logged or included in error responses returned to clients
- [ ] Monitoring/tracing does not capture credentials, tokens, or PII in spans or metrics
- [ ] Any test data derived from production has been fully scrubbed before use
- [ ] New sensitive data types are classified and documented

**Dependencies and Infrastructure**
- [ ] New dependencies have been checked for known CVEs (`dotnet list package --vulnerable` / `npm audit`)
- [ ] Error responses do not leak internal stack traces or system details
- [ ] Log access controls reviewed if new log destinations or pipelines are introduced
- [ ] Credential rotation policy confirmed for any new secrets introduced

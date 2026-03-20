# Security

Security is a first-class concern, not an afterthought. Every feature and change must be
assessed for security impact before merging. The guidance below applies to both C# and
TypeScript projects.

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

### Never implement authentication yourself

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

- [ ] All user-supplied input is validated at the boundary before use
- [ ] No raw string concatenation into queries (SQL, LDAP, shell commands)
- [ ] No secrets, credentials, or PII committed to source control
- [ ] Authentication and authorisation enforced — not bypassed for convenience
- [ ] Sensitive values are not logged or included in error responses returned to clients
- [ ] New dependencies have been checked for known CVEs (`dotnet list package --vulnerable` / `npm audit`)
- [ ] Error responses do not leak internal stack traces or system details
- [ ] New endpoints have explicit authorisation policies (no accidental public exposure)
- [ ] HTTPS enforced; security headers present

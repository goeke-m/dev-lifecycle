# {{PROJECT_NAME}}

<!-- Badges — replace URLs with your actual CI, coverage, and package links -->
[![Build](https://github.com/{{GITHUB_ORG}}/{{REPO_NAME}}/actions/workflows/build.yml/badge.svg)](https://github.com/{{GITHUB_ORG}}/{{REPO_NAME}}/actions/workflows/build.yml)
[![Tests](https://github.com/{{GITHUB_ORG}}/{{REPO_NAME}}/actions/workflows/test.yml/badge.svg)](https://github.com/{{GITHUB_ORG}}/{{REPO_NAME}}/actions/workflows/test.yml)
[![Coverage](https://codecov.io/gh/{{GITHUB_ORG}}/{{REPO_NAME}}/branch/main/graph/badge.svg)](https://codecov.io/gh/{{GITHUB_ORG}}/{{REPO_NAME}})
[![Version](https://img.shields.io/github/v/release/{{GITHUB_ORG}}/{{REPO_NAME}})](https://github.com/{{GITHUB_ORG}}/{{REPO_NAME}}/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

{{DESCRIPTION}}

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Development](#development)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [License](#license)

## Prerequisites

<!-- List everything a new developer needs to have installed before they can run the project. Be specific about versions. -->

- [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0) (for C# projects) or [Node.js 22+](https://nodejs.org/) (for TypeScript projects)
- [Git](https://git-scm.com/) 2.40+
- <!-- Add any other prerequisites: Docker, a database, cloud CLI tools, etc. -->

## Installation

### Clone the repository

```bash
git clone https://github.com/{{GITHUB_ORG}}/{{REPO_NAME}}.git
cd {{REPO_NAME}}
```

### Set up the project

**C# (.NET):**

```bash
dotnet restore
```

**TypeScript (Node.js):**

```bash
npm install
```

### Configuration

Copy the example environment file and fill in your values:

```bash
cp .env.example .env
```

| Variable | Description | Default |
|----------|-------------|---------|
| `EXAMPLE_VAR` | Description of what this variable does | `default-value` |

## Usage

<!-- Describe the primary way to use / run this project. -->

**C# — run the application:**

```bash
dotnet run --project src/{{PROJECT_NAME}}/{{PROJECT_NAME}}.csproj
```

**TypeScript — run the application:**

```bash
npm run build
npm start
```

### API Reference

<!-- If this is a library or service, document the public API here or link to generated docs. -->

<!-- Example:
```csharp
var client = new MyClient(options);
var result = await client.DoSomethingAsync(request);
```
-->

## Development

### Running tests

**C#:**

```bash
# Run all tests
dotnet test

# Run with coverage
dotnet test --settings coverlet.runsettings --collect:"XPlat Code Coverage"
```

**TypeScript:**

```bash
# Run all tests
npm test

# Run in watch mode
npm run test:watch

# Run with coverage
npm run test:coverage
```

### Linting and formatting

**C#:**

```bash
# Check formatting
dotnet format --verify-no-changes

# Fix formatting
dotnet format
```

**TypeScript:**

```bash
# Check linting
npm run lint

# Fix linting
npm run lint:fix

# Check formatting
npm run format:check

# Fix formatting
npm run format
```

### Building

**C#:**

```bash
dotnet build --configuration Release
```

**TypeScript:**

```bash
npm run build
```

### Project structure

```
{{REPO_NAME}}/
├── src/                    # Source code
│   └── {{PROJECT_NAME}}/   # Main project
├── tests/                  # Test projects / files
├── docs/                   # Documentation
│   ├── adr/                # Architecture Decision Records
│   └── templates/          # Doc templates (managed by ai-dev-lifecycle)
├── .github/                # GitHub Actions workflows and templates
└── README.md
```

## Architecture

<!-- Provide a high-level overview of the system architecture. Link to ADRs for key decisions. -->

Key architecture decisions are documented as [Architecture Decision Records](docs/adr/).

<!-- Example:
- [ADR-001: Use PostgreSQL as the primary database](docs/adr/ADR-001-postgresql.md)
- [ADR-002: Adopt the mediator pattern for command handling](docs/adr/ADR-002-mediator.md)
-->

## Contributing

Contributions are welcome. Please read through the following guidelines before submitting a pull request.

### Git workflow

1. Create a branch from `main` following the naming convention: `feat/short-description`, `fix/issue-number-description`, `chore/description`
2. Make your changes, following the [coding standards](docs/coding-standards.md) (or `.editorconfig` and `eslint.config.js`)
3. Ensure all tests pass and coverage thresholds are met
4. Commit using [Conventional Commits](https://www.conventionalcommits.org/): `feat: add user auth`, `fix: handle null response`
5. Open a pull request using the [PR template](.github/PULL_REQUEST_TEMPLATE.md)

### Commit message format

```
<type>[optional scope]: <description>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`, `build`, `perf`, `revert`

### Code review

All pull requests require at least one approval before merging. See [pr-standards](agents/rules/pr-standards.md) for expectations.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

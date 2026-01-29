---
name: preferences-web-application-deployment
description: Web application deployment patterns for production hosting and CI/CD. Load when deploying web applications or configuring deployment pipelines.
---

# Web application deployment

## Deployment philosophy

Deploy web applications to Cloudflare Workers/Pages unless specific requirements dictate otherwise.

### Why Cloudflare

**Technical advantages**:
- Global edge network with automatic geo-distribution (300+ locations)
- Zero cold starts with V8 isolate-based workers (sub-millisecond startup)
- Integrated platform with consistent billing and unified developer experience
- Type-safe bindings via wrangler for platform resources
- Native support for modern web standards (Web APIs, streaming, WebSockets)

**Economic advantages**:
- Generous free tier (100,000 requests/day, 10ms CPU time per request)
- Predictable pricing with no hidden costs
- No infrastructure management overhead
- Automatic scaling without capacity planning

**Developer experience**:
- Local development with `wrangler dev` mirrors production environment
- Instant deployments via git integration or CLI
- Built-in observability (metrics, logs, traces)
- TypeScript-first with automatic type generation

### When to consider alternatives

Use alternative platforms when:
- Workload requires >30 seconds of CPU time per request (use Cloudflare Workflows or traditional servers)
- Application depends on native binaries not available in Workers runtime
- Regulatory requirements mandate specific geographic data residency beyond Cloudflare's controls
- Existing infrastructure investment makes migration cost-prohibitive

## Database configuration

Prefer Cloudflare D1 for SQLite-compatible workloads, PostgreSQL for complex relational requirements.

### Cloudflare D1 (preferred)

Cloudflare D1 provides serverless SQLite at the edge with zero configuration scaling.

**When to use D1**:
- Application data fits SQLite's capabilities (relational data, transactions, full-text search)
- Read-heavy workloads benefit from edge caching
- Cost optimization is critical (D1 has generous free tier)
- Simplified operations without connection pooling concerns

**Limitations**:
- SQLite limitations apply (no concurrent writes from multiple isolates)
- 10GB database size limit per database
- Single-region primary with read replicas at edge

#### Environment variables for D1

```bash
# packages/data-ops/.env or apps/user-application/.env
CLOUDFLARE_DATABASE_ID="<database-id-from-dashboard>"
CLOUDFLARE_ACCOUNT_ID="<account-id-from-dashboard>"
CLOUDFLARE_D1_TOKEN="<api-token-with-d1-permissions>"
```

**Create D1 database**:

```bash
# Create production database
wrangler d1 create my-app-db

# Create staging database
wrangler d1 create my-app-db-stage

# List databases
wrangler d1 list
```

#### Drizzle configuration for D1

```typescript
// packages/data-ops/drizzle.config.ts
import type { Config } from "drizzle-kit";

const config: Config = {
  out: "./src/drizzle",
  schema: ["./src/drizzle/auth-schema.ts"],
  dialect: "sqlite",
  driver: "d1-http",
  dbCredentials: {
    accountId: process.env.CLOUDFLARE_ACCOUNT_ID!,
    databaseId: process.env.CLOUDFLARE_DATABASE_ID!,
    token: process.env.CLOUDFLARE_D1_TOKEN!,
  },
  tablesFilter: ["!_cf_KV", "!auth_*"],
};

export default config satisfies Config;
```

#### Wrangler D1 binding

```jsonc
// wrangler.jsonc
{
  "d1_databases": [
    {
      "binding": "DB", // Access via env.DB in worker code
      "database_id": "your-database-id",
      "database_name": "my-app-db",
      "experimental_remote": true // Enable remote D1 access during local dev
    }
  ]
}
```

#### Runtime database access

```typescript
// src/server.ts or server functions
import { env } from "cloudflare:workers";
import { drizzle } from "drizzle-orm/d1";

export default {
  fetch(request: Request) {
    // D1 binding available via env.DB
    const db = drizzle(env.DB);

    // Use Drizzle for type-safe queries
    const users = await db.select().from(usersTable);

    return new Response(JSON.stringify(users));
  }
}
```

#### D1 migrations

```bash
# Generate migration from schema changes
pnpm run generate-drizzle-sql-output

# Apply migrations to D1 (local dev)
wrangler d1 execute my-app-db --local --file=./packages/data-ops/src/drizzle/0001_migration.sql

# Apply migrations to D1 (production)
wrangler d1 execute my-app-db --file=./packages/data-ops/src/drizzle/0001_migration.sql

# Or use Drizzle Kit's migration runner
pnpm run drizzle:migrate
```

### PostgreSQL (secondary option)

Use PostgreSQL for workloads requiring advanced features not available in SQLite.

**When to use PostgreSQL**:
- Advanced data types needed (JSON path queries, arrays, hstore)
- Complex analytical queries benefit from query planner
- Team expertise in PostgreSQL
- Existing PostgreSQL database migration

**Recommended providers**:
- **Supabase** with Supavisor transaction mode (pooled connections)
- **Neon** with built-in connection pooling (serverless-optimized)

#### Environment variables for PostgreSQL

```bash
# packages/data-ops/.env
DATABASE_HOST="hostname.com/database-name"
DATABASE_USERNAME="username"
DATABASE_PASSWORD="password"
```

**Connection string format**:

```
postgresql://{username}:{password}@{hostname}/{database-name}
```

#### Drizzle configuration for PostgreSQL

```typescript
// packages/data-ops/drizzle.config.ts
import type { Config } from "drizzle-kit";

const config: Config = {
  out: "./src/drizzle",
  schema: ["./src/drizzle/auth-schema.ts"],
  dialect: "postgresql",
  dbCredentials: {
    url: `postgresql://${process.env.DATABASE_USERNAME}:${process.env.DATABASE_PASSWORD}@${process.env.DATABASE_HOST}`,
  },
  tablesFilter: ["!_cf_KV", "!auth_*"],
};

export default config satisfies Config;
```

#### Runtime database access with connection pooling

```typescript
// src/server.ts
import { initDatabase } from "@repo/data-ops/database/setup";
import { env } from "cloudflare:workers";

export default {
  fetch(request: Request) {
    // Initialize pooled connection
    const db = initDatabase({
      host: env.DATABASE_HOST,
      username: env.DATABASE_USERNAME,
      password: env.DATABASE_PASSWORD,
    });

    // Database queries here
  }
}
```

**Important**: Use transaction mode or connection pooling for serverless environments.
Workers create many short-lived connections - traditional connection pooling fails without Supavisor/Neon pooling.

### Schema management with Drizzle

All database schemas managed via Drizzle ORM for type-safe database access.

**Workflow**:

1. **Define schemas** in TypeScript using Drizzle schema builders
2. **Generate migrations** from schema changes with `drizzle-kit generate`
3. **Apply migrations** to database with `drizzle-kit migrate` or wrangler
4. **Pull schema** from database to verify with `drizzle-kit pull`

```bash
# From workspace root
pnpm run generate-drizzle-sql-output  # Generate migration SQL
pnpm run drizzle:migrate              # Apply to database
pnpm run pull-drizzle-schema          # Verify schema sync
```

See @~/.claude/commands/preferences/schema-versioning.md for migration patterns and versioning strategies.

## Wrangler configuration

Wrangler configures Cloudflare Workers deployment, local development, and platform bindings.

### Essential wrangler.jsonc structure

```jsonc
{
  // JSON schema for IDE autocomplete
  "$schema": "node_modules/wrangler/config-schema.json",

  // Worker name (deployment identifier)
  "name": "my-app",

  // Entry point - custom server or framework default
  "main": "src/server.ts",

  // API compatibility date (use recent date for latest features)
  "compatibility_date": "2025-04-10",

  // Enable Node.js compatibility layer for npm packages
  "compatibility_flags": ["nodejs_compat"],

  // Enable workers.dev subdomain for testing (disable in production)
  "workers_dev": true,

  // Static assets configuration (for SPAs, SSR apps)
  "assets": {
    "directory": ".output/public",
    "binding": "ASSETS",
    "not_found_handling": "single-page-application",
    // Routes where worker runs before checking static assets
    "run_worker_first": ["/api/*", "/trpc/*", "/auth/*"]
  },

  // Build command (runs before deployment)
  "build": {
    "command": "pnpm run build"
  },

  // Enable observability (metrics, logs, traces)
  "observability": {
    "enabled": true
  }
}
```

### Environment variables vs secrets

**Use `vars` for non-sensitive configuration**:

```jsonc
{
  "vars": {
    "API_URL": "https://api.example.com",
    "FEATURE_FLAG_NEW_UI": "true",
    "LOG_LEVEL": "info"
  }
}
```

**Use secrets for sensitive data**:

```bash
# Set secret (not stored in wrangler.jsonc)
wrangler secret put DATABASE_PASSWORD
wrangler secret put GOOGLE_CLIENT_SECRET
wrangler secret put BETTER_AUTH_SECRET

# List secrets
wrangler secret list

# Delete secret
wrangler secret delete OLD_SECRET
```

**Access in worker code**:

```typescript
import { env } from "cloudflare:workers";

// Both vars and secrets available via env
const apiUrl = env.API_URL;           // from vars
const dbPassword = env.DATABASE_PASSWORD; // from secret
```

### Type generation for environment

Generate TypeScript types for Cloudflare environment bindings:

```bash
# Generate types from wrangler.jsonc
pnpm run cf-typegen

# Or directly
wrangler types --env-interface Env
```

**Usage**:

```typescript
import { env } from "cloudflare:workers";

// env is fully typed based on wrangler.jsonc configuration
env.DB        // Type: D1Database
env.CACHE     // Type: KVNamespace
env.MY_VAR    // Type: string
```

## Platform resources and bindings

Cloudflare Workers integrate with platform resources via bindings configured in wrangler.jsonc.

See @~/.claude/commands/preferences/cloudflare-wrangler-reference.md for comprehensive binding configuration.

### D1 databases (serverless SQL)

```jsonc
{
  "d1_databases": [
    {
      "binding": "DB",
      "database_id": "your-database-id",
      "experimental_remote": true
    }
  ]
}
```

**Usage**:

```typescript
import { drizzle } from "drizzle-orm/d1";

const db = drizzle(env.DB);
const users = await db.select().from(usersTable);
```

### KV namespaces (key-value caching)

```jsonc
{
  "kv_namespaces": [
    {
      "binding": "CACHE",
      "id": "your-kv-namespace-id",
      "experimental_remote": true
    }
  ]
}
```

**Usage**:

```typescript
// Cache API responses
await env.CACHE.put("user:123", JSON.stringify(user), {
  expirationTtl: 3600 // 1 hour
});

const cached = await env.CACHE.get("user:123", "json");
```

### R2 buckets (object storage)

```jsonc
{
  "r2_buckets": [
    {
      "binding": "BUCKET",
      "bucket_name": "my-storage"
    }
  ]
}
```

**Usage**:

```typescript
// S3-compatible API
await env.BUCKET.put("uploads/file.pdf", fileData, {
  httpMetadata: {
    contentType: "application/pdf"
  }
});

const file = await env.BUCKET.get("uploads/file.pdf");
const blob = await file.blob();
```

### Service bindings (microservices)

Service bindings enable type-safe communication between multiple workers.

```jsonc
{
  "services": [
    {
      "binding": "BACKEND_SERVICE",
      "service": "data-service-production",
      "experimental_remote": true
    }
  ]
}
```

**Usage**:

```typescript
// Call another worker service
const response = await env.BACKEND_SERVICE.fetch(
  new Request("https://internal/api/data", {
    method: "POST",
    body: JSON.stringify({ query: "..." })
  })
);

const data = await response.json();
```

**Pattern**: Monorepo with multiple worker apps communicating via service bindings.

```
apps/
  user-application/     # Frontend worker (TanStack Start)
  data-service/         # Backend worker (Hono API)
```

See backpine-saas-kit for reference implementation.

### Queues (async message processing)

```jsonc
{
  "queues": {
    "producers": [
      {
        "binding": "QUEUE",
        "queue": "data-processing-queue"
      }
    ],
    "consumers": [
      {
        "queue": "data-processing-queue",
        "dead_letter_queue": "data-processing-dlq"
      }
    ]
  }
}
```

**Producer usage**:

```typescript
// Send message to queue
await env.QUEUE.send({
  userId: "123",
  action: "process_upload"
});

// Batch send
await env.QUEUE.sendBatch([
  { body: { userId: "123" } },
  { body: { userId: "456" } }
]);
```

**Consumer handler**:

```typescript
export default {
  async queue(batch: MessageBatch, env: Env): Promise<void> {
    for (const message of batch.messages) {
      try {
        await processMessage(message.body);
        message.ack();
      } catch (error) {
        message.retry();
      }
    }
  }
}
```

### Workflows (durable execution)

Long-running, durable processes that survive worker restarts.

```jsonc
{
  "workflows": [
    {
      "binding": "MY_WORKFLOW",
      "name": "my-workflow-production",
      "class_name": "MyWorkflow"
    }
  ]
}
```

**Workflow definition**:

```typescript
import { WorkflowEntrypoint, WorkflowStep } from "cloudflare:workers";

export class MyWorkflow extends WorkflowEntrypoint {
  async run(event: any, step: WorkflowStep) {
    // Steps are checkpointed - execution resumes on failure
    const result1 = await step.do("fetch-data", async () => {
      return await fetch("https://api.example.com/data");
    });

    // Sleep preserves state
    await step.sleep("wait-for-processing", "1 hour");

    const result2 = await step.do("process-data", async () => {
      return processData(result1);
    });

    return result2;
  }
}
```

### Durable Objects (stateful compute)

Strongly consistent, stateful workers with persistent storage.

```jsonc
{
  "durable_objects": {
    "bindings": [
      {
        "name": "COUNTER",
        "class_name": "Counter"
      }
    ]
  },
  "migrations": [
    {
      "tag": "v1",
      "new_classes": ["Counter"]
    }
  ]
}
```

**Durable Object definition**:

```typescript
import { DurableObject } from "cloudflare:workers";

export class Counter extends DurableObject {
  async fetch(request: Request) {
    let count = (await this.ctx.storage.get<number>("count")) || 0;
    count++;
    await this.ctx.storage.put("count", count);
    return new Response(count.toString());
  }
}
```

**Access from worker**:

```typescript
// Create unique Durable Object instance
const id = env.COUNTER.idFromName("global-counter");
const stub = env.COUNTER.get(id);

// Call Durable Object
const response = await stub.fetch(request);
```

### Workers AI (AI model inference)

```jsonc
{
  "ai": {
    "binding": "AI"
  }
}
```

**Usage**:

```typescript
const response = await env.AI.run("@cf/meta/llama-2-7b-chat-int8", {
  prompt: "What is the capital of France?"
});
```

### Browser rendering

```jsonc
{
  "browser": {
    "binding": "VIRTUAL_BROWSER"
  }
}
```

**Usage**:

```typescript
const browser = await env.VIRTUAL_BROWSER.launch();
const page = await browser.newPage();
await page.goto("https://example.com");
const screenshot = await page.screenshot();
```

## TanStack Start SSR deployment

Deploy TanStack Start applications to Cloudflare Workers with SSR support.

### Project structure

```
src/
  routes/              # File-based routes
  server.ts            # Custom Cloudflare Workers entry point
  start.tsx            # TanStack Start client entry
vite.config.ts         # Vite + Cloudflare plugin configuration
wrangler.jsonc         # Cloudflare deployment configuration
```

### Vite configuration with Cloudflare plugin

```typescript
// vite.config.ts
import { defineConfig } from "vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
import viteTsConfigPaths from "vite-tsconfig-paths";
import tailwindcss from "@tailwindcss/vite";
import { cloudflare } from "@cloudflare/vite-plugin";

export default defineConfig({
  plugins: [
    viteTsConfigPaths({
      projects: ["./tsconfig.json"],
    }),
    tailwindcss(),
    tanstackStart({
      srcDirectory: "src",
      start: { entry: "./start.tsx" },
      server: { entry: "./server.ts" }, // Custom server entry
    }),
    viteReact(),
    cloudflare({
      viteEnvironment: {
        name: "ssr", // Enable SSR environment
      },
    }),
  ],
});
```

### Custom server entry point

```typescript
// src/server.ts
import { setAuth } from "@repo/data-ops/auth/server";
import { initDatabase } from "@repo/data-ops/database/setup";
import handler from "@tanstack/react-start/server-entry";
import { env } from "cloudflare:workers";

export default {
  fetch(request: Request) {
    // Initialize database connection
    const db = initDatabase({
      host: env.DATABASE_HOST,
      username: env.DATABASE_USERNAME,
      password: env.DATABASE_PASSWORD,
    });

    // Configure authentication
    setAuth({
      secret: env.BETTER_AUTH_SECRET,
      socialProviders: {
        google: {
          clientId: env.GOOGLE_CLIENT_ID,
          clientSecret: env.GOOGLE_CLIENT_SECRET,
        },
      },
      adapter: {
        drizzleDb: db,
        provider: "pg", // or "sqlite" for D1
      },
    });

    // Delegate to TanStack Start handler
    return handler.fetch(request, {
      context: {
        db,
        // Additional context passed to routes
      },
    });
  },
};
```

### Wrangler configuration for SSR

```jsonc
{
  "name": "my-app",
  "main": "src/server.ts",
  "compatibility_date": "2025-04-10",
  "compatibility_flags": ["nodejs_compat"],

  "assets": {
    "directory": ".output/public",
    "binding": "ASSETS",
    "not_found_handling": "single-page-application",
    // API routes handled by worker before checking static assets
    "run_worker_first": ["/api/*", "/trpc/*", "/auth/*"]
  },

  "d1_databases": [
    {
      "binding": "DB",
      "database_id": "production-db-id"
    }
  ],

  "vars": {
    "API_URL": "https://api.example.com"
  }
}
```

### Deployment workflow

```bash
# Generate Cloudflare types
pnpm run cf-typegen

# Build application (runs Vite build)
pnpm run build

# Deploy to Cloudflare
pnpm run deploy

# Or combined
pnpm run build && wrangler deploy
```

### Server functions with Cloudflare bindings

```typescript
// src/core/functions/example-functions.ts
import { createServerFn } from "@tanstack/react-start";
import { env } from "cloudflare:workers";
import { z } from "zod";

const InputSchema = z.object({
  userId: z.string(),
});

export const fetchUserData = createServerFn()
  .validator((data) => InputSchema.parse(data))
  .handler(async ({ data }) => {
    // Access Cloudflare bindings
    const cached = await env.CACHE.get(`user:${data.userId}`, "json");
    if (cached) return cached;

    const user = await env.DB.prepare(
      "SELECT * FROM users WHERE id = ?"
    ).bind(data.userId).first();

    // Cache for 1 hour
    await env.CACHE.put(`user:${data.userId}`, JSON.stringify(user), {
      expirationTtl: 3600,
    });

    return user;
  });
```

## Static site deployment

Deploy client-only applications (no SSR) to Cloudflare Pages.

### When to use static deployment

**Use static deployment for**:
- Client-side rendered applications (Vite + React)
- Static site generators (Astro, VitePress)
- Documentation sites
- Marketing pages

**Use Workers deployment for**:
- Server-side rendering (TanStack Start, Remix)
- API routes or backend logic
- Authentication flows
- Dynamic content generation

### Cloudflare Pages deployment

**Via Git integration** (recommended):

1. Connect repository to Cloudflare Pages
2. Configure build settings in Cloudflare dashboard:
   - Build command: `pnpm run build`
   - Build output directory: `dist` (or `.output/public` for TanStack Start)
3. Automatic deployments on git push

**Via wrangler CLI**:

```bash
# Build application
pnpm run build

# Deploy to Pages
wrangler pages deploy dist --project-name=my-app

# Or configure in wrangler.jsonc with pages-specific settings
```

### Pages configuration for SPAs

```jsonc
{
  "pages": {
    "project_name": "my-app",
    "build_output_directory": "dist",
    // SPA mode - serve index.html for all non-asset routes
    "single_page_application": true
  }
}
```

### Pages Functions (serverless API routes)

Add API routes to static sites with Pages Functions:

```
functions/
  api/
    hello.ts         # Available at /api/hello
    users/
      [id].ts        # Available at /api/users/:id
```

**Function example**:

```typescript
// functions/api/hello.ts
export async function onRequest(context) {
  const { request, env } = context;

  // Access bindings (KV, D1, etc.) via env
  const data = await env.KV.get("greeting");

  return new Response(JSON.stringify({ message: data }), {
    headers: { "Content-Type": "application/json" },
  });
}
```

## Multi-environment deployment strategies

Separate development, staging, and production environments with wrangler.jsonc env configuration.

### Environment configuration pattern

```jsonc
{
  "name": "my-app",

  // Default configuration (development)
  "vars": {
    "API_URL": "https://api-dev.example.com"
  },
  "d1_databases": [
    {
      "binding": "DB",
      "database_id": "dev-database-id",
      "experimental_remote": true
    }
  ],

  // Environment-specific overrides
  "env": {
    "stage": {
      "vars": {
        "API_URL": "https://api-stage.example.com"
      },
      "d1_databases": [
        {
          "binding": "DB",
          "database_id": "stage-database-id"
        }
      ],
      "routes": [
        {
          "pattern": "stage.example.com",
          "custom_domain": true
        }
      ]
    },

    "production": {
      "vars": {
        "API_URL": "https://api.example.com"
      },
      "d1_databases": [
        {
          "binding": "DB",
          "database_id": "production-database-id"
        }
      ],
      "routes": [
        {
          "pattern": "example.com",
          "custom_domain": true
        }
      ]
    }
  }
}
```

### Deploy to specific environment

```bash
# Deploy to staging
wrangler deploy --env stage

# Deploy to production
wrangler deploy --env production

# Local development (uses default config)
wrangler dev
```

### Environment-specific secrets

```bash
# Set secrets per environment
wrangler secret put DATABASE_PASSWORD --env stage
wrangler secret put DATABASE_PASSWORD --env production

# Secrets isolated between environments
```

### Package.json scripts for multi-environment

```json
{
  "scripts": {
    "dev": "vite dev",
    "build": "vite build",
    "deploy:stage": "pnpm run build && wrangler deploy --env stage",
    "deploy:production": "pnpm run build && wrangler deploy --env production",
    "cf-typegen": "wrangler types --env-interface Env"
  }
}
```

## Local development

### Wrangler dev for local testing

```bash
# Start local development server with remote bindings
wrangler dev

# Custom port
wrangler dev --port 3000

# With remote bindings (access production D1, KV)
wrangler dev --remote

# Enable experimental local mode
wrangler dev --experimental-local
```

**Note**: Use `experimental_remote: true` in bindings to access remote resources during local dev.

### Environment variables for local dev

```bash
# .dev.vars (gitignored - for local secrets)
DATABASE_PASSWORD=local-password
GOOGLE_CLIENT_SECRET=dev-client-secret
BETTER_AUTH_SECRET=local-auth-secret
```

**Wrangler loads `.dev.vars` automatically during `wrangler dev`**.

### Framework-specific dev servers

```bash
# TanStack Start (uses Vite + Cloudflare plugin)
pnpm dev

# Hono (direct wrangler dev)
wrangler dev --x-remote-bindings
```

## Observability and monitoring

### Enable observability in wrangler

```jsonc
{
  "observability": {
    "enabled": true
  }
}
```

Access metrics, logs, and traces in Cloudflare dashboard under Workers & Pages > [Your Worker] > Metrics.

### Logging patterns

```typescript
// Structured logging
console.log(JSON.stringify({
  level: "info",
  message: "User authenticated",
  userId: user.id,
  timestamp: new Date().toISOString(),
}));

// Error logging with context
console.error("Database query failed", {
  query: sql,
  error: error.message,
  userId: context.userId,
});
```

### Performance monitoring

```typescript
// Measure execution time
const start = Date.now();
await expensiveOperation();
const duration = Date.now() - start;

console.log(JSON.stringify({
  operation: "data_processing",
  duration_ms: duration,
}));
```

### Custom analytics with Analytics Engine

```jsonc
{
  "analytics_engine_datasets": [
    {
      "binding": "ANALYTICS"
    }
  ]
}
```

**Usage**:

```typescript
env.ANALYTICS.writeDataPoint({
  blobs: ["user_signup"],
  doubles: [1],
  indexes: [userId],
});
```

## Best practices

### Security

- **Never commit secrets** to wrangler.jsonc - use `wrangler secret put`
- **Use .dev.vars** for local development secrets (gitignored)
- **Validate all inputs** with Zod schemas at worker boundaries
- **Sanitize outputs** to prevent XSS in SSR contexts
- **Set CORS headers** explicitly for API routes

### Performance

- **Cache aggressively** with KV for read-heavy data
- **Use bindings** instead of fetch for inter-service communication
- **Minimize bundle size** - tree-shake unused code
- **Leverage edge caching** for static assets and API responses
- **Use streaming** for large responses

### Cost optimization

- **Use D1 over PostgreSQL** when possible (lower cost)
- **Implement caching** to reduce database queries
- **Batch operations** to reduce request count
- **Set appropriate TTLs** on cached data
- **Use free tier limits** strategically (D1, KV, Workers)

### Development workflow

- **Type generation first** - run `cf-typegen` after wrangler.jsonc changes
- **Test locally** with `wrangler dev --remote` for production parity
- **Use environments** for staging deployments before production
- **Automate deployments** via CI/CD with wrangler GitHub Actions
- **Monitor observability** dashboard for errors and performance

## Integration with other preferences

See related preference files for complementary patterns:

- @~/.claude/commands/preferences/react-tanstack-ui-development.md - TanStack Start SSR patterns
- @~/.claude/commands/preferences/typescript-nodejs-development.md - Hono backend patterns
- @~/.claude/commands/preferences/schema-versioning.md - Database migration workflows
- @~/.claude/commands/preferences/railway-oriented-programming.md - Error handling in server functions
- @~/.claude/commands/preferences/cloudflare-wrangler-reference.md - Comprehensive wrangler configuration

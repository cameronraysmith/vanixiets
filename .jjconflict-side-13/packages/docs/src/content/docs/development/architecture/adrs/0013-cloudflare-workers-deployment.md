---
title: "ADR-0013: Cloudflare Workers deployment"
---

## Status

Accepted

## Context

Deploying Astro-based documentation sites requires choosing a hosting platform:

**Static hosts:**
- **Netlify** - automatic builds, edge network, generous free tier
- **Vercel** - Next.js-optimized, excellent DX, good free tier
- **Cloudflare Pages** - fast, global CDN, unlimited bandwidth
- **GitHub Pages** - free, simple, limited features

**Serverless platforms:**
- **Cloudflare Workers** - edge computing, global distribution, SSR support
- **AWS Lambda + CloudFront** - full AWS integration, more complex
- **Netlify Functions** - integrated with Netlify, limited execution time

**Considerations:**
- SSR capabilities (dynamic content generation)
- Global distribution (edge locations)
- Cost structure (bandwidth, compute, requests)
- Developer experience (deployment workflow)
- Vendor lock-in

## Decision

Deploy to **Cloudflare Workers** using the Astro Cloudflare adapter.

## Build Process

1. Astro builds static site and SSR components
2. Cloudflare adapter creates Worker bundle (packages SSR handler with static assets)
3. Wrangler CLI deploys to Cloudflare Workers

## Configuration

**wrangler.jsonc:**
- Worker name and routes
- Compatibility settings
- Environment variables (from SOPS)

**astro.config.ts:**
- Cloudflare adapter configuration
- Image service mode (`passthrough` - no Cloudflare Image Resizing needed)
- Platform proxy settings (disabled during tests)

## Rationale

**Positive:**
- **Global edge deployment** - Workers run in 200+ locations worldwide
- **SSR capabilities** - can generate dynamic content if needed in future
- **Cost-effective** - free tier: 100k requests/day, paid tier very reasonable
- **Fast cold starts** - Workers start in <1ms
- **Excellent deployment experience** - wrangler CLI is fast and reliable
- **No server management** - fully managed platform
- **Unlimited bandwidth** - no egress charges
- **Native HTTPS** - automatic SSL certificates

**Negative:**
- Vendor lock-in to Cloudflare
- Worker runtime limitations (no Node.js APIs, some packages incompatible)
- 1MB script size limit (rarely hit with Astro)
- Debugging is harder than traditional servers

**Neutral:**
- Need to manage Cloudflare credentials
- Custom domains require DNS configuration

## Trade-offs

### vs Cloudflare Pages

**Workers advantages:**
- More control over Worker script
- Direct integration with other Cloudflare services
- Better for programmatic deployment (wrangler in CI/CD)

**Pages advantages:**
- Simpler deployment (git push)
- Built-in preview deployments
- Simpler configuration

**Decision:** Workers chosen for flexibility and CI/CD integration.

### vs Vercel

**Workers advantages:**
- More cost-effective at scale
- Global edge network (Vercel's edge is more limited)
- No vendor lock-in to Next.js ecosystem

**Vercel advantages:**
- Better DX for Next.js projects
- Automatic preview deployments
- Better analytics and monitoring

**Decision:** Workers chosen for cost and edge distribution.

### vs Static-only (Netlify/GitHub Pages)

**Workers advantages:**
- SSR capability available (future-proof)
- More flexible routing
- Can add dynamic features without migration

**Static advantages:**
- Simpler deployment
- No runtime costs
- Easier to debug

**Decision:** Workers chosen for SSR capability even though currently serving static content.

## Consequences

**For developers:**
- Use `wrangler dev` for local development
- Can test Worker-specific features locally
- Fast deployment (wrangler CLI)

**For users:**
- Fast page loads globally
- Minimal latency regardless of location

**For operations:**
- Need Cloudflare account and API tokens
- Environment variables managed via SOPS + wrangler secrets
- Can configure custom domains via Cloudflare DNS

**For template users:**
- Must set up Cloudflare account
- Can easily switch to different adapter (Netlify, Vercel, Node) if preferred
- Configuration in `wrangler.jsonc` needs customization

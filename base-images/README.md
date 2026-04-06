# Shared Base Images

This directory contains shared platform image definitions intended to reduce duplicated common layers across tenant image builds.

## Directory Layout

- `runtime-base/`
  - production runtime foundation
  - should stay small and stable

- `builder-base/`
  - build-stage foundation
  - can contain common toolchain packages

## Why These Images Exist

Tenant-specific images should only focus on tenant application code and tenant dependencies.

Anything that is common across most tenant images should move into a shared base image when it is stable enough.

This reduces:

- repeated setup in tenant Dockerfiles
- duplicated cached layers across per-org ECR repositories
- drift between build environments

## Usage Model

Builder base:

```dockerfile
FROM <shared-builder-base> AS builder
```

Runtime base:

```dockerfile
FROM <shared-runtime-base>
```

## Recommendation

Keep these images versioned and explicit.

Examples:

- `nitrostack-builder-base:node20-v1`
- `nitrostack-runtime-base:node20-v1`

Avoid floating production tags as the only reference.

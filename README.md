# NitroCloud Build Infrastructure

This workspace contains the build assets for NitroCloud tenant image creation.

The current design is optimized for:

- multi-tenant builds
- per-org ECR repositories
- ECR-backed Docker cache reuse
- ARM-native CodeBuild environments
- clean separation between build orchestration and Docker image definitions

## Current Layout

- `buildspec.codebuild.yml`
  - CodeBuild entrypoint
  - downloads tenant source from S3
  - pulls remote ECR cache when available
  - selects the correct Dockerfile template
  - builds and pushes the tenant image

- `scripts/select-dockerfile-template.sh`
  - inspects the downloaded app
  - picks the correct Dockerfile template
  - copies it into the app directory as `Dockerfile`

- `build-templates/docker/`
  - versioned tenant image templates
  - currently includes:
    - `Dockerfile.nitro-v2`
    - `Dockerfile.nitro-legacy`
    - `Dockerfile.node`

- `.dockerignore`
  - reduces Docker build context size
  - improves cache stability and upload performance

- `base-images/`
  - shared platform image definitions
  - separated into runtime and builder images
  - intended for future optimization and cross-tenant deduplication

## Current Build Flow

1. CodeBuild starts with `buildspec.codebuild.yml`.
2. It logs into the target ECR registry.
3. It tries to pull `:buildcache` from the target ECR repository.
4. It downloads the tenant source bundle from S3.
5. It finds the tenant app directory by locating `package.json`.
6. It copies the local Dockerfile templates and selector script into the build workspace.
7. The selector script chooses the correct Dockerfile template.
8. Docker builds the image, optionally using `--cache-from` with the ECR cache image.
9. CodeBuild pushes:
   - `$IMAGE_TAG`
   - `latest`
   - `buildcache`

## Why We Use ECR Cache Only

This setup intentionally avoids CodeBuild local Docker caching.

Reason:

- CodeBuild workers are effectively stateless for this use case.
- Local host cache is unreliable across builds.
- ECR cache works across hosts and is the correct reusable layer source.

The current caching strategy is:

- pull `repo:buildcache` before build
- build with `--cache-from repo:buildcache`
- push updated `repo:buildcache` after a successful build

This makes the first build work without cache and allows the second build onward to reuse remote layers.

## Why Templates Are Stored As Files

We moved away from generating Dockerfiles inline inside `buildspec.yml`.

That is better because:

- YAML stays readable
- Dockerfiles are versioned like normal source files
- updates are easier to review
- build failures are easier to debug
- later migration to S3-hosted immutable templates becomes straightforward

## Future S3 Template Model

The next step after repo-based testing is:

- keep templates authored in Git
- publish approved template versions to S3
- make tenant builds fetch immutable template versions from S3

Recommended pattern:

- do not use a floating `latest` template in production
- publish versioned template paths instead

Example:

```text
s3://nitrocloud-build-templates/docker/v2026-04-03-001/Dockerfile.nitro-v2
s3://nitrocloud-build-templates/docker/v2026-04-03-001/Dockerfile.nitro-legacy
s3://nitrocloud-build-templates/docker/v2026-04-03-001/Dockerfile.node
```

This provides:

- immutability
- rollback safety
- auditability
- controlled rollout of template changes

## Why Base Images Still Matter Even With ECR Cache

ECR cache helps per repository build history.

Shared base images solve a different problem:

- duplicated common layers across many tenant repositories
- repeated platform setup in every tenant image
- inconsistent runtime and build environments

If every tenant image currently installs the same stable components, that work is duplicated across many repositories and cache images.

A shared base-image strategy reduces that duplication.

## Base Image Strategy

This workspace includes two separate shared image definitions under `base-images/`:

- `runtime-base`
- `builder-base`

These are intentionally separated because runtime and build concerns are different.

### Runtime Base Image

Purpose:

- final production image foundation
- minimal stable runtime dependencies
- NitroStack CLI available at runtime

Recommended contents:

- `node:20-alpine`
- `procps`
- `@nitrostack/cli`
- small shared runtime dependencies required by all NitroStack apps

Should not include:

- tenant application dependencies
- arbitrary framework libraries
- large build toolchains

### Builder Base Image

Purpose:

- shared build-stage foundation
- common build toolchain for widgets, MCP-related builds, and native modules

Recommended contents:

- `node:20-alpine`
- `python3`
- `make`
- `g++`
- `git`
- optionally `@nitrostack/cli`

This image is heavier than runtime and is only meant for the build stage.

## Should React, Next.js, Or MCP Libraries Be Preinstalled?

Usually, no for application libraries.

Why:

- tenant builds still install dependencies from the tenant app `package.json`
- global framework packages in the base image do not replace tenant-local `node_modules`
- preloading many JS libraries makes the base image larger and harder to maintain

What does make sense to preload:

- system build tools
- stable CLI tools
- shared OS-level dependencies

What usually should remain tenant-local:

- `react`
- `next`
- app-level MCP libraries
- widget framework libraries
- anything with frequent version drift

## Expected Time Savings

Approximate impact:

- ECR cache only:
  - good repeat-build improvement for unchanged layers

- runtime base image:
  - typically saves the repeated runtime setup layer

- builder base image:
  - typically saves repeated toolchain installation across many builds

Most real savings come from combining:

- stable Dockerfile layer ordering
- ECR cache
- shared runtime base image
- shared builder base image
- small Docker build context via `.dockerignore`

## Multi-Tenant ECR Model

In a multi-tenant setup, each org can still have its own ECR repository for final images.

Example:

- shared base image repos:
  - `shared/nitrostack-runtime-base`
  - `shared/nitrostack-builder-base`

- tenant image repos:
  - `org-a/app-image`
  - `org-b/app-image`

This model gives:

- shared platform layers once
- tenant-specific application images separately
- less duplicated platform setup across per-org repositories

## Recommended Evolution Path

1. Test the current repo-based template model.
2. Move Dockerfile templates to immutable S3 versioned paths.
3. Build and publish shared runtime and builder base images.
4. Update tenant Dockerfile templates to use those shared base images.
5. Keep ECR `buildcache` enabled for tenant-specific layers.

This gives a clean progression without changing too many moving parts at once.

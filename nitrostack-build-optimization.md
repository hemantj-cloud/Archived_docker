## 📑 Quick Summary (tl;dr)
*   **Current State**: Builds are "manual" and install `@nitrostack/cli` every time (slow).
*   **The Fix**: Use **Docker Buildx** with **Registry Caching** for instant layer hits.
*   **The Goal**: **Leverage Existing Base Images** (`runtime-base` & `builder-base`) to shave 30+ seconds off every build.

### 🔄 Build Steps Progression
| **Old Flow (10 Steps)** | **New Optimized Flow (6 Steps)** |
| :--- | :--- |
| 1. Validate inputs | 1. Validate inputs |
| 2. Login to ECR | 2. Login to ECR |
| 3. **Manual pull** cache image | 3. **(Automated)** Download & Extract Source |
| 4. Download source from S3 | 4. Select Dockerfile Template |
| 5. Extract & Locate App | 5. **(Atomic)** Build & Push with Cache |
| 6. Copy Docker Templates | 6. Output Image URI |
| 7. Select Dockerfile Script | |
| 8. Build Image | |
| 9. Push to ECR | |
| 10. Output Image URI | |

---
# NitroStack Build Optimization Plan

This document outlines the improvements made to the AWS CodeBuild process and the strategy for further optimization using a custom base image.

## 🚀 Optimized Buildspec

The current `buildspec.codebuild.yml` has been updated to use **Docker Buildx**. This provides several advantages over the standard `docker build` command:

1.  **Registry Caching**: Uses `--cache-from` and `--cache-to` with `type=registry`. This is significantly faster than a manual `docker pull` because it only fetches the metadata and layers needed to verify cache hits.
2.  **Atomic Build & Push**: The `--push` flag handles both operations in a single command, reducing the overhead and risk of separate push failures.
3.  **Modern Validation**: Uses efficient `${VAR:?error}` syntax for mandatory environment variables.

### Current Buildspec (Buildx Optimized)

```yaml
version: 0.2

env:
  variables:
    DOCKER_BUILDKIT: "1"
    CACHE_TAG: "buildcache"
    TARGET_PLATFORM: "linux/arm64"
    TEMPLATE_DIR: "build-templates/docker"

phases:
  pre_build:
    commands:
      - set -eu
      # 1. Mandatory Input Validation
      - : "${ECR_REPOSITORY_URI:?ECR_REPOSITORY_URI must be set}"
      - : "${CODE_BUCKET:?CODE_BUCKET must be set}"
      - : "${S3_KEY:?S3_KEY must be set}"
      
      # 2. ECR Login
      - ECR_REGISTRY="$(echo "$ECR_REPOSITORY_URI" | cut -d/ -f1)"
      - aws ecr get-login-password --region "${AWS_REGION:-us-east-1}" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
      
      # 3. Initialize Buildx
      - docker buildx create --use

      # 4. S3 Source Preparation
      - aws s3 cp "s3://$CODE_BUCKET/$S3_KEY" /tmp/code-package.zip
      - mkdir -p /tmp/build && unzip -q /tmp/code-package.zip -d /tmp/build
      - APP_DIR="$(dirname $(find /tmp/build -name package.json -not -path '*/node_modules/*' | head -n 1))"
      - echo "Building from $APP_DIR"

  build:
    commands:
      # 5. Select Dockerfile Template
      - cp -R "$CODEBUILD_SRC_DIR/$TEMPLATE_DIR" /tmp/template-dir
      - cd "$APP_DIR"
      - bash "$CODEBUILD_SRC_DIR/scripts/select-dockerfile-template.sh" /tmp/template-dir
      
      # 6. Build and Push with Registry Cache
      - |
        docker buildx build \
          --platform "$TARGET_PLATFORM" \
          --cache-from "type=registry,ref=$ECR_REPOSITORY_URI:$CACHE_TAG" \
          --cache-to "type=registry,ref=$ECR_REPOSITORY_URI:$CACHE_TAG,mode=max" \
          -t "$ECR_REPOSITORY_URI:$IMAGE_TAG" \
          -t "$ECR_REPOSITORY_URI:latest" \
          --push .

  post_build:
    commands:
      - |
        if [ "${CODEBUILD_BUILD_SUCCEEDING:-0}" = "1" ]; then
          echo "IMAGE_URI=$ECR_REPOSITORY_URI:$IMAGE_TAG" > /tmp/build-output.txt
          echo "Build & Push Success: $ECR_REPOSITORY_URI:$IMAGE_TAG"
        fi

artifacts:
  files:
    - /tmp/build-output.txt
```

---

## 🛠️ Leveraging Existing Base Images

The project already includes pre-defined base image configurations to optimize build times. These should be utilized to ensure all builds are using a consistent, pre-configured environment.

### 1. Existing Base Image Definitions
You can find the base image definitions in the project at:
*   [base-images/runtime-base/Dockerfile](file:///Users/admin/Desktop/extras/Archived_docker/base-images/runtime-base/Dockerfile): Optimized for execution (production).
*   [base-images/builder-base/Dockerfile](file:///Users/admin/Desktop/extras/Archived_docker/base-images/builder-base/Dockerfile): Optimized for compilation (includes build-essential tools like `make`, `g++`, etc.).

### 2. Strategy: Pre-building to ECR
Instead of installing `@nitrostack/cli` inside every app build, we should push these base images to ECR.

#### Step A: Build & Push the Project Base Images
```bash
# Push the runtime base
docker build -t nitrostack/runtime-base:20-alpine ./base-images/runtime-base
docker push <ECR_URI>/nitrostack/runtime-base:20-alpine

# Push the builder base
docker build -t nitrostack/builder-base:20-alpine ./base-images/builder-base
docker push <ECR_URI>/nitrostack/builder-base:20-alpine
```

### 3. Implementation in Application Templates
We can now update the application templates to use these existing images. For example, in [Dockerfile.nitro-v2](file:///Users/admin/Desktop/extras/Archived_docker/build-templates/docker/Dockerfile.nitro-v2):

```dockerfile
# USE EXISTING BUILDER BASE
FROM <ECR_URI>/nitrostack/builder-base:20-alpine AS builder
# (No need to install python, make, or CLI here!)

WORKDIR /app
COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi
COPY . .
RUN npm run build
# ...

# USE EXISTING RUNTIME BASE
FROM <ECR_URI>/nitrostack/runtime-base:20-alpine AS production
# (No need to install procps or CLI here!)

WORKDIR /app
COPY --from=builder --chown=node:node /app /app
USER node
EXPOSE 3000
CMD ["nitrostack-cli", "start"]
```

### 📈 Expected Benefits
- **Zero Configuration**: Leveraging the files already in the repo ensures no "new" dependencies are added.
- **Speed**: Shaves off 20+ seconds by pre-installing the heavy CLI and system dependencies (`procps`, `python`, etc.).
- **Consistency**: Guarantees that the version of NitroStack CLI matches across all builds.

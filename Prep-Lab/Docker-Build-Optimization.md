## DevOps Interview Lab: Docker Build Optimization

### **Scenario Context**
"You're leading a microservices migration. The team complains Docker builds take 8+ minutes. Your task is to optimize the Node.js service build pipeline while demonstrating best practices."

---

## **Lab Setup & Prerequisites**

```bash
# Initial setup on local laptop
mkdir ~/docker-optimization-lab && cd ~/docker-optimization-lab

# Create demo application with intentional anti-patterns
cat > app.js << 'EOF'
const express = require('express');
const app = express();
app.get('/', (req, res) => res.send('Optimized Docker Demo'));
app.listen(3000, () => console.log('Running on port 3000'));
EOF

cat > package.json << 'EOF'
{
  "name": "optimization-demo",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.0",
    "lodash": "^4.17.21",
    "axios": "^1.4.0"
  }
}
EOF

# Generate package-lock.json
npm init -y && npm install

# Create bloated test directory (simulates large dependencies)
mkdir tests && dd if=/dev/zero of=tests/large.dat bs=1M count=100

# Initialize git repo (adds to .git folder weight)
git init && echo "test" > file.txt && git add . && git commit -m "init"
```

---

## **Step 1: Baseline Anti-Pattern Build (The Problem)**

```dockerfile
# Dockerfile.bad
FROM node:latest
WORKDIR /app
COPY . .
RUN npm install
CMD ["node", "app.js"]
```

**Build & Measure:**
```bash
# Time the problematic build
time docker build -f Dockerfile.bad -t app:bad .

# Expected output: ~60-120 seconds (depends on network)
# Note: Even changing 1 line in app.js forces full npm install rebuild
```

**Interview Discussion Point:** *"What's the cache invalidation issue here?"*
- Every code change invalidates line 3 (`COPY . .`)
- Line 4 (`RUN npm install`) rebuilds from scratch

---

## **Step 2: Layer Caching Optimization**

```dockerfile
# Dockerfile.step2
FROM node:18-alpine
WORKDIR /app

# Copy only dependency manifests FIRST (leverages Docker cache)
COPY package*.json ./
RUN npm ci --only=production

# Then copy application code
COPY . .
CMD ["node", "app.js"]
```

**Implement & Test:**
```bash
# First build (still slow - downloads dependencies)
time docker build -f Dockerfile.step2 -t app:step2 .

# Make a code change
echo "// cache test" >> app.js

# Second build (FAST - uses cached npm ci layer)
time docker build -f Dockerfile.step2 -t app:step2 .

# Expected: Build time drops 70-80% (2-5 seconds for rebuild)
```

**Key Metrics:**
```bash
# Verify layer caching
docker history app:step2 --no-trunc | grep -A2 "package"
# Should show "CACHED" for npm ci layer
```

---

## **Step 3: .dockerignore Implementation**

```bash
# Create .dockerignore file
cat > .dockerignore << 'EOF'
.git
node_modules
tests/*.dat
*.md
.gitignore
Dockerfile*
.dockerignore
npm-debug.log
EOF

# Demonstrate size difference
echo "=== BEFORE .dockerignore ==="
docker build -f Dockerfile.step2 -t app:noignore . 2>&1 | grep "Sending build context"

echo "=== AFTER .dockerignore ==="
docker build -f Dockerfile.step2 -t app:ignore . 2>&1 | grep "Sending build context"

# Expected: Context size drops from ~100MB to <1MB
```

**Prove It Matters:**
```bash
# Show what gets excluded
docker build --no-cache -f Dockerfile.step2 -t test . --progress=plain 2>&1 | grep -i "COPY"
```

---

## **Step 4: Multi-Stage Build for Production**

```dockerfile
# Dockerfile.step4
# Stage 1: Builder
FROM node:18-alpine AS builder
WORKDIR /build
COPY package*.json ./
RUN npm ci

# Copy and build (add build steps if needed)
COPY . .
RUN npm run build 2>/dev/null || echo "No build script"

# Stage 2: Production
FROM node:18-alpine
RUN apk add --no-cache tini
WORKDIR /app

# Copy only production artifacts
COPY --from=builder --chown=node:node /build/node_modules ./node_modules
COPY --chown=node:node package*.json ./
COPY --chown=node:node app.js .

USER node
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "app.js"]
```

**Build & Compare:**
```bash
# Build optimized image
docker build -f Dockerfile.step4 -t app:optimized .

# Compare sizes
echo "=== Image Size Comparison ==="
docker images | grep -E "app:bad|app:step2|app:optimized"

# Expected results:
# app:bad         ~980MB (node:latest + build tools)
# app:step2       ~150MB (node:alpine + deps)
# app:optimized   ~120MB (multi-stage stripped)
```

---

## **Step 5: Command Chaining & Alpine Migration**

```dockerfile
# Dockerfile.final
FROM node:18-alpine AS builder
WORKDIR /app

# BAD: Separate RUN commands create bloat layers
# RUN apk update
# RUN apk add python3 make g++
# RUN npm install -g node-gyp

# GOOD: Chain commands and clean in same layer
RUN apk add --no-cache --virtual .build-deps \
    python3 \
    make \
    g++ \
    && npm install -g node-gyp \
    && apk del .build-deps

COPY package*.json ./
RUN npm ci --only=production --no-audit --no-fund

COPY . .
RUN npm prune --production

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package*.json ./
COPY . .

EXPOSE 3000
CMD ["node", "app.js"]
```

**Verify Layer Efficiency:**
```bash
# Build final optimized version
docker build -f Dockerfile.final -t app:final .

# Inspect layers - should see fewer intermediate layers
docker history app:final --format "table {{.CreatedBy}}\t{{.Size}}"

# Run security check
docker scan app:final 2>/dev/null || echo "Install Docker Scan: docker scan --accept-license"
```

---

## **Step 6: Benchmark & Validation Suite**

```bash
#!/bin/bash
# benchmark.sh - Interview-ready performance metrics

echo "=== DOCKER BUILD OPTIMIZATION BENCHMARKS ==="

# Function to measure build time
measure_build() {
    local tag=$1
    local dockerfile=$2
    echo -n "Building $tag... "
    time docker build -f $dockerfile -t $tag . > /dev/null 2>&1
}

# Measure after code change
echo "// benchmark change" >> app.js

echo -e "\n1. COLD BUILDS (no cache)"
measure_build "app:bad" "Dockerfile.bad"
measure_build "app:final" "Dockerfile.final"

echo -e "\n2. WARM BUILDS (with cache)"
measure_build "app:bad" "Dockerfile.bad"
measure_build "app:final" "Dockerfile.final"

echo -e "\n3. IMAGE METRICS"
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep "app:"

echo -e "\n4. LAYER ANALYSIS"
docker history app:final --no-trunc | head -6

# Cleanup
rm app.js 2>/dev/null
```

---

## **Interview Q&A Cheat Sheet**

| **Problem** | **Optimization** | **Why It Works** |
|------------|-----------------|------------------|
| `COPY . .` then `RUN npm install` | Copy package.json first | Docker caches layers; dependencies only reinstall when manifest changes |
| Bloated images (1GB+) | Use `-alpine` base images | Alpine Linux is ~5MB vs Ubuntu ~70MB |
| Build tools in runtime | Multi-stage builds | Build tools stay in builder stage, only artifacts copied |
| Layer bloat | Chain `RUN` commands with `&&` and clean in same layer | Each `RUN` creates immutable layer; cleaning in same layer removes files before layer freeze |
| Slow context sending | `.dockerignore` | Excludes .git, node_modules, logs from build context |
| `npm install` inconsistencies | Use `npm ci` | Respects package-lock.json exactly, faster, CI-friendly |

---

## **Progressive Demonstration Script**

```bash
# demo.sh - Run this during interview to show progression
#!/bin/bash

echo "🎯 DEMO: From 90s builds to 3s rebuilds"

# Step 1: Show the pain
echo -e "\n❌ ANTI-PATTERN BUILD (slow)"
time docker build -f Dockerfile.bad -t demo:bad . 2>&1 | grep -E "Step|ERROR|SUCCESS"

# Step 2: Layer ordering fix
echo -e "\n✅ LAYER CACHING FIX"
time docker build -f Dockerfile.step2 -t demo:step2 . 2>&1 | grep -E "CACHED|Step"

# Step 3: Make trivial code change
echo "// trivial change" >> app.js
echo -e "\n⚡ REBUILD WITH CACHE (fast)"
time docker build -f Dockerfile.step2 -t demo:step2 . 2>&1 | grep -E "CACHED|duration"

# Step 4: Show size difference
echo -e "\n📊 IMAGE SIZES"
docker images | grep demo

# Step 5: Multi-stage production
echo -e "\n🏭 PRODUCTION OPTIMIZED"
time docker build -f Dockerfile.final -t demo:final . 2>&1 | tail -3
docker images demo:final
```

**Expected Output:**
```
demo:bad       ~1.2GB   90s build
demo:step2     ~180MB   85s first / 3s rebuild  
demo:final     ~95MB    45s first / 2s rebuild
```

---

## **Real Interview Questions to Answer**

1. **"Explain Docker layer caching like I'm a junior dev"**
   *Each instruction is a snapshot. If COPY hasn't changed, Docker reuses that snapshot instead of rebuilding.*

2. **"Why not use `npm install` instead of `npm ci`?"**  
   *`npm ci` fails if package-lock.json is out of sync, ensures reproducible builds, and skips dependency resolution*

3. **"How would you debug a bloated image?"**
   ```bash
   docker history image:tag --no-trunc | awk '{print $2, $4}'
   docker run -it --entrypoint sh image:tag
   du -sh /* 2>/dev/null | sort -h
   ```

4. **"What's the problem with `apt-get update` in a separate layer?"**
   *Cache is stale - if you later run `apt-get install`, it uses old package lists*

**Winner's Answer:** *"Implement all 5 optimizations: layer ordering, .dockerignore, multi-stage, Alpine base, and command chaining. This typically reduces build times from minutes to seconds and image sizes by 80%."*

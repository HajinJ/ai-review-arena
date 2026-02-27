#!/usr/bin/env bash
# =============================================================================
# Tests for scripts/detect-stack.sh
# =============================================================================

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"

source "$TESTS_DIR/test-helpers.sh"

SCRIPT="$REPO_DIR/scripts/detect-stack.sh"

echo "=== test-detect-stack.sh ==="

setup_temp_dir

# =========================================================================
# Test: Node.js project detection
# =========================================================================

PROJ="$TEMP_DIR/node-project"
mkdir -p "$PROJ"

cat > "$PROJ/package.json" <<'EOF'
{
  "name": "test-app",
  "dependencies": {
    "express": "^4.18.0",
    "pg": "^8.0.0",
    "mongoose": "^7.0.0"
  },
  "devDependencies": {
    "jest": "^29.0.0",
    "typescript": "^5.0.0"
  }
}
EOF

# Also add tsconfig for TypeScript detection
cat > "$PROJ/tsconfig.json" <<'EOF'
{"compilerOptions": {"target": "ES2020"}}
EOF

result=$(bash "$SCRIPT" "$PROJ" 2>/dev/null)
assert_json_valid "$result" "node.js: output is valid JSON"

langs=$(echo "$result" | jq -r '.languages | join(",")')
assert_contains "$langs" "nodejs" "node.js: detects nodejs"

frameworks=$(echo "$result" | jq -r '.frameworks | join(",")')
assert_contains "$frameworks" "express" "node.js: detects express framework"

databases=$(echo "$result" | jq -r '.databases | join(",")')
assert_contains "$databases" "postgresql" "node.js: detects postgresql via pg"
assert_contains "$databases" "mongodb" "node.js: detects mongodb via mongoose"

testing=$(echo "$result" | jq -r '.testing | join(",")')
assert_contains "$testing" "jest" "node.js: detects jest"

# TypeScript detection
langs_full=$(echo "$result" | jq -r '.languages | join(",")')
assert_contains "$langs_full" "typescript" "node.js: detects typescript"

# =========================================================================
# Test: Python project detection (requirements.txt)
# =========================================================================

PROJ="$TEMP_DIR/python-project"
mkdir -p "$PROJ"

cat > "$PROJ/requirements.txt" <<'EOF'
django==4.2
redis==4.5.0
pytest==7.3.0
celery==5.3.0
EOF

result=$(bash "$SCRIPT" "$PROJ" 2>/dev/null)
assert_json_valid "$result" "python: output is valid JSON"

langs=$(echo "$result" | jq -r '.languages | join(",")')
assert_contains "$langs" "python" "python: detects python"

frameworks=$(echo "$result" | jq -r '.frameworks | join(",")')
assert_contains "$frameworks" "django" "python: detects django"
assert_contains "$frameworks" "celery" "python: detects celery"

databases=$(echo "$result" | jq -r '.databases | join(",")')
assert_contains "$databases" "redis" "python: detects redis"

testing=$(echo "$result" | jq -r '.testing | join(",")')
assert_contains "$testing" "pytest" "python: detects pytest"

# =========================================================================
# Test: Python project detection (pyproject.toml)
# =========================================================================

PROJ="$TEMP_DIR/python-pyproject"
mkdir -p "$PROJ"

cat > "$PROJ/pyproject.toml" <<'EOF'
[tool.poetry.dependencies]
python = "^3.11"
fastapi = "^0.100"
sqlalchemy = "^2.0"
EOF

result=$(bash "$SCRIPT" "$PROJ" 2>/dev/null)
langs=$(echo "$result" | jq -r '.languages | join(",")')
assert_contains "$langs" "python" "python pyproject: detects python"

frameworks=$(echo "$result" | jq -r '.frameworks | join(",")')
assert_contains "$frameworks" "fastapi" "python pyproject: detects fastapi"
assert_contains "$frameworks" "sqlalchemy" "python pyproject: detects sqlalchemy"

# =========================================================================
# Test: Go project detection
# =========================================================================

PROJ="$TEMP_DIR/go-project"
mkdir -p "$PROJ"

cat > "$PROJ/go.mod" <<'EOF'
module github.com/test/app
go 1.21
EOF

result=$(bash "$SCRIPT" "$PROJ" 2>/dev/null)
assert_json_valid "$result" "go: output is valid JSON"

langs=$(echo "$result" | jq -r '.languages | join(",")')
assert_contains "$langs" "golang" "go: detects golang"

# =========================================================================
# Test: Java project with Maven (pom.xml)
# =========================================================================

PROJ="$TEMP_DIR/java-maven"
mkdir -p "$PROJ"

cat > "$PROJ/pom.xml" <<'EOF'
<project>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter</artifactId>
    </dependency>
    <dependency>
      <groupId>mysql</groupId>
      <artifactId>mysql-connector-java</artifactId>
    </dependency>
  </dependencies>
</project>
EOF

result=$(bash "$SCRIPT" "$PROJ" 2>/dev/null)
assert_json_valid "$result" "java maven: output is valid JSON"

langs=$(echo "$result" | jq -r '.languages | join(",")')
assert_contains "$langs" "java" "java maven: detects java"

build_tools=$(echo "$result" | jq -r '.build_tools | join(",")')
assert_contains "$build_tools" "maven" "java maven: detects maven"

frameworks=$(echo "$result" | jq -r '.frameworks | join(",")')
assert_contains "$frameworks" "springboot" "java maven: detects springboot"

databases=$(echo "$result" | jq -r '.databases | join(",")')
assert_contains "$databases" "mysql" "java maven: detects mysql"

# =========================================================================
# Test: Java project with Gradle
# =========================================================================

PROJ="$TEMP_DIR/java-gradle"
mkdir -p "$PROJ"

cat > "$PROJ/build.gradle" <<'EOF'
plugins {
    id 'org.springframework.boot' version '3.0.0'
}
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter'
    implementation 'redis.clients:jedis'
}
EOF

result=$(bash "$SCRIPT" "$PROJ" 2>/dev/null)
build_tools=$(echo "$result" | jq -r '.build_tools | join(",")')
assert_contains "$build_tools" "gradle" "java gradle: detects gradle"

frameworks=$(echo "$result" | jq -r '.frameworks | join(",")')
assert_contains "$frameworks" "springboot" "java gradle: detects springboot"

# =========================================================================
# Test: Multi-stack detection
# =========================================================================

PROJ="$TEMP_DIR/multi-stack"
mkdir -p "$PROJ"

cat > "$PROJ/package.json" <<'EOF'
{
  "dependencies": {"react": "^18.0.0", "next": "^13.0.0"},
  "devDependencies": {"vitest": "^1.0.0"}
}
EOF

cat > "$PROJ/requirements.txt" <<'EOF'
fastapi==0.100
EOF

cat > "$PROJ/Dockerfile" <<'EOF'
FROM node:18
EOF

result=$(bash "$SCRIPT" "$PROJ" 2>/dev/null)
assert_json_valid "$result" "multi-stack: output is valid JSON"

langs=$(echo "$result" | jq -r '.languages | join(",")')
assert_contains "$langs" "nodejs" "multi-stack: detects nodejs"
assert_contains "$langs" "python" "multi-stack: detects python"

infra=$(echo "$result" | jq -r '.infrastructure | join(",")')
assert_contains "$infra" "docker" "multi-stack: detects docker"

all_tech=$(echo "$result" | jq '.all_technologies | length')
assert_gt "$all_tech" 3 "multi-stack: detects multiple technologies"

# =========================================================================
# Test: text output format
# =========================================================================

PROJ="$TEMP_DIR/text-output"
mkdir -p "$PROJ"
cat > "$PROJ/go.mod" <<'EOF'
module test
go 1.21
EOF

result=$(bash "$SCRIPT" "$PROJ" --output text 2>/dev/null)
assert_contains "$result" "Languages:" "text output: has Languages label"
assert_contains "$result" "golang" "text output: shows golang"

# =========================================================================
# Test: empty project (no detectable stack)
# =========================================================================

PROJ="$TEMP_DIR/empty-project"
mkdir -p "$PROJ"

result=$(bash "$SCRIPT" "$PROJ" 2>/dev/null)
assert_json_valid "$result" "empty project: output is valid JSON"

platform=$(echo "$result" | jq -r '.platform')
assert_eq "$platform" "unknown" "empty project: platform is unknown"

print_summary

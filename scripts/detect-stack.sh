#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Project Stack Auto-Detection
#
# Usage: detect-stack.sh [project-root] [--deep] [--output json|text]
#
# Scans the project for known configuration files, dependency manifests,
# and build files to determine the technology stack.
#
# Output: JSON (default) or text summary of detected stack.
#
# Exit codes:
#   0 - Always (informational tool)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ensure_jq

# --- Arguments ---
PROJECT_ROOT=""
DEEP_SCAN=false
OUTPUT_FORMAT="json"

while [ $# -gt 0 ]; do
  case "$1" in
    --deep) DEEP_SCAN=true; shift ;;
    --output) OUTPUT_FORMAT="${2:-json}"; shift 2 ;;
    -*) shift ;;
    *)
      if [ -z "$PROJECT_ROOT" ]; then
        PROJECT_ROOT="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT=$(find_project_root)
fi

# --- Detection State ---
LANGUAGES=()
FRAMEWORKS=()
DATABASES=()
INFRASTRUCTURE=()
BUILD_TOOLS=()
TESTING=()
CI_CD=()
PLATFORM=""

# --- Helper: add unique (bash 3.2 compatible, no nameref) ---
# Uses eval for dynamic array names — validated against allowlist for safety
add_unique() {
  local target_var="$1"
  local value="$2"
  # Safety: only allow known array names (prevents eval injection)
  case "$target_var" in
    LANGUAGES|FRAMEWORKS|DATABASES|INFRASTRUCTURE|BUILD_TOOLS|TESTING|CI_CD|ALL_TECHNOLOGIES) ;;
    *) return 1 ;;
  esac
  # Check if value already exists in array
  eval "local _items=(\"\${${target_var}[@]+\"\${${target_var}[@]}\"}\")"
  local item
  for item in "${_items[@]+"${_items[@]}"}"; do
    if [ "$item" = "$value" ]; then
      return 0
    fi
  done
  eval "${target_var}+=(\"\$value\")"
}

# --- Helper: file exists ---
has_file() {
  [ -f "$PROJECT_ROOT/$1" ]
}

# --- Helper: dir exists ---
has_dir() {
  [ -d "$PROJECT_ROOT/$1" ]
}

# --- Helper: grep in file ---
file_contains() {
  local file="$1"
  local pattern="$2"
  grep -q "$pattern" "$PROJECT_ROOT/$file" 2>/dev/null
}

# =============================================================================
# Detection: Java / JVM
# =============================================================================

detect_java_maven() {
  if ! has_file "pom.xml"; then return; fi

  add_unique LANGUAGES "java"
  add_unique BUILD_TOOLS "maven"

  if file_contains "pom.xml" "spring-boot"; then
    add_unique FRAMEWORKS "springboot"
  fi
  if file_contains "pom.xml" "spring-data-redis"; then
    add_unique DATABASES "redis"
  fi
  if file_contains "pom.xml" "mysql-connector"; then
    add_unique DATABASES "mysql"
  fi
  if file_contains "pom.xml" "kafka"; then
    add_unique INFRASTRUCTURE "kafka"
  fi
  if file_contains "pom.xml" "hibernate"; then
    add_unique FRAMEWORKS "hibernate"
  fi
  if file_contains "pom.xml" "elasticsearch"; then
    add_unique DATABASES "elasticsearch"
  fi
  if file_contains "pom.xml" "junit\|testng\|mockito"; then
    add_unique TESTING "junit"
  fi
}

detect_java_gradle() {
  local gradle_file=""
  if has_file "build.gradle"; then
    gradle_file="build.gradle"
  elif has_file "build.gradle.kts"; then
    gradle_file="build.gradle.kts"
  else
    return
  fi

  add_unique BUILD_TOOLS "gradle"

  if file_contains "$gradle_file" "kotlin\|\.kt"; then
    add_unique LANGUAGES "kotlin"
  fi
  add_unique LANGUAGES "java"

  if file_contains "$gradle_file" "com.android"; then
    add_unique FRAMEWORKS "android"
    add_unique LANGUAGES "kotlin"
  fi
  if file_contains "$gradle_file" "spring-boot"; then
    add_unique FRAMEWORKS "springboot"
  fi
  if file_contains "$gradle_file" "redis"; then
    add_unique DATABASES "redis"
  fi
  if file_contains "$gradle_file" "mysql"; then
    add_unique DATABASES "mysql"
  fi
}

# =============================================================================
# Detection: Node.js / JavaScript / TypeScript
# =============================================================================

detect_nodejs() {
  if ! has_file "package.json"; then return; fi

  add_unique LANGUAGES "nodejs"

  # Parse dependencies with jq
  local all_deps
  all_deps=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys[]' "$PROJECT_ROOT/package.json" 2>/dev/null || true)

  if [ -z "$all_deps" ]; then return; fi

  # Frameworks
  echo "$all_deps" | grep -q "^react$" && add_unique FRAMEWORKS "react"
  echo "$all_deps" | grep -q "^react-native$" && add_unique FRAMEWORKS "react-native"
  echo "$all_deps" | grep -q "^vue$" && add_unique FRAMEWORKS "vue"
  echo "$all_deps" | grep -q "^@angular/core$" && add_unique FRAMEWORKS "angular"
  echo "$all_deps" | grep -q "^svelte$" && add_unique FRAMEWORKS "svelte"
  echo "$all_deps" | grep -q "^express$" && add_unique FRAMEWORKS "express"
  echo "$all_deps" | grep -q "^fastify$" && add_unique FRAMEWORKS "fastify"
  echo "$all_deps" | grep -q "^@nestjs/core$" && add_unique FRAMEWORKS "nestjs"
  echo "$all_deps" | grep -q "^next$" && add_unique FRAMEWORKS "nextjs"

  # Databases & ORMs
  echo "$all_deps" | grep -q "^redis$\|^ioredis$" && add_unique DATABASES "redis"
  echo "$all_deps" | grep -q "^mysql$\|^mysql2$" && add_unique DATABASES "mysql"
  echo "$all_deps" | grep -q "^pg$" && add_unique DATABASES "postgresql"
  echo "$all_deps" | grep -q "^mongodb$\|^mongoose$" && add_unique DATABASES "mongodb"
  echo "$all_deps" | grep -q "^prisma$\|^@prisma/client$" && add_unique FRAMEWORKS "prisma"
  echo "$all_deps" | grep -q "^typeorm$" && add_unique FRAMEWORKS "typeorm"
  echo "$all_deps" | grep -q "^sequelize$" && add_unique FRAMEWORKS "sequelize"

  # Testing
  echo "$all_deps" | grep -q "^jest$" && add_unique TESTING "jest"
  echo "$all_deps" | grep -q "^vitest$" && add_unique TESTING "vitest"
  echo "$all_deps" | grep -q "^mocha$" && add_unique TESTING "mocha"
  echo "$all_deps" | grep -q "^@playwright/test$\|^playwright$" && add_unique TESTING "playwright"
  echo "$all_deps" | grep -q "^cypress$" && add_unique TESTING "cypress"

  # Build tools
  echo "$all_deps" | grep -q "^webpack$" && add_unique BUILD_TOOLS "webpack"
  echo "$all_deps" | grep -q "^vite$" && add_unique BUILD_TOOLS "vite"
  echo "$all_deps" | grep -q "^esbuild$" && add_unique BUILD_TOOLS "esbuild"
  echo "$all_deps" | grep -q "^turbo$\|^turborepo$" && add_unique BUILD_TOOLS "turborepo"
}

# =============================================================================
# Detection: Python
# =============================================================================

detect_python() {
  local has_python=false

  if has_file "requirements.txt"; then
    has_python=true
    if file_contains "requirements.txt" "django"; then
      add_unique FRAMEWORKS "django"
    fi
    if file_contains "requirements.txt" "fastapi"; then
      add_unique FRAMEWORKS "fastapi"
    fi
    if file_contains "requirements.txt" "flask"; then
      add_unique FRAMEWORKS "flask"
    fi
    if file_contains "requirements.txt" "celery"; then
      add_unique FRAMEWORKS "celery"
    fi
    if file_contains "requirements.txt" "redis"; then
      add_unique DATABASES "redis"
    fi
    if file_contains "requirements.txt" "sqlalchemy"; then
      add_unique FRAMEWORKS "sqlalchemy"
    fi
    if file_contains "requirements.txt" "pytest"; then
      add_unique TESTING "pytest"
    fi
  fi

  if has_file "pyproject.toml"; then
    has_python=true
    if file_contains "pyproject.toml" "django"; then
      add_unique FRAMEWORKS "django"
    fi
    if file_contains "pyproject.toml" "fastapi"; then
      add_unique FRAMEWORKS "fastapi"
    fi
    if file_contains "pyproject.toml" "flask"; then
      add_unique FRAMEWORKS "flask"
    fi
    if file_contains "pyproject.toml" "celery"; then
      add_unique FRAMEWORKS "celery"
    fi
    if file_contains "pyproject.toml" "redis"; then
      add_unique DATABASES "redis"
    fi
    if file_contains "pyproject.toml" "sqlalchemy"; then
      add_unique FRAMEWORKS "sqlalchemy"
    fi
  fi

  if [ "$has_python" = true ]; then
    add_unique LANGUAGES "python"
  fi
}

# =============================================================================
# Detection: Go, Rust
# =============================================================================

detect_go() {
  if has_file "go.mod"; then
    add_unique LANGUAGES "golang"
  fi
}

detect_rust() {
  if has_file "Cargo.toml"; then
    add_unique LANGUAGES "rust"
    add_unique BUILD_TOOLS "cargo"
  fi
}

# =============================================================================
# Detection: iOS / Swift / Xcode
# =============================================================================

detect_ios() {
  local found_ios=false

  # Check for .xcodeproj or .xcworkspace directories
  local xcode_proj
  xcode_proj=$(find "$PROJECT_ROOT" -maxdepth 2 -name "*.xcodeproj" -o -name "*.xcworkspace" 2>/dev/null | head -1)

  if [ -n "$xcode_proj" ]; then
    add_unique LANGUAGES "swift"
    add_unique FRAMEWORKS "ios"
    add_unique BUILD_TOOLS "xcode"
    found_ios=true
  fi

  if has_file "Podfile"; then
    add_unique BUILD_TOOLS "cocoapods"
    found_ios=true
  fi

  if has_file "Package.swift"; then
    add_unique LANGUAGES "swift"
    add_unique BUILD_TOOLS "spm"
  fi

  if [ "$found_ios" = true ]; then
    PLATFORM="client-mobile"
  fi
}

# =============================================================================
# Detection: Android
# =============================================================================

detect_android() {
  local found=false

  if has_file "app/src/main/AndroidManifest.xml" || has_file "AndroidManifest.xml"; then
    add_unique FRAMEWORKS "android"
    found=true
  fi

  # Might also be caught by gradle detection
  if [ "$found" = true ]; then
    if [ -z "$PLATFORM" ] || [ "$PLATFORM" = "client-mobile" ]; then
      PLATFORM="client-mobile"
    fi
  fi
}

# =============================================================================
# Detection: Infrastructure
# =============================================================================

detect_infrastructure() {
  if has_file "Dockerfile" || has_file "docker-compose.yml" || has_file "docker-compose.yaml"; then
    add_unique INFRASTRUCTURE "docker"
  fi

  if has_dir "k8s" || has_dir "kubernetes"; then
    local k8s_files
    k8s_files=$(find "$PROJECT_ROOT/k8s" "$PROJECT_ROOT/kubernetes" -maxdepth 3 -name "*.yaml" -o -name "*.yml" 2>/dev/null | head -1)
    if [ -n "$k8s_files" ]; then
      add_unique INFRASTRUCTURE "kubernetes"
    fi
  fi

  if has_dir "helm" || has_file "Chart.yaml"; then
    add_unique INFRASTRUCTURE "helm"
  fi

  if has_file "terraform/main.tf" || has_dir "terraform"; then
    add_unique INFRASTRUCTURE "terraform"
  fi
}

# =============================================================================
# Detection: CI/CD
# =============================================================================

detect_cicd() {
  if has_dir ".github/workflows"; then
    local workflow_files
    workflow_files=$(find "$PROJECT_ROOT/.github/workflows" -maxdepth 2 -name "*.yml" -o -name "*.yaml" 2>/dev/null | head -1)
    if [ -n "$workflow_files" ]; then
      add_unique CI_CD "github-actions"
    fi
  fi

  if has_file "Jenkinsfile"; then
    add_unique CI_CD "jenkins"
  fi

  if has_file ".gitlab-ci.yml"; then
    add_unique CI_CD "gitlab-ci"
  fi

  if has_file ".circleci/config.yml"; then
    add_unique CI_CD "circleci"
  fi
}

# =============================================================================
# Detection: Game Engines
# =============================================================================

detect_game_engines() {
  if has_file "ProjectSettings/ProjectSettings.asset"; then
    add_unique FRAMEWORKS "unity"
    add_unique LANGUAGES "csharp"
    PLATFORM="game"
  fi

  local uproject
  uproject=$(find "$PROJECT_ROOT" -maxdepth 1 -name "*.uproject" 2>/dev/null | head -1)
  if [ -n "$uproject" ]; then
    add_unique FRAMEWORKS "unreal"
    add_unique LANGUAGES "cpp"
    PLATFORM="game"
  fi

  if has_file "project.godot"; then
    add_unique FRAMEWORKS "godot"
    PLATFORM="game"
  fi
}

# =============================================================================
# Detection: C/C++, C#/.NET
# =============================================================================

detect_native() {
  if has_file "CMakeLists.txt"; then
    add_unique LANGUAGES "cpp"
    add_unique BUILD_TOOLS "cmake"
  fi

  local csproj
  csproj=$(find "$PROJECT_ROOT" -maxdepth 2 -name "*.csproj" -o -name "*.sln" 2>/dev/null | head -1)
  if [ -n "$csproj" ]; then
    add_unique LANGUAGES "csharp"
    add_unique FRAMEWORKS "dotnet"
  fi
}

# =============================================================================
# Detection: TypeScript
# =============================================================================

detect_typescript() {
  if has_file "tsconfig.json"; then
    add_unique LANGUAGES "typescript"
  fi
}

# =============================================================================
# Detection: Flutter
# =============================================================================

detect_flutter() {
  if has_file "pubspec.yaml"; then
    if file_contains "pubspec.yaml" "flutter"; then
      add_unique FRAMEWORKS "flutter"
      add_unique LANGUAGES "dart"
    fi
  fi
}

# =============================================================================
# Run All Detectors
# =============================================================================

detect_java_maven
detect_java_gradle
detect_nodejs
detect_python
detect_go
detect_rust
detect_ios
detect_android
detect_infrastructure
detect_cicd
detect_game_engines
detect_native
detect_typescript
detect_flutter

# =============================================================================
# Platform Detection Logic
# =============================================================================

if [ -z "$PLATFORM" ]; then
  _has_mobile=false
  _has_frontend=false
  _has_backend=false

  for fw in "${FRAMEWORKS[@]+"${FRAMEWORKS[@]}"}"; do
    case "$fw" in
      ios|android|react-native|flutter) _has_mobile=true ;;
      react|vue|angular|svelte|nextjs) _has_frontend=true ;;
      express|fastify|nestjs|springboot|django|fastapi|flask) _has_backend=true ;;
    esac
  done

  if [ "$_has_mobile" = true ]; then
    PLATFORM="client-mobile"
  elif [ "$_has_frontend" = true ] && [ "$_has_backend" = true ]; then
    PLATFORM="fullstack"
  elif [ "$_has_frontend" = true ]; then
    PLATFORM="client-web"
  elif [ "$_has_backend" = true ]; then
    PLATFORM="server"
  else
    PLATFORM="unknown"
  fi
fi

# =============================================================================
# Build All Technologies List
# =============================================================================

ALL_TECHNOLOGIES=()
for item in "${LANGUAGES[@]+"${LANGUAGES[@]}"}"; do add_unique ALL_TECHNOLOGIES "$item"; done
for item in "${FRAMEWORKS[@]+"${FRAMEWORKS[@]}"}"; do add_unique ALL_TECHNOLOGIES "$item"; done
for item in "${DATABASES[@]+"${DATABASES[@]}"}"; do add_unique ALL_TECHNOLOGIES "$item"; done
for item in "${INFRASTRUCTURE[@]+"${INFRASTRUCTURE[@]}"}"; do add_unique ALL_TECHNOLOGIES "$item"; done
for item in "${BUILD_TOOLS[@]+"${BUILD_TOOLS[@]}"}"; do add_unique ALL_TECHNOLOGIES "$item"; done
for item in "${TESTING[@]+"${TESTING[@]}"}"; do add_unique ALL_TECHNOLOGIES "$item"; done
for item in "${CI_CD[@]+"${CI_CD[@]}"}"; do add_unique ALL_TECHNOLOGIES "$item"; done

# =============================================================================
# Output
# =============================================================================

array_to_json_values() {
  # Accepts values as positional arguments
  if [ $# -eq 0 ]; then
    echo "[]"
    return
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
}

if [ "$OUTPUT_FORMAT" = "text" ]; then
  echo "Project: $PROJECT_ROOT"
  echo "Platform: $PLATFORM"
  echo "Languages: ${LANGUAGES[*]+"${LANGUAGES[*]}"}"
  echo "Frameworks: ${FRAMEWORKS[*]+"${FRAMEWORKS[*]}"}"
  echo "Databases: ${DATABASES[*]+"${DATABASES[*]}"}"
  echo "Infrastructure: ${INFRASTRUCTURE[*]+"${INFRASTRUCTURE[*]}"}"
  echo "Build Tools: ${BUILD_TOOLS[*]+"${BUILD_TOOLS[*]}"}"
  echo "Testing: ${TESTING[*]+"${TESTING[*]}"}"
  echo "CI/CD: ${CI_CD[*]+"${CI_CD[*]}"}"
else
  DETECTED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  jq -n \
    --arg project_root "$PROJECT_ROOT" \
    --arg detected_at "$DETECTED_AT" \
    --arg platform "$PLATFORM" \
    --argjson languages "$(array_to_json_values "${LANGUAGES[@]+"${LANGUAGES[@]}"}")" \
    --argjson frameworks "$(array_to_json_values "${FRAMEWORKS[@]+"${FRAMEWORKS[@]}"}")" \
    --argjson databases "$(array_to_json_values "${DATABASES[@]+"${DATABASES[@]}"}")" \
    --argjson infrastructure "$(array_to_json_values "${INFRASTRUCTURE[@]+"${INFRASTRUCTURE[@]}"}")" \
    --argjson build_tools "$(array_to_json_values "${BUILD_TOOLS[@]+"${BUILD_TOOLS[@]}"}")" \
    --argjson testing "$(array_to_json_values "${TESTING[@]+"${TESTING[@]}"}")" \
    --argjson ci_cd "$(array_to_json_values "${CI_CD[@]+"${CI_CD[@]}"}")" \
    --argjson all_technologies "$(array_to_json_values "${ALL_TECHNOLOGIES[@]+"${ALL_TECHNOLOGIES[@]}"}")" \
    '{
      project_root: $project_root,
      detected_at: $detected_at,
      platform: $platform,
      languages: $languages,
      frameworks: $frameworks,
      databases: $databases,
      infrastructure: $infrastructure,
      build_tools: $build_tools,
      testing: $testing,
      ci_cd: $ci_cd,
      all_technologies: $all_technologies
    }'
fi

exit 0

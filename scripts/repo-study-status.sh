#!/bin/bash
# repo-study-status.sh - 查看 study 项目状态
# 用法: ./scripts/repo-study-status.sh [--json] [--check-remote]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
META_FILE="$PROJECT_DIR/.study-meta.json"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

JSON_MODE=false
CHECK_REMOTE=false

for arg in "$@"; do
  case $arg in
    --json) JSON_MODE=true ;;
    --check-remote) CHECK_REMOTE=true ;;
  esac
done

if [ ! -f "$META_FILE" ]; then
  echo "Error: .study-meta.json not found"
  exit 1
fi

# 读取基本信息
REPO_NAME=$(jq -r '.repo.name' "$META_FILE")
REPO_OWNER=$(jq -r '.repo.owner' "$META_FILE")
LOCAL_SHA=$(jq -r '.repo.commitSha' "$META_FILE")
TOPIC_COUNT=$(jq '.topics | length' "$META_FILE")
MANAGED_BY=$(jq -r '.managedBy.skill // "unknown"' "$META_FILE")

# 远程检查
REMOTE_STATUS="unknown"
REMOTE_SHA=""
if [ "$CHECK_REMOTE" = true ]; then
  REMOTE_SHA=$(gh api "repos/${REPO_OWNER}/${REPO_NAME}/commits/main" --jq '.sha' 2>/dev/null)
  if [ -n "$REMOTE_SHA" ]; then
    if [ "$REMOTE_SHA" = "$LOCAL_SHA" ]; then
      REMOTE_STATUS="up-to-date"
    else
      REMOTE_STATUS="outdated"
    fi
  fi
fi

if [ "$JSON_MODE" = true ]; then
  jq --arg rs "$REMOTE_STATUS" --arg rsha "$REMOTE_SHA" \
    '. + {remoteCheck: {status: $rs, remoteSha: $rsha}}' "$META_FILE"
else
  echo -e "${BLUE}Repo Study Status${NC}"
  echo "Project: $PROJECT_DIR"
  echo "Repo: ${REPO_OWNER}/${REPO_NAME}"
  echo "Managed By: $MANAGED_BY"
  echo "Local Commit: ${LOCAL_SHA:0:8}"

  if [ "$CHECK_REMOTE" = true ]; then
    if [ "$REMOTE_STATUS" = "outdated" ]; then
      echo -e "Remote: ${YELLOW}${REMOTE_STATUS}${NC} (${REMOTE_SHA:0:8})"
    elif [ "$REMOTE_STATUS" = "up-to-date" ]; then
      echo -e "Remote: ${GREEN}${REMOTE_STATUS}${NC}"
    fi
  fi

  echo ""
  echo "Topics: $TOPIC_COUNT"

  if [ "$TOPIC_COUNT" -gt 0 ]; then
    jq -r '.topics[] | "\(.name) [\(.category)] - questions:\(.progress.questionCount) notes:\(.progress.noteCount)"' "$META_FILE"
  fi
fi

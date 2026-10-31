#!/usr/bin/env bash
#
# nexus-upload.sh  (Git Bash / Linux 겸용)
#   fetch-maven-deps.sh 로 받은 repository/ 폴더를 Maven 레이아웃 그대로
#   Nexus 3 maven2 hosted 저장소에 HTTP PUT 으로 업로드합니다.
#
#   - -g 로 group 저장소를 지정하면, 그 group 에 이미 있는 파일은 올리지 않습니다.
#     (개발자가 실제로 받는 곳 기준으로 중복 판단 → 다른 hosted/proxy 에 있는 것도 건너뜀)
#   - maven-metadata.xml, 체크섬(.sha1/.md5 등)은 Nexus 가 만들어 주므로 올리지 않습니다.
#   - hosted 쪽에 이미 있는 파일(400, 재배포 금지 정책)도 건너뜁니다.
#   - 비밀번호는 명령행 인자로 받지 않습니다. (history 노출 방지)
#
# 사용법:
#   ./nexus-upload.sh -u <Nexus주소> -r <hosted저장소> [-g <group저장소>] [-n <스냅샷hosted>] [-k] [-d] [repository_dir]
#
#   -u  Nexus 주소 (예: http://10.0.0.5:8081)
#   -r  업로드할 릴리스용 hosted 저장소 이름 (예: maven-releases)
#   -g  존재 여부를 확인할 group 저장소 이름 (예: maven-public). 생략하면 확인 없이 업로드
#   -n  스냅샷용 hosted 저장소 이름 (없으면 -SNAPSHOT 은 건너뜀)
#   -k  자체 서명 인증서 허용 (curl -k)
#   -d  dry-run: 실제로 올리지 않고 목록만 출력 (-g 가 있으면 존재 여부 확인까지 수행)
#
#   시작 시 -r/-n 은 hosted, -g 는 group 타입인지 Nexus 에 확인하고, 아니면 중단합니다.
#   repository_dir 기본값: ./maven-out/repository
#
# 인증:
#   환경변수 NEXUS_USER / NEXUS_PASSWORD 가 있으면 사용, 없으면 실행 시 입력받습니다.
#
set -uo pipefail

NEXUS_URL=""
REPO_ID=""
GROUP_ID=""
SNAP_REPO=""
INSECURE=false
DRY=false

usage() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

while getopts "u:r:g:n:kdh" opt; do
  case "$opt" in
    u) NEXUS_URL="${OPTARG%/}" ;;
    r) REPO_ID="$OPTARG" ;;
    g) GROUP_ID="$OPTARG" ;;
    n) SNAP_REPO="$OPTARG" ;;
    k) INSECURE=true ;;
    d) DRY=true ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
SRC="${1:-./maven-out/repository}"

[[ -n "$NEXUS_URL" && -n "$REPO_ID" ]] || usage
[[ -d "$SRC" ]] || { echo "[ERROR] 폴더가 없습니다: $SRC" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "[ERROR] curl 이 없습니다." >&2; exit 1; }

# 저장소 타입 확인·조회·업로드 모두 인증이 필요합니다. (dry-run 포함)
if [[ -z "${NEXUS_USER:-}" ]]; then read -r -p "Nexus 계정: " NEXUS_USER; fi
if [[ -z "${NEXUS_PASSWORD:-}" ]]; then read -r -s -p "Nexus 비밀번호: " NEXUS_PASSWORD; echo; fi

# 인증 정보는 권한 600 임시 설정 파일로 curl 에 넘깁니다. (인자/history 노출 방지)
# stdin 을 쓰지 않으므로 Git Bash 에서 루프 입력이 소진되는 문제가 없습니다.
esc() { local s="${1//\\/\\\\}"; printf '%s' "${s//\"/\\\"}"; }
CFG="$(mktemp)"
trap 'rm -f "$CFG"' EXIT
chmod 600 "$CFG"
if [[ -n "${NEXUS_USER:-}" ]]; then
  printf 'user = "%s:%s"\n' "$(esc "$NEXUS_USER")" "$(esc "${NEXUS_PASSWORD:-}")" > "$CFG"
fi
CURL_BASE=(-K "$CFG" -sS -o /dev/null -w '%{http_code}' --connect-timeout 10)
$INSECURE && CURL_BASE+=(-k)

# group 저장소에 파일이 있는지 확인 → HTTP 코드 출력
check_group() {
  curl "${CURL_BASE[@]}" --max-time 60 --head "$NEXUS_URL/repository/$GROUP_ID/$1" < /dev/null || echo "000"
}

# ---- 저장소 타입 검증 ----
#   -r / -n 은 hosted, -g 는 group 이어야 합니다.
#   group 에 PUT 하면 Nexus 가 거부하는데, 그 응답이 "이미 존재"로 오인될 수 있어 미리 막습니다.
REPO_JSON="$(mktemp)"
trap 'rm -f "$CFG" "$REPO_JSON"' EXIT
code=$(curl -K "$CFG" -sS -o "$REPO_JSON" -w '%{http_code}' --connect-timeout 10 --max-time 30 \
         $($INSECURE && echo -k) "$NEXUS_URL/service/rest/v1/repositories" < /dev/null) || code="000"
case "$code" in
  200) : ;;
  401|403) echo "[FATAL] $code — 저장소 목록 조회 인증/권한 오류입니다. 계정을 확인하세요." >&2; exit 1 ;;
  000)     echo "[FATAL] Nexus 에 접속할 수 없습니다: $NEXUS_URL" >&2; exit 1 ;;
  *)       echo "[FATAL] $code — 저장소 목록을 가져오지 못했습니다. Nexus 주소(-u)를 확인하세요." >&2; exit 1 ;;
esac

# JSON 을 "이름 타입 포맷" 줄로 변환 (jq 없이 처리)
REPO_LIST=$(tr -d '\r\n' < "$REPO_JSON" | { sed 's/"name"[[:space:]]*:/\n&/g'; echo; } | while IFS= read -r line; do
  n=$(printf '%s' "$line" | sed -n 's/^"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [[ -z "$n" ]] && continue
  t=$(printf '%s' "$line" | sed -n 's/.*"type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  f=$(printf '%s' "$line" | sed -n 's/.*"format"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  echo "$n $t $f"
done)

repo_type() { awk -v n="$1" '$1==n {print $2; exit}' <<< "$REPO_LIST"; }
repo_fmt()  { awk -v n="$1" '$1==n {print $3; exit}' <<< "$REPO_LIST"; }

require_type() {  # $1=저장소 이름, $2=필요 타입, $3=옵션
  local t f
  t=$(repo_type "$1"); f=$(repo_fmt "$1")
  if [[ -z "$t" ]]; then
    echo "[FATAL] $3 $1 — 저장소가 없거나 이 계정으로 볼 수 없습니다." >&2
    echo "        사용 가능한 저장소:" >&2
    awk '{printf "          %-30s %-7s %s\n", $1, $2, $3}' <<< "$REPO_LIST" >&2
    exit 1
  fi
  if [[ "$t" != "$2" ]]; then
    echo "[FATAL] $3 $1 은(는) $t 타입입니다. $2 타입 저장소를 지정하세요." >&2
    echo "        $2 타입 저장소:" >&2
    awk -v w="$2" '$2==w {printf "          %-30s %s\n", $1, $3}' <<< "$REPO_LIST" >&2
    exit 1
  fi
  if [[ "$f" != "maven2" ]]; then
    echo "[FATAL] $3 $1 은(는) $f 포맷입니다. maven2 저장소를 지정하세요." >&2; exit 1
  fi
}

require_type "$REPO_ID" hosted "-r"
[[ -n "$SNAP_REPO" ]] && require_type "$SNAP_REPO" hosted "-n"
[[ -n "$GROUP_ID"  ]] && require_type "$GROUP_ID"  group  "-g"
echo "[INFO] 저장소 확인 완료: -r $REPO_ID(hosted)${GROUP_ID:+, -g $GROUP_ID(group)}${SNAP_REPO:+, -n $SNAP_REPO(hosted)}"

cd "$SRC"
LOG_FAIL="$(pwd)/../upload-failed.txt"
: > "$LOG_FAIL"

# 업로드 대상 목록을 먼저 배열로 모읍니다.
mapfile -t FILES < <(find . -type f \
           ! -name 'maven-metadata*.xml' ! -name '_remote.repositories' \
           ! -name '*.lastUpdated' ! -name 'resolver-status.properties' \
           ! -name '*.sha1' ! -name '*.md5' ! -name '*.sha256' ! -name '*.sha512' ! -name '*.asc' \
         | sed 's|^\./||' | sort)

total=${#FILES[@]}
echo "[INFO] 업로드 대상 ${total}개 (pom $(printf '%s\n' "${FILES[@]}" | grep -c '\.pom$')개 포함)"
if [[ -n "$GROUP_ID" ]]; then
  echo "[INFO] 존재 확인: $GROUP_ID (group)  →  업로드: $REPO_ID (hosted)"
fi
[[ $total -gt 0 ]] || { echo "[ERROR] 올릴 파일이 없습니다: $SRC" >&2; exit 1; }

ok=0; skip=0; gskip=0; fail=0; snap_skip=0; i=0

for rel in "${FILES[@]}"; do
  i=$((i + 1))
  if [[ "$rel" == *-SNAPSHOT/* ]]; then
    if [[ -z "$SNAP_REPO" ]]; then snap_skip=$((snap_skip + 1)); continue; fi
    target="$SNAP_REPO"
  else
    target="$REPO_ID"
  fi

  # 1) group 저장소에 이미 있으면 건너뜀
  if [[ -n "$GROUP_ID" ]]; then
    hcode=$(check_group "$rel")
    case "$hcode" in
      200)     gskip=$((gskip + 1)); echo "[HAVE] ($i/$total) $rel (group 에 이미 있음)"; continue ;;
      404)     : ;;  # 없음 → 업로드 진행
      401|403) echo "[FATAL] $hcode — group($GROUP_ID) 읽기 권한이 없습니다." >&2; exit 1 ;;
      *)       echo "[WARN] ($i/$total) group 확인 실패($hcode), 업로드를 시도합니다: $rel" ;;
    esac
  fi

  url="$NEXUS_URL/repository/$target/$rel"
  if $DRY; then echo "[DRY]  ($i/$total) $url"; continue; fi

  # 2) hosted 저장소에 업로드
  code=$(curl "${CURL_BASE[@]}" --retry 2 --upload-file "$rel" "$url" < /dev/null) || code="000"

  case "$code" in
    200|201|204) ok=$((ok + 1)); echo "[OK]   ($i/$total) $rel" ;;
    400)         skip=$((skip + 1)); echo "[SKIP] ($i/$total) $rel (hosted 에 이미 존재)" ;;
    401|403)     echo "[FATAL] $code 인증/권한 오류 — 계정과 저장소 쓰기 권한을 확인하세요." >&2; exit 1 ;;
    404)         echo "[FATAL] 404 — 저장소 이름($target) 또는 URL 을 확인하세요." >&2; exit 1 ;;
    *)           fail=$((fail + 1)); echo "[FAIL] ($i/$total) $code $rel"; echo "$code $rel" >> "$LOG_FAIL" ;;
  esac
done

echo
if $DRY; then
  echo "[DRY-RUN] 대상 $total / group 에 이미 있음 $gskip / 올릴 예정 $((total - gskip - snap_skip)) / 스냅샷 건너뜀 $snap_skip"
  exit 0
fi
echo "[DONE] 성공 $ok / group 에 이미 있음 $gskip / hosted 에 이미 존재 $skip / 실패 $fail / 스냅샷 건너뜀 $snap_skip"
[[ $fail -gt 0 ]] && echo "  실패 목록: $LOG_FAIL"
exit $(( fail > 0 ? 1 : 0 ))

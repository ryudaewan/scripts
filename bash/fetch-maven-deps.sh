#!/usr/bin/env bash
#
# fetch-maven-deps.sh  (Git Bash / Linux 겸용)
#   지정한 Maven 아티팩트와 전이 의존성을 모두 내려받습니다.
#
#   결과물:
#     <out>/lib/          jar 평면 모음 (클래스패스용)
#     <out>/repository/   Maven 레이아웃 로컬 저장소 (parent pom, BOM 포함 → Nexus 업로드용)
#     <out>/dependency-tree.txt
#
# 사용법:
#   ./fetch-maven-deps.sh [-o 출력폴더] [-s] [-j] [-S settings.xml] [-x scope] [-z] 좌표...
#   좌표 형식: groupId:artifactId:version[:type[:classifier]]
#
#   -o  출력 폴더 (기본: ./maven-out)
#   -s  소스 jar 도 받기
#   -j  javadoc jar 도 받기
#   -S  settings.xml 지정 (사내 프록시/미러용)
#   -x  scope (기본: runtime = compile + runtime)
#   -z  완료 후 tar.gz 로 압축
#
set -euo pipefail

OUT_DIR="./maven-out"
WITH_SOURCES=false
WITH_JAVADOC=false
SETTINGS=""
SCOPE="runtime"
MAKE_TAR=false
MVN="${MVN:-mvn}"
PLUGIN="org.apache.maven.plugins:maven-dependency-plugin:3.8.1"

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

while getopts "o:sjS:x:zh" opt; do
  case "$opt" in
    o) OUT_DIR="$OPTARG" ;;
    s) WITH_SOURCES=true ;;
    j) WITH_JAVADOC=true ;;
    S) SETTINGS="$OPTARG" ;;
    x) SCOPE="$OPTARG" ;;
    z) MAKE_TAR=true ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -ge 1 ]] || usage

command -v "$MVN" >/dev/null 2>&1 || { echo "[ERROR] mvn 을 찾을 수 없습니다. PATH 를 확인하세요." >&2; exit 1; }
if [[ -n "$SETTINGS" && ! -f "$SETTINGS" ]]; then
  echo "[ERROR] settings 파일이 없습니다: $SETTINGS" >&2; exit 1
fi

# Git Bash 의 /c/... 경로는 Java(Maven)가 이해하지 못하므로 C:/... 형태로 변환합니다.
winpath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
REPO="$OUT_DIR/repository"
LIB="$OUT_DIR/lib"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---- 좌표 → 임시 pom 의 <dependency> ----
deps=""
for coord in "$@"; do
  IFS=':' read -r g a v t c <<< "$coord"
  if [[ -z "${g:-}" || -z "${a:-}" || -z "${v:-}" ]]; then
    echo "[ERROR] 잘못된 좌표: $coord  (형식: groupId:artifactId:version[:type[:classifier]])" >&2
    exit 1
  fi
  deps+="    <dependency>
      <groupId>$g</groupId>
      <artifactId>$a</artifactId>
      <version>$v</version>
      <type>${t:-jar}</type>"
  [[ -n "${c:-}" ]] && deps+="
      <classifier>$c</classifier>"
  deps+="
    </dependency>
"
  echo "[INFO] 대상: $coord"
done

cat > "$WORK/pom.xml" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>local.fetch</groupId>
  <artifactId>fetch-deps</artifactId>
  <version>1</version>
  <packaging>pom</packaging>
  <dependencies>
$deps  </dependencies>
</project>
EOF

MVN_ARGS=(-B -ntp -f "$(winpath "$WORK/pom.xml")" "-Dmaven.repo.local=$(winpath "$REPO")")
[[ -n "$SETTINGS" ]] && MVN_ARGS+=(-s "$(winpath "$(cd "$(dirname "$SETTINGS")" && pwd)/$(basename "$SETTINGS")")")

# ---- 1) jar 복사 + 저장소 채우기 ----
echo "[INFO] 의존성 다운로드 중... (scope=$SCOPE)"
"$MVN" "${MVN_ARGS[@]}" "$PLUGIN:copy-dependencies" \
  "-DoutputDirectory=$(winpath "$LIB")" \
  "-DincludeScope=$SCOPE"

# ---- 2) 소스 jar (선택) ----
if $WITH_SOURCES; then
  echo "[INFO] 소스 jar 다운로드 중..."
  "$MVN" "${MVN_ARGS[@]}" "$PLUGIN:copy-dependencies" \
    "-DoutputDirectory=$(winpath "$OUT_DIR/sources")" \
    "-DincludeScope=$SCOPE" \
    -Dclassifier=sources \
    -Dmdep.failOnMissingClassifierArtifact=false
fi

# ---- 2-1) javadoc jar (선택) ----
if $WITH_JAVADOC; then
  echo "[INFO] javadoc jar 다운로드 중..."
  "$MVN" "${MVN_ARGS[@]}" "$PLUGIN:copy-dependencies" \
    "-DoutputDirectory=$(winpath "$OUT_DIR/javadoc")" \
    "-DincludeScope=$SCOPE" \
    -Dclassifier=javadoc \
    -Dmdep.failOnMissingClassifierArtifact=false
fi

# ---- 3) 의존성 트리 ----
"$MVN" "${MVN_ARGS[@]}" -q "$PLUGIN:tree" \
  "-DoutputFile=$(winpath "$OUT_DIR/dependency-tree.txt")" \
  "-Dscope=$SCOPE" || echo "[WARN] 의존성 트리 생성 실패 (다운로드에는 영향 없음)"

# ---- 4) 폐쇄망 재사용을 위한 메타파일 정리 ----
find "$REPO" \( -name '_remote.repositories' -o -name '*.lastUpdated' -o -name 'resolver-status.properties' \) \
  -type f -delete 2>/dev/null || true

# ---- 5) 압축 (선택) ----
if $MAKE_TAR; then
  tar -czf "$OUT_DIR.tar.gz" -C "$(dirname "$OUT_DIR")" "$(basename "$OUT_DIR")"
  echo "[INFO] 압축 완료: $OUT_DIR.tar.gz"
fi

count_jars() { find "$1" -name '*.jar' 2>/dev/null | wc -l | tr -d ' '; }

echo
echo "[DONE] jar $(count_jars "$LIB")개"
echo "  lib        : $LIB"
if $WITH_SOURCES; then
  echo "  sources    : $OUT_DIR/sources  ($(count_jars "$OUT_DIR/sources")개)"
fi
if $WITH_JAVADOC; then
  echo "  javadoc    : $OUT_DIR/javadoc  ($(count_jars "$OUT_DIR/javadoc")개)"
fi
echo "  repository : $REPO"
echo "  tree       : $OUT_DIR/dependency-tree.txt"
echo "  * 소스/javadoc 개수가 본체보다 적은 것은 해당 라이브러리가 배포하지 않았기 때문입니다."
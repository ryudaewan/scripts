#!/bin/ash

# 첫 번째 인자가 있는지 확인
if [ -z "$1" ]; then
  echo "내려받을 apk 파일명을 첫 번째 인자를 주셔야 합니다."
  exit -1
fi

# 다운로드를 저장할 디렉토리 설정
XXX=$1
DOWNLOAD_DIR="./packages"

if [ ! -d "$DOWNLOAD_DIR" ]; then  
  mkdir -p "$DOWNLOAD_DIR"
fi

# 첫번째 인자로 지정한 apk 파일 자체는 내려받는다.
apk fetch --no-cache --output "$DOWNLOAD_DIR" $XXX > /dev/null

# gcompat 및 모든 의존성 패키지 다운로드 (재귀적으로 모든 의존성 포함)
#apk fetch --no-cache --output "$DOWNLOAD_DIR" gcompat --recursive --simulate | grep -Eo '([a-zA-Z0-9\.\-\_]+\.apk)' | xargs -I {} apk fetch --no-cache --output "$DOWNLOAD_DIR" {}
apk fetch --no-cache $XXX --recursive --simulate | grep Downloading | grep -v $XXX | cut -d' ' -f2 | sed 's/-[0-9].*//' > ___tempX8546____
cat ___tempX8546____ | grep -Ev '^musl$' > ${XXX}.dep # 알파인 리눅스에 musl은 기본 탑재이므로 의존하는 라이브러리 목록에서 뺀다.
rm -f ___tempX8546____

CNT=$(wc -l < ${XXX}.dep)

if [ "$CNT" -lt 1 ]; then
  exit 0
fi

while read inx; do
    echo $inx
    ./dep.sh $inx
done < ${XXX}.dep

# 내려받은 apk 파일들은 아래의 명령어로 설치한다.
# apk add --repository $(pwd) --allow-untrusted ./*.apk

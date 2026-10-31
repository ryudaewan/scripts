# Maven 라이브러리 반입 스크립트 사용법

인터넷이 되는 PC에서 Maven 라이브러리를 전이 의존성까지 모두 내려받고, 폐쇄망의 사내 Nexus 3에 업로드하는 스크립트 두 개의 사용법입니다.

| 스크립트 | 역할 | 실행 위치 |
|---|---|---|
| `fetch-maven-deps.sh` | 라이브러리 + 전이 의존성 + parent pom/BOM 다운로드 | 인터넷 PC |
| `nexus-upload.sh` | 받은 `repository/` 폴더를 Nexus hosted 저장소에 업로드 | 폐쇄망 PC |

---

## 1. 준비 사항

- **Git Bash** (Linux bash에서도 동작합니다)
- **다운로드 PC**: Maven(`mvn`)이 PATH에 있어야 합니다. `mvn -v`로 확인하세요.
- **업로드 PC**: `curl`만 있으면 됩니다 (Git Bash에 기본 포함). Maven은 필요 없습니다.
- 처음 한 번 실행 권한을 줍니다.

```bash
chmod +x fetch-maven-deps.sh nexus-upload.sh
```

---

## 2. 전체 흐름

```
[인터넷 PC]                          [폐쇄망 PC]
fetch-maven-deps.sh                  nexus-upload.sh
  → out/repository/  ── 반입 ──→      → 사내 Nexus (maven-releases)
  → out/dependency-tree.txt (심사용)
```

1. 인터넷 PC에서 `fetch-maven-deps.sh`로 다운로드
2. `out/repository/` 폴더(+ `dependency-tree.txt`)를 압축해 반입
3. 폐쇄망 PC에서 `nexus-upload.sh`로 dry-run 확인 후 업로드
4. 개발 PC에서 Maven Update Project로 정상 수신 확인

---

## 3. fetch-maven-deps.sh (다운로드)

### 사용법

```bash
./fetch-maven-deps.sh [-o 출력폴더] [-s] [-j] [-S settings.xml] [-x scope] [-z] 좌표...
```

### 옵션

| 옵션 | 설명 | 기본값 |
|---|---|---|
| `-o` | 출력 폴더 | `./maven-out` |
| `-s` | 소스 jar도 받기 | 받지 않음 |
| `-j` | javadoc jar도 받기 (**소문자** j) | 받지 않음 |
| `-S` | 별도 settings.xml 지정 | `~/.m2/settings.xml` 자동 사용 |
| `-x` | 의존성 scope | `runtime` (compile + runtime) |
| `-z` | 완료 후 `출력폴더.tar.gz`로 압축 | 압축 안 함 |

### 좌표 형식

```
groupId:artifactId:version[:type[:classifier]]
```

- 예: `org.jasypt:jasypt-spring31:1.9.3`
- BOM처럼 pom 타입이면 `...:버전:pom`
- 좌표는 [search.maven.org](https://search.maven.org) 또는 [mvnrepository.com](https://mvnrepository.com)의 Maven 탭에서 `groupId`, `artifactId`, `version`을 `:`로 이어 붙이면 됩니다.

### 실행 예

```bash
# 기본
./fetch-maven-deps.sh -o ./out org.springdoc:springdoc-openapi-starter-webmvc-ui:2.8.13

# 여러 개 + 소스 + javadoc
./fetch-maven-deps.sh -o ./out -s -j \
  org.springdoc:springdoc-openapi-starter-webmvc-ui:2.8.13 \
  org.jasypt:jasypt-spring31:1.9.3

# 평소와 다른 settings.xml(프록시 등)을 써야 할 때
./fetch-maven-deps.sh -o ./out -S ~/.m2/settings-proxy.xml org.apache.poi:poi-ooxml:5.3.0
```

> 다시 받을 때는 `rm -rf ./out`으로 이전 결과를 지우고 시작하는 것이 깔끔합니다.

### 결과물

| 경로 | 내용 | 반입 필요 |
|---|---|---|
| `out/repository/` | Maven 레이아웃 저장소. jar, pom, **parent pom, BOM**, 소스/javadoc 포함 | **필수** (Nexus 업로드 대상) |
| `out/dependency-tree.txt` | 의존성 트리 | 권장 (반입 심사용) |
| `out/lib/` | 본체 jar 평면 복사본 | Nexus 없이 클래스패스에 직접 넣을 때만 |
| `out/sources/` | 소스 jar 평면 복사본 (`-s`) | 불필요 (repository에 포함됨) |
| `out/javadoc/` | javadoc jar 평면 복사본 (`-j`) | 불필요 (repository에 포함됨) |

완료 시 출력 예:

```
[DONE] jar 47개
  lib        : .../out/lib
  sources    : .../out/sources  (45개)
  javadoc    : .../out/javadoc  (43개)
  repository : .../out/repository
  tree       : .../out/dependency-tree.txt
```

소스/javadoc 개수가 본체보다 적은 것은 해당 라이브러리가 배포하지 않았기 때문이며 정상입니다.

### 참고: parent pom을 꼭 반입해야 하는 이유

라이브러리 pom은 `<parent>`로 상위 pom을 상속하고, 하위 의존성 버전이 상위 pom에 적혀 있는 경우가 많습니다. jar만 반입하면 다음 오류가 납니다.

```
Could not find artifact com.fasterxml.jackson:jackson-base:pom:2.17.2
```

`repository/`에는 parent pom과 BOM이 모두 들어 있으므로, **`lib/`가 아니라 `repository/`를 반입·업로드**하면 됩니다.

---

## 4. nexus-upload.sh (업로드)

### 사용법

```bash
./nexus-upload.sh -u <Nexus주소> -r <hosted저장소> [-g <group저장소>] [-n <스냅샷저장소>] [-k] [-d] [repository_dir]
```

### 옵션

| 옵션 | 설명 |
|---|---|
| `-u` | Nexus 주소 (예: `http://10.0.0.5:8081`) — 필수 |
| `-r` | 릴리스용 **hosted** 저장소 이름 (예: `maven-releases`) — 필수 |
| `-g` | 존재 여부를 확인할 **group** 저장소 (예: `maven-public`). 여기 이미 있는 파일은 올리지 않음. 생략하면 확인 없이 업로드 |
| `-n` | 스냅샷용 hosted 저장소. 지정하지 않으면 `-SNAPSHOT`은 건너뜀 |
| `-k` | 자체 서명 인증서 허용 (HTTPS일 때) |
| `-d` | dry-run: 올릴 URL 목록만 출력 (`-g`가 있으면 group 존재 확인까지 수행) |
| `repository_dir` | 업로드할 폴더. 기본값 `./maven-out/repository` |

> `-o ./out`으로 받았다면 경로를 **반드시** `./out/repository`로 지정하세요.

### 인증

- 환경변수 `NEXUS_USER`, `NEXUS_PASSWORD`가 있으면 사용하고, 없으면 실행 시 입력받습니다.
- 비밀번호는 curl 인자가 아니라 stdin으로 넘기므로 명령 이력에 남지 않습니다.

```bash
# 반복 실행 시
export NEXUS_USER=계정
read -s NEXUS_PASSWORD && export NEXUS_PASSWORD
```

### 실행 예

```bash
# 1) 먼저 dry-run으로 대상 확인 (group에 이미 있는 것은 [HAVE]로 표시)
./nexus-upload.sh -u http://<넥서스주소>:8081 -r maven-releases -g maven-public -d ./out/repository

# 2) 실제 업로드 (maven-public에 없는 것만 maven-releases에 올림)
./nexus-upload.sh -u http://<넥서스주소>:8081 -r maven-releases -g maven-public ./out/repository
```

### 동작 방식

- `-g`를 주면 파일마다 group 저장소에 HEAD 요청을 보내 존재 여부를 확인합니다. 개발자가 실제로 받는 곳 기준이라, 다른 hosted나 proxy 캐시에 이미 있는 것도 중복으로 올리지 않습니다.
- Nexus REST API가 아니라 **Maven 저장소 경로에 HTTP PUT**으로 파일을 올립니다. `mvn deploy`가 내부적으로 하는 것과 같은 방식입니다.
- `maven-metadata.xml`, 체크섬(`.sha1`, `.md5` 등), `_remote.repositories`, `*.lastUpdated`는 올리지 않습니다. 메타데이터와 체크섬은 Nexus가 자동 생성합니다.

### 응답 코드

| 코드 | 의미 | 처리 |
|---|---|---|
| (group HEAD) `200` | group에 이미 있음 | `[HAVE]` — 업로드 안 함 |
| `200` / `201` / `204` | 업로드 성공 | `[OK]` |
| `400` | 이미 같은 버전이 있음 (재배포 금지 정책) | `[SKIP]` — 무시해도 됨 |
| `401` / `403` | 인증 실패 또는 쓰기 권한 없음 | 즉시 중단 |
| `404` | 저장소 이름 또는 URL 오류 | 즉시 중단 |
| 그 외 | 기타 실패 | `upload-failed.txt`에 기록 |

### 저장소 타입 자동 검증

시작할 때 Nexus에 저장소 목록을 조회해서 다음을 확인하고, 맞지 않으면 바로 중단합니다.

- `-r`, `-n`: **hosted** 타입 + maven2 포맷이어야 함 (group에는 업로드할 수 없음)
- `-g`: **group** 타입 + maven2 포맷이어야 함
- 저장소 이름 오타면 사용 가능한 저장소 목록을 보여 줌

이 때문에 dry-run(`-d`)에서도 계정을 입력받습니다.

### Nexus 쪽 확인 사항

- 대상 저장소는 **proxy가 아닌 hosted** 타입이어야 합니다.
- 계정에 해당 저장소 add/edit 권한이 있어야 합니다.
- 그 hosted 저장소가 팀이 쓰는 `maven-public` 같은 group 저장소에 포함돼 있어야 개발 PC에서 받을 수 있습니다.

### 업로드 후 확인

1. Nexus 웹 화면 Browse에서 해당 경로 아래 jar, pom, sources, javadoc이 있는지 확인
2. 개발 PC에서 로컬 `.m2`의 해당 groupId 폴더를 지우고 Maven Update Project → Nexus에서 정상으로 받아지는지 확인

---

## 5. settings.xml과 `-S` 옵션

회사 PC가 Maven Central에 직접 접속하지 못하면, Maven은 `~/.m2/settings.xml`의 프록시나 미러 설정을 통해 받습니다. 이 파일은 **자동으로 읽히므로** 평소 빌드가 잘 되는 PC라면 `-S`가 필요 없습니다.

`-S`는 평소와 **다른** settings.xml을 써야 할 때만 지정합니다. 예시:

```xml
<settings>
  <!-- HTTP 프록시를 거쳐야 하는 경우 -->
  <proxies>
    <proxy>
      <id>corp</id>
      <active>true</active>
      <protocol>http</protocol>
      <host>proxy.회사.com</host>
      <port>8080</port>
      <nonProxyHosts>localhost|*.회사.com</nonProxyHosts>
    </proxy>
  </proxies>

  <!-- 사내 Nexus 미러를 통해서만 받아야 하는 경우 -->
  <mirrors>
    <mirror>
      <id>nexus</id>
      <mirrorOf>*</mirrorOf>
      <url>http://<넥서스주소>:8081/repository/maven-public/</url>
    </mirror>
  </mirrors>
</settings>
```

---

## 6. 문제 해결

| 증상 | 원인 / 해결 |
|---|---|
| `$'\r': command not found` | 메모장 등에서 편집해 줄바꿈이 CRLF로 바뀜 → `sed -i 's/\r$//' *.sh` |
| `Permission denied` | 실행 권한 없음 → `chmod +x *.sh` |
| `The POM for ... is missing, no dependency information available` | 좌표 오타가 대부분 (예: `com.fasterxml.org.jasypt` → `org.jasypt`). search.maven.org에서 좌표 확인 |
| 실행하자마자 사용법만 출력됨 | 알 수 없는 옵션 (예: 대문자 `-J`). 옵션은 대소문자를 구분합니다 |
| `mvn 을 찾을 수 없습니다` | Maven이 PATH에 없음 → `mvn -v`로 확인 |
| 폐쇄망 빌드 시 `Could not find artifact ...:pom` | parent pom/BOM 누락 → `lib/`가 아니라 `repository/`를 업로드했는지 확인 |
| 업로드 시 `404` | 저장소 이름 오타, 또는 Nexus 2 사용 (Nexus 2는 경로 체계가 다름) |
| 업로드 시 `401`/`403` | 계정·비밀번호 또는 hosted 저장소 쓰기 권한 확인 |
| `-SNAPSHOT`이 올라가지 않음 | `-n maven-snapshots`로 스냅샷 저장소를 지정해야 함 |

### Git Bash 관련 참고

- Git Bash의 `/c/Users/...` 경로는 Java가 인식하지 못하므로, 스크립트가 내부에서 `cygpath -m`으로 `C:/Users/...` 형태로 변환해 Maven에 넘깁니다. 별도로 신경 쓰실 필요는 없습니다.
- 완료 메시지에 `/c/Users/...` 형태로 표시되는 것은 정상입니다.

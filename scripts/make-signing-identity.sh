#!/usr/bin/env bash
# 로컬 전용 self-signed 코드 서명 ID "ClaudeCats Self-Signed" 를 로그인 키체인에 만든다.
#
# 왜 필요한가 — 이 앱은 지금까지 ad-hoc 서명(`codesign --sign -`)만 했다. ad-hoc 은
# 빌드할 때마다 코드 서명 해시(cdhash)가 바뀌고, macOS 의 파일 접근 권한(TCC)은 그
# 해시(정확히는 "지정 요구사항", designated requirement)에 묶여 있다. 그래서 앱이
# 스스로 다시 빌드해 갈아끼울 때마다(scripts/install.sh --self-update) 예전에 받아 둔
# ~/Documents 저장소 접근 권한이 새 번들과 안 맞아 풀리고, 업데이트 확인이 막힌다.
#
# 안정적인 self-signed ID 로 서명하면 인증서(leaf)가 그대로인 한 지정 요구사항이
# 빌드마다 **동일**하므로, 한 번 허용한 파일 접근 권한이 이후 업데이트에도 유지된다.
#
# 이건 **로컬 전용**이다. 애플 계정도, 배포용도 아니다 — 남에게 .app 을 건네려면
# 여전히 Developer ID + 공증(notarization)이 필요하다(범위 밖). 이 ID 는 그저 이
# 맥에서 codesign 이 쓸 수 있는, 매번 같은 인증서일 뿐이다.
#
# 한 번만 실행하면 된다. bundle.sh 는 이 스크립트를 부르지 않는다 — ID 가 있으면
# 그걸로 서명하고, 없으면 ad-hoc 으로 물러설 뿐이다.
#
# 사용법: ./scripts/make-signing-identity.sh
#
# 환경 변수(테스트·고급 용):
#   CLAUDE_CATS_SIGNING_KEYCHAIN  ID 를 넣을 키체인(기본 login.keychain-db).
#   CLAUDE_CATS_KEYCHAIN_PW       위 키체인의 잠금 해제 암호(기본 빈 문자열).
#                                 로그인 키체인은 보통 로그인 암호라 빈 값이면 마지막
#                                 set-key-partition-list 단계가 실패한다(아래 안내 참고).
set -euo pipefail

IDENTITY_NAME="ClaudeCats Self-Signed"
KEYCHAIN="${CLAUDE_CATS_SIGNING_KEYCHAIN:-login.keychain-db}"
KEYCHAIN_PW="${CLAUDE_CATS_KEYCHAIN_PW:-}"
# .p12 를 감싸는 임시 암호. import 하고 곧바로 지우므로 고정값이어도 무방하다.
# 빈 암호는 OpenSSL 3 이 만든 .p12 의 MAC 을 macOS security 가 못 읽어(=import 실패)
# 쓸 수 없다 — 그래서 고정 암호를 쓴다.
P12_PW="claudecats-local"

# 이미 있으면 그대로 두고 나간다(idempotent). SHA-1 을 뽑아 보여 준다.
# `-v`(valid only)를 **쓰지 않는다** — self-signed 인증서는 신뢰 앵커가 아니라
# CSSMERR_TP_NOT_TRUSTED 로 "invalid" 취급돼 `-v` 목록에서 빠진다. 하지만 codesign 은
# 그 인증서로도 잘 서명하고(로컬 서명엔 신뢰가 필요 없다) 지정 요구사항도 안정적이다.
# `|| true`: 아직 ID 가 없으면 grep 이 1 로 끝나는데, pipefail+set -e 조합에서 그게
# 스크립트를 여기서 죽인다(정상적인 첫 실행이 그렇다). 빈 결과를 정상으로 받는다.
existing="$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
  | grep -F "\"$IDENTITY_NAME\"" | head -1 | awk '{print $2}' || true)"
if [ -n "$existing" ]; then
  echo "이미 있음: $IDENTITY_NAME ($existing) — $KEYCHAIN"
  exit 0
fi

command -v openssl >/dev/null 2>&1 || {
  echo "openssl 을 찾지 못했다 — 인증서를 만들 수 없다" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cc-signing.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

KEY="$TMP/key.pem"
CERT="$TMP/cert.pem"
P12="$TMP/identity.p12"
CONF="$TMP/openssl.cnf"

# 코드 서명 인증서에 필요한 확장:
#   basicConstraints=critical,CA:false   — 최종 엔티티 인증서(CA 아님)
#   keyUsage=critical,digitalSignature   — 서명용
#   extendedKeyUsage=critical,codeSigning(1.3.6.1.5.5.7.3.3) — codesign 이 이걸 본다
cat > "$CONF" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY_NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF

# EC(prime256v1) 키 + 10년짜리 self-signed 인증서. -nodes: 키에 암호를 걸지 않는다.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout "$KEY" -out "$CERT" -days 3650 -config "$CONF" >/dev/null 2>&1 || {
  echo "인증서 생성 실패" >&2; exit 1; }

# 키+인증서를 PKCS#12 로 묶는다. 고정 임시 암호 — 곧바로 import 하고 지운다.
# -legacy 는 openssl 3 이 macOS security 가 읽는 형식(RC2/3DES + SHA-1 MAC)으로
# 내보내게 한다. 이게 없으면 security import 가 MAC 검증에서 실패한다.
if ! openssl pkcs12 -export -inkey "$KEY" -in "$CERT" -out "$P12" \
      -passout "pass:$P12_PW" -name "$IDENTITY_NAME" -legacy >/dev/null 2>&1; then
  # -legacy 를 모르는 구버전 openssl 대비.
  openssl pkcs12 -export -inkey "$KEY" -in "$CERT" -out "$P12" \
    -passout "pass:$P12_PW" -name "$IDENTITY_NAME" >/dev/null 2>&1 || {
    echo ".p12 생성 실패" >&2; exit 1; }
fi

# 키체인에 넣는다. -T 로 codesign·security 가 이 키를 쓸 수 있게 미리 허용 목록에 올린다.
# add-trusted-cert 는 하지 않는다 — SSL 신뢰가 아니라 코드 서명에만 쓸 것이고, 신뢰
# 앵커 등록(admin 도메인)은 sudo/GUI 를 부른다. 코드 서명에는 키체인에 있기만 하면 된다.
if ! security import "$P12" -k "$KEYCHAIN" -P "$P12_PW" \
      -T /usr/bin/codesign -T /usr/bin/security >/dev/null 2>&1; then
  echo "키체인($KEYCHAIN)으로 import 실패 — 키체인이 잠겨 있는지 확인해 주세요" >&2
  exit 1
fi

# codesign 이 실행할 때 GUI "허용" 창을 띄우지 않게 파티션 목록을 연다. -k 로 키체인
# 암호를 준다. 로그인 키체인은 보통 로그인 암호라, 빈 값이면 여기서 실패한다 —
# 매달리지 않고(암호를 명령줄로 주므로 프롬프트가 없다) 곧바로 에러가 난다.
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: \
      -s -k "$KEYCHAIN_PW" "$KEYCHAIN" >/dev/null 2>&1; then
  cat >&2 <<MSG
경고: set-key-partition-list 에 실패했습니다.
  인증서·키는 키체인($KEYCHAIN)에 들어갔지만, codesign 이 키를 쓸 때 GUI 허용 창이
  뜰 수 있습니다. 로그인 키체인 암호(보통 로그인 암호)를 주고 아래를 한 번 실행하세요:

    security set-key-partition-list -S apple-tool:,apple:,codesign: \\
      -s -k "<로그인 암호>" "$KEYCHAIN"

  또는 codesign 이 처음 뜨는 "항상 허용" 창을 한 번 눌러 줘도 됩니다.
MSG
  exit 1
fi

sha="$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
  | grep -F "\"$IDENTITY_NAME\"" | head -1 | awk '{print $2}' || true)"
if [ -z "$sha" ]; then
  echo "만들었지만 codesign 용 ID 목록에서 찾지 못했습니다 — 인증서 EKU 를 확인해 주세요" >&2
  exit 1
fi

echo "만들었습니다: $IDENTITY_NAME"
echo "  SHA-1: $sha"
echo "  키체인: $KEYCHAIN"
echo "이제 ./scripts/install.sh (또는 bundle.sh) 가 이 ID 로 서명합니다."

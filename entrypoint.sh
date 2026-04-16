#!/bin/sh
set -e

CERT_DIR="/etc/haproxy/certs"
CA_URL="${CA_URL:-http://ca-server/api/admin/proxy-cert}"
SHORE_HOST="${SHORE_HOST:-localhost}"
SHORE_PORT="${SHORE_PORT:-29090}"

echo "[entrypoint] SHORE_HOST=${SHORE_HOST}, SHORE_PORT=${SHORE_PORT}"
echo "[entrypoint] CA_URL=${CA_URL}"

# CRT가 없으면 CSR 생성 → CA 전송 → CRT 저장
if [ ! -f "$CERT_DIR/client.crt" ]; then
    echo "[entrypoint] client.crt 없음 → CSR 생성 후 CA 요청"

    # CSR 생성 (client.key는 이미 존재)
    openssl req -new \
      -key "$CERT_DIR/client.key" \
      -subj "/CN=Shore Gateway Forward Proxy/O=KRINS/C=KR" \
      -out "$CERT_DIR/client.csr"

    # JSON 페이로드 생성
    PAYLOAD=$(python3 -c "
import json
csr = open('$CERT_DIR/client.csr').read()
print(json.dumps({
    'certType':     'FORWARD_PROXY',
    'csr':          csr,
    'subjectCn':    'Shore Gateway Forward Proxy',
    'organization': 'KRINS',
    'country':      'KR',
    'uris':         ['urn:mrn:mcp:device:krins:shore-gw-fwd']
}))
")

    # CA 서버로 JSON 전송 → 응답에서 certificatePem 추출 → client.crt 저장
    RESPONSE=$(curl -sf -X POST "$CA_URL" \
      -u "admin:admin1234" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD")

    echo "$RESPONSE" | python3 -c "
import json, sys
body = json.load(sys.stdin)
if not body.get('success'):
    print('[entrypoint][ERROR] 인증서 발급 실패:', body.get('message'))
    sys.exit(1)
pem = body['data']['certificatePem']
with open('$CERT_DIR/client.crt', 'w') as f:
    f.write(pem)
"
    echo "[entrypoint] client.crt 발급 완료"
else
    echo "[entrypoint] client.crt 존재 → CA 요청 생략"
fi

# HAProxy용 PEM 합본 생성 (crt + key) - 항상 재생성 (이전 실행에서 깨진 경우 복구)
cat "$CERT_DIR/client.crt" "$CERT_DIR/client.key" > "$CERT_DIR/client.pem"
echo "[entrypoint] client.pem 생성 완료"

# 환경변수를 실제 값으로 치환한 설정 파일 생성
sed \
  -e "s|\${SHORE_HOST}|${SHORE_HOST}|g" \
  -e "s|\${SHORE_PORT}|${SHORE_PORT}|g" \
  /usr/local/etc/haproxy/haproxy.cfg.tmpl \
  > /usr/local/etc/haproxy/haproxy.cfg

echo "[entrypoint] haproxy.cfg 생성 완료"

exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg "$@"

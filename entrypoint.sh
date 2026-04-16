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

    # JSON 페이로드 생성 (jq가 CSR 개행문자 이스케이프 자동 처리)
    PAYLOAD=$(jq -n \
      --arg csr "$(cat "$CERT_DIR/client.csr")" \
      '{
        certType: "FORWARD_PROXY",
        csr: $csr,
        subjectCn: "Shore Gateway Forward Proxy",
        organization: "KRINS",
        country: "KR",
        uris: ["urn:mrn:mcp:device:krins:shore-gw-fwd"]
      }')

    # CA 서버로 JSON 전송 → 응답에서 certificatePem 추출 → client.crt 저장
    curl -sf -X POST "$CA_URL" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
    | jq -r '.data.certificatePem' > "$CERT_DIR/client.crt"

    # HAProxy용 PEM 합본 생성 (crt + key)
    cat "$CERT_DIR/client.crt" "$CERT_DIR/client.key" > "$CERT_DIR/client.pem"

    echo "[entrypoint] client.crt 발급 완료"
else
    echo "[entrypoint] client.crt 존재 → CA 요청 생략"
fi

# 환경변수를 실제 값으로 치환한 설정 파일 생성
sed \
  -e "s|\${SHORE_HOST}|${SHORE_HOST}|g" \
  -e "s|\${SHORE_PORT}|${SHORE_PORT}|g" \
  /usr/local/etc/haproxy/haproxy.cfg.tmpl \
  > /usr/local/etc/haproxy/haproxy.cfg

echo "[entrypoint] haproxy.cfg 생성 완료"

exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg "$@"

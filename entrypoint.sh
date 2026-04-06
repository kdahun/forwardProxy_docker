#!/bin/sh
set -e

# 환경변수 기본값
SHORE_HOST="${SHORE_HOST:-localhost}"
SHORE_PORT="${SHORE_PORT:-5000}"

echo "[entrypoint] SHORE_HOST=${SHORE_HOST}, SHORE_PORT=${SHORE_PORT}"

# 환경변수를 실제 값으로 치환한 설정 파일 생성
sed \
  -e "s|\${SHORE_HOST}|${SHORE_HOST}|g" \
  -e "s|\${SHORE_PORT}|${SHORE_PORT}|g" \
  /usr/local/etc/haproxy/haproxy.cfg.tmpl \
  > /usr/local/etc/haproxy/haproxy.cfg

echo "[entrypoint] haproxy.cfg 생성 완료"

exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg "$@"

FROM haproxy:2.9-alpine

USER root

# 설정 파일을 템플릿으로 복사 (entrypoint에서 envsubst)
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg.tmpl

# entrypoint 스크립트 복사
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# HTTP 프록시 포트 / WebSocket 포트 / Stats 포트
EXPOSE 28080 28081 28404

ENTRYPOINT ["/entrypoint.sh"]

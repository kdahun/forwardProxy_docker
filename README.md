# Forward Proxy (선박 측) — HAProxy Docker

## 구조

```
Java GW (선박국)
  │
  ├─ HTTP  → localhost:8080 → HAProxy → SHORE_HOST:SHORE_PORT (REST API)
  └─ WS    → localhost:8081 → HAProxy → SHORE_HOST:SHORE_PORT (WebSocket)
```

## 아웃바운드 제어 (허용 경로)

| 경로 | 용도 |
|---|---|
| `GET  /api/health` | 헬스체크 |
| `POST /api/session` | 세션 생성 (로그인 + 인증서 검증) |
| `WS   /api/push/ws` | WebSocket 세션 연결 |
| `/hello/*` | 테스트용 엔드포인트 |

위 경로 외 모든 요청은 **HAProxy 레벨에서 차단 (403)**.

---

## 실행 방법

### 1. 로컬 테스트 (REST API 서버 포함)

`restAPI.py` 를 이 디렉토리에 복사한 뒤:

```bash
docker compose up --build
```

| 접속처 | URL |
|---|---|
| REST API (프록시 경유) | http://localhost:8080/api/health |
| WebSocket (프록시 경유) | ws://localhost:8081/api/push/ws |
| HAProxy Stats | http://localhost:8404/stats |
| REST API (직접) | http://localhost:5000/api/health |

### 2. 실제 해안국 서버로 연결

`docker-compose.yml` 에서 환경변수만 변경:

```yaml
environment:
  SHORE_HOST: <해안국-공인IP>   # 예: 203.0.113.10
  SHORE_PORT: "30443"           # 해안국 Nginx NodePort
```

또는 docker run:

```bash
docker build -t forward-proxy .
docker run -d \
  -p 8080:8080 \
  -p 8081:8081 \
  -p 8404:8404 \
  -e SHORE_HOST=<해안국-IP> \
  -e SHORE_PORT=5000 \
  --name forward-proxy \
  forward-proxy
```

---

## Java GW 연결 예시

### REST (로그인 + 세션 생성)

```java
// 프록시를 경유하므로 클라이언트는 proxy IP:8080 만 바라봄
HttpClient client = HttpClient.newHttpClient();

HttpRequest req = HttpRequest.newBuilder()
    .uri(URI.create("http://localhost:8080/api/session"))
    .header("Content-Type", "application/json")
    .POST(HttpRequest.BodyPublishers.ofString(
        "{\"userId\":\"ship-01\", \"cert\":\"...\"}"))
    .build();

HttpResponse<String> res = client.send(req, HttpResponse.BodyHandlers.ofString());
// {"status":"ok","session_id":"..."}
```

### WebSocket (세션 연결)

```java
// WS 전용 포트 8081 사용
WebSocket ws = HttpClient.newHttpClient()
    .newWebSocketBuilder()
    .buildAsync(URI.create("ws://localhost:8081/api/push/ws"),
        new WebSocket.Listener() {
            public CompletionStage<?> onText(WebSocket ws, CharSequence data, boolean last) {
                System.out.println("수신: " + data);
                return null;
            }
        })
    .join();
```

---

## 허용 경로 추가 방법

`haproxy.cfg` 의 ACL 블록에 추가:

```haproxy
acl is_new_path  path_beg /api/new-endpoint
http-request deny unless ... or is_new_path
```

이후 `docker compose up --build` 로 재빌드.

---

## 포트 요약

| 포트 | 용도 |
|---|---|
| 8080 | Java GW → 프록시 (HTTP / REST) |
| 8081 | Java GW → 프록시 (TCP / WebSocket) |
| 8404 | HAProxy Stats 모니터링 |

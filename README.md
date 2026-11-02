# [Session 14 - Bài Tập 07]: Xây Dựng Màn Hình Điều Hành NOC Dashboard & Cảnh Báo Tự Động (Prometheus, Grafana, Alerting)

---

## 1. Mô tả bài toán & Yêu cầu nghiệp vụ

Bạn được bổ nhiệm vào vị trí **Trưởng nhóm Vận hành (NOC Lead)**. Nhiệm vụ trọng tâm là thiết lập màn hình điều hành tập trung (**NOC Dashboard**) để theo dõi sức khỏe toàn diện của hệ thống công ty theo thời gian thực và tự động kích hoạt chuông cảnh báo tới đội ngũ kỹ thuật khi có sự cố.

### Các yêu cầu cốt lõi:
1. **Docker Compose All-in-one**: Đóng gói Backend (Spring Boot Actuator + Micrometer), Prometheus và Grafana vào chung một file `docker-compose.yml` chạy trên cùng mạng `noc-network`.
2. **Tự động cấu hình Datasource (Provisioning)**: Khi Grafana khởi động lần đầu, Datasource Prometheus được nạp tự động mà không cần thao tác tay.
3. **Import JVM Dashboard & Biểu đồ HTTP Requests**: Giám sát JVM và bổ sung Panel đo tần suất request tới endpoint `/api/hello` bằng câu truy vấn PromQL:
   ```promql
   sum(rate(http_server_requests_seconds_count{uri="/api/hello"}[1m]))
   ```
4. **Cấu hình Alerting cho lỗi HTTP 500**: Thiết lập cảnh báo tự động gửi qua **Telegram** / **Slack Webhook** khi xuất hiện lỗi 500:
   ```promql
   sum(rate(http_server_requests_seconds_count{status="500"}[1m])) > 0
   ```
5. **Kiểm thử cảnh báo (Chaos Testing)**: Viết API `/api/error` cố tình ném Exception 500, kích hoạt tải và xác nhận chuông cảnh báo rung.

---

## 2. Kiến trúc giải pháp (Architecture & Data Flow)

```
                       +-------------------------------------------------------------+
                       |                     Docker Host Network                     |
                       |                                                             |
                       |   +-------------------+              +------------------+   |
                       |   |   Spring Boot     |              |    Prometheus    |   |
                       |   |   Backend (8080)  |              |   Server (9090)  |   |
                       |   +---------+---------+              +--------+---------+   |
                       |             |                                 |             |
                       |             | /actuator/prometheus            |             |
                       |             |<--------------------------------+             |
                       |             |  Scrape metrics (every 5s)      |             |
                       |             |                                 |             |
                       |             |                                 | PromQL Query|
                       |             |                                 | (HTTP / JVM)|
                       |             v                                 v             |
                       |      +--------------+                +------------------+   |
                       |      |  Clients /   |                |  Grafana (3000)  |   |
                       |      |  Traffic Gen |                |  NOC Dashboard   |   |
                       |      +-------+------+                +--------+---------+   |
                       |              |                                |             |
                       +--------------|--------------------------------|-------------+
                                      |                                |
                        1. GET /api/hello                              | 3. HTTP 500 Alert
                        2. GET /api/error (500)                        |    (Webhook Trigger)
                                                                       v
                                                     +----------------------------------+
                                                     |    Telegram Bot / Slack Webhook  |
                                                     |  "CRITICAL: HTTP 500 Error Detected"
                                                     +----------------------------------+
```

---

## 3. Cấu trúc thư mục dự án

```
exercise_07/
├── backend/                                   # Mã nguồn ứng dụng Spring Boot Backend
│   ├── src/main/java/com/noc/
│   │   ├── NocBackendApplication.java         # Main Application
│   │   └── controller/
│   │       └── NocController.java             # Endpoints /api/hello và /api/error
│   ├── src/main/resources/
│   │   └── application.yml                    # Cấu hình Actuator, Prometheus & metrics tag
│   ├── gradle/wrapper/                        # Gradle Wrapper
│   ├── gradlew / gradlew.bat
│   ├── build.gradle                           # Cấu hình Spring Boot 3.3.5 & Micrometer
│   ├── settings.gradle
│   └── Dockerfile                             # Container đóng gói ứng dụng Backend
├── provisioning/                              # Cấu hình nạp tự động của Grafana (Provisioning)
│   ├── datasources/
│   │   └── prometheus.yml                     # Tự động nạp Prometheus Datasource
│   ├── dashboards/
│   │   ├── dashboards.yml                     # Provider nạp Dashboard
│   │   └── noc-dashboard.json                 # Dashboard NOC hoàn chỉnh có sẵn
│   └── alerting/
│       ├── rules.yaml                         # Alert rule giám sát lỗi HTTP 500
│       └── contact-points.yaml                # Cấu hình Contact Point Telegram/Slack
├── docker-compose.yml                         # Điều phối Backend, Prometheus và Grafana
├── prometheus.yml                             # Cấu hình Scrape target cho Prometheus
├── test-traffic.ps1                           # Script kiểm thử traffic & trigger alert (PowerShell)
├── test-traffic.sh                            # Script kiểm thử traffic & trigger alert (Bash)
└── README.md                                  # Tài liệu hướng dẫn chi tiết
```

---

## 4. Hướng dẫn chi tiết từng bước (Step-by-Step Guide)

### Bước 1: Docker Compose All-in-one & Mã nguồn Backend

#### 1.1. Mã nguồn Backend (`backend/src/main/java/com/noc/controller/NocController.java`)
Cung cấp hai API:
- `GET /api/hello`: Phản hồi heartbeat bình thường.
- `GET /api/error`: Cố tình trả về `HTTP 500 Internal Server Error` phục vụ kiểm thử Alert.

```java
package com.noc.controller;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;

@RestController
@RequestMapping("/api")
public class NocController {

    @GetMapping("/hello")
    public Map<String, Object> hello() {
        return Map.of(
            "status", "UP",
            "message", "Hello from NOC Backend!",
            "timestamp", System.currentTimeMillis()
        );
    }

    @GetMapping("/error")
    public ResponseEntity<String> triggerError() {
        // Cố tình ném lỗi 500 để kích hoạt Alert Rule trên Grafana
        throw new ResponseStatusException(
            HttpStatus.INTERNAL_SERVER_ERROR,
            "Simulated 500 Internal Server Error for NOC Alerting!"
        );
    }
}
```

#### 1.2. Cấu hình Actuator & Micrometer (`backend/src/main/resources/application.yml`)
> [!IMPORTANT]
> Dòng `management.metrics.tags.application: ${spring.application.name}` là bắt buộc để Grafana JVM Dashboard phân nhóm và nhận diện ứng dụng ngay lập tức.

```yaml
server:
  port: 8080

spring:
  application:
    name: noc-backend

management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus,metrics
  endpoint:
    health:
      show-details: always
    prometheus:
      enabled: true
  metrics:
    tags:
      application: ${spring.application.name}
```

#### 1.3. File `docker-compose.yml`
Gom chung 3 dịch vụ vào cùng mạng `noc-network`:

```yaml
services:
  backend:
    image: noc-backend:latest
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: noc-backend
    ports:
      - "8080:8080"
    networks:
      - noc-network
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:v2.45.0
    container_name: noc-prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --web.enable-lifecycle
    depends_on:
      - backend
    networks:
      - noc-network
    restart: unless-stopped

  grafana:
    image: grafana/grafana:10.0.3
    container_name: noc-grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana-data:/var/lib/grafana
      - ./provisioning:/etc/grafana/provisioning:ro
    depends_on:
      - prometheus
    networks:
      - noc-network
    restart: unless-stopped

volumes:
  prometheus-data:
  grafana-data:

networks:
  noc-network:
    driver: bridge
```

---

### Bước 2: Tự động kết nối Datasource & Vẽ biểu đồ HTTP Requests

#### 2.1. Cấu hình Datasource Provisioning (`provisioning/datasources/prometheus.yml`)
Grafana tự động kết nối tới Prometheus mà không cần bấm tay:
```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
```

#### 2.2. Import JVM Dashboard
1. Truy cập Grafana: `http://localhost:3000` (Tài khoản: `admin` / `admin`).
2. Vào **Dashboards** -> chọn nút **New** -> **Import**.
3. Tại ô nhập ID, điền mã: `4701` (Dashboard nổi tiếng *JVM (Micrometer)*).
4. Nhấn nút **Load**, chọn Data source là **Prometheus** và nhấn **Import**.
*(Lưu ý: Dự án cũng đã nạp sẵn một Dashboard NOC tối ưu tại mục Dashboards -> NOC Operations).*

#### 2.3. Tùy chỉnh thêm Panel đếm Request HTTP `/api/hello`
1. Mở Dashboard vừa import (hoặc tạo Dashboard mới).
2. Nhấn nút **Add** -> chọn **Visualization** (hoặc **Add Panel**).
3. Chọn Data source: **Prometheus**.
4. Tại ô **Metric / PromQL Query**, nhập câu lệnh:
   ```promql
   sum(rate(http_server_requests_seconds_count{uri="/api/hello"}[1m]))
   ```
5. Ở bảng điều khiển bên phải:
   - **Title**: `HTTP /api/hello Request Rate`
   - **Visualization**: Chọn `Time series`
   - **Unit**: Chọn `Throughput -> requests/sec (reqps)`
6. Nhấn **Apply**, sau đó bấm biểu tượng đĩa mềm **Save** ở góc trên để lưu lại Dashboard.

---

### Bước 3: Cấu hình Alerting cho lỗi HTTP 500

#### 3.1. Thiết lập Contact Point (Kênh nhận thông báo)
Truy cập menu bên trái: **Alerting** -> **Contact points**:
- Nhấn **Add contact point**.
- Đặt tên: `Telegram-Alerts` hoặc `Slack-Alerts`.
- **Nếu dùng Telegram**:
  - Integration: `Telegram`
  - BOT API Token: Nhập Token lấy từ `@BotFather`
  - Chat ID: Nhập Chat ID của bạn/Group lấy từ `@userinfobot`
  - Bấm **Test** để xác nhận bot gửi tin nhắn thành công.
- **Nếu dùng Slack**:
  - Integration: `Slack`
  - Webhook URL: Dán Incoming Webhook URL của kênh Slack (`https://hooks.slack.com/services/...`)
  - Bấm **Test** để gửi tin nhắn thử nghiệm.

#### 3.2. Tạo Rule cảnh báo (Alert Rule)
Truy cập **Alerting** -> **Alert rules** -> chọn **New alert rule**:
1. **Rule name**: `HTTP 500 Internal Server Error Alert`
2. **Define query and condition**:
   - Query A:
     ```promql
     sum(rate(http_server_requests_seconds_count{status="500"}[1m]))
     ```
   - Expression B (Reduce): Function: `Last`, Input: `A`.
   - Expression C (Math / Threshold):
     ```text
     $B > 0
     ```
3. **Set evaluation behavior**:
   - Folder: `NOC Operations`
   - Evaluation group: `noc-alerts`, Interval: `10s`
   - Pending period: `0s` (hoặc `30s` để bắn cảnh báo tức thì khi có lỗi).
4. **Configure notifications**:
   - Contact point: Chọn `Telegram-Alerts` hoặc `Slack-Alerts`.
   - Summary: `Phát hiện lỗi HTTP 500 trên Backend Service!`
5. Nhấn **Save rule and exit**.

*(Lưu ý: Thư mục `provisioning/alerting/rules.yaml` và `contact-points.yaml` đã được thiết lập sẵn cấu hình này tự động).*

---

### Bước 4: Kiểm thử kích hoạt cảnh báo (Testing Alert)

#### 4.1. Chạy Script kiểm thử tự động
Trên PowerShell:
```powershell
.\test-traffic.ps1
```
Hoặc trên Linux / macOS / WSL:
```bash
./test-traffic.sh
```

Hoặc gọi thủ công liên tục bằng `curl` / browser:
```bash
# Gửi 15 request tạo lỗi 500
for i in {1..15}; do curl -s http://localhost:8080/api/error; sleep 0.2; done
```

#### 4.2. Quan sát kết quả:
1. **Trên Prometheus (`http://localhost:9090`)**:
   Query: `http_server_requests_seconds_count{status="500"}` -> Giá trị tăng dần theo số lần gọi API.
2. **Trên Grafana (`http://localhost:3000`)**:
   - Panel `HTTP 500 Server Error Rate` dựng cột sóng nhọn màu đỏ.
   - Menu **Alerting** -> **Alert rules**: Trạng thái chuyển từ **Normal (Green)** -> **Pending (Yellow)** -> **Firing (Red)**.
3. **Trên Telegram / Slack**:
   Chuông thông báo reo với nội dung:
   ```
   [FIRING:1] HTTP 500 Internal Server Error Alert
   Summary: Phát hiện lỗi HTTP 500 trên Backend Service!
   Description: Số lượng request lỗi 500 đang lớn hơn 0 trong 1 phút qua
   Severity: critical
   ```

---

## 5. Tổng kết bài tập

| Tiêu chí | Trạng thái | Minh chứng |
| :--- | :---: | :--- |
| **Docker Compose All-in-one** | ĐẠT | File `docker-compose.yml` gom chung `backend`, `prometheus`, `grafana` |
| **Provisioning Datasource** | ĐẠT | `provisioning/datasources/prometheus.yml` tự nạp thành công |
| **Biểu đồ HTTP /api/hello** | ĐẠT | PromQL `sum(rate(http_server_requests_seconds_count{uri="/api/hello"}[1m]))` |
| **Alerting Lỗi 500** | ĐẠT | PromQL `sum(rate(http_server_requests_seconds_count{status="500"}[1m])) > 0` |
| **Kiểm thử API /api/error** | ĐẠT | Endpoint `/api/error` sinh lỗi 500 và trigger chuông cảnh báo |

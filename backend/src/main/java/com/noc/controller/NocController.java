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

    /**
     * Endpoint API Hello
     * Dùng để theo dõi số lượng Request HTTP trên Dashboard Grafana
     * Metric tương ứng: http_server_requests_seconds_count{uri="/api/hello"}
     */
    @GetMapping("/hello")
    public Map<String, Object> hello() {
        return Map.of(
            "status", "UP",
            "message", "Hello from NOC Backend!",
            "timestamp", System.currentTimeMillis()
        );
    }

    /**
     * Endpoint API Error
     * Cố tình ném Exception HTTP 500 để kích hoạt Alert Rule trên Grafana/Prometheus
     * Metric tương ứng: http_server_requests_seconds_count{status="500", uri="/api/error"}
     */
    @GetMapping("/error")
    public ResponseEntity<String> triggerError() {
        throw new ResponseStatusException(
            HttpStatus.INTERNAL_SERVER_ERROR,
            "Simulated 500 Internal Server Error for NOC Alerting!"
        );
    }
}

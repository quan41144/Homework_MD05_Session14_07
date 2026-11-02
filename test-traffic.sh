#!/usr/bin/env bash
# Script test traffic cho NOC Dashboard & Alerting
ACTION="${1:-all}"

echo "=========================================================="
echo "          NOC MONITORING TRAFFIC & ALERT TESTER          "
echo "=========================================================="

check_health() {
  echo -e "\n[1] Kiem tra trang thai cac dich vu:"
  curl -s http://localhost:8080/api/hello > /dev/null && echo "  -> Backend /api/hello: OK" || echo "  -> Backend: FAILED"
  curl -s http://localhost:8080/actuator/prometheus > /dev/null && echo "  -> Actuator Prometheus: OK" || echo "  -> Actuator: FAILED"
  curl -s http://localhost:9090/-/healthy > /dev/null && echo "  -> Prometheus (9090): OK" || echo "  -> Prometheus: FAILED"
  curl -s http://localhost:3000/api/health > /dev/null && echo "  -> Grafana (3000): OK" || echo "  -> Grafana: FAILED"
}

send_hello() {
  echo -e "\n[2] Gui 20 requests toi /api/hello tao traffic..."
  for i in {1..20}; do
    curl -s http://localhost:8080/api/hello > /dev/null
    echo -n "."
    sleep 0.15
  done
  echo -e "\n  -> Xong traffic /api/hello! Kiem tra do thi tren Grafana."
}

trigger_error() {
  echo -e "\n[3] Gui 10 requests loi 500 toi /api/error kich hoat Alert..."
  for i in {1..10}; do
    curl -s http://localhost:8080/api/error > /dev/null || true
    echo -n "!"
    sleep 0.2
  done
  echo -e "\n  -> Xong! Kiem tra Grafana Alerting rules (chuyen sang Firing)."
}

case "$ACTION" in
  check)
    check_health
    ;;
  hello)
    send_hello
    ;;
  error)
    trigger_error
    ;;
  *)
    check_health
    send_hello
    trigger_error
    ;;
esac

echo -e "\n=========================================================="
echo "Grafana: http://localhost:3000 (admin / admin)"
echo "Prometheus: http://localhost:9090"
echo "=========================================================="

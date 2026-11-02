# Script test traffic cho NOC Dashboard & Alerting
param(
    [string]$Action = "all" # "hello", "error", "check", "all"
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "          NOC MONITORING TRAFFIC & ALERT TESTER          " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

function Check-Health {
    Write-Host "`n[1] Kiem tra trang thai cac dich vu:" -ForegroundColor Green
    
    # 1. Backend Hello
    try {
        $resHello = Invoke-RestMethod -Uri "http://localhost:8080/api/hello" -TimeoutSec 3
        Write-Host "  -> Backend /api/hello: OK (Status: $($resHello.status), Message: $($resHello.message))" -ForegroundColor Green
    } catch {
        Write-Host "  -> Backend /api/hello: FAILED ($($_.Exception.Message))" -ForegroundColor Red
    }

    # 2. Backend Actuator Prometheus
    try {
        $resProm = Invoke-RestMethod -Uri "http://localhost:8080/actuator/prometheus" -TimeoutSec 3
        Write-Host "  -> Backend /actuator/prometheus: OK (Metrics exported)" -ForegroundColor Green
    } catch {
        Write-Host "  -> Backend /actuator/prometheus: FAILED" -ForegroundColor Red
    }

    # 3. Prometheus Server
    try {
        $resTargets = Invoke-RestMethod -Uri "http://localhost:9090/api/v1/targets" -TimeoutSec 3
        $targetHealth = ($resTargets.data.activeTargets | Where-Object { $_.scrapePool -eq "noc-backend" }).health
        Write-Host "  -> Prometheus Server (Target noc-backend): $targetHealth" -ForegroundColor Green
    } catch {
        Write-Host "  -> Prometheus Server: FAILED" -ForegroundColor Red
    }

    # 4. Grafana
    try {
        $resGrafana = Invoke-RestMethod -Uri "http://localhost:3000/api/health" -TimeoutSec 3
        Write-Host "  -> Grafana (Port 3000): OK (Database: $($resGrafana.database))" -ForegroundColor Green
    } catch {
        Write-Host "  -> Grafana: FAILED" -ForegroundColor Red
    }
}

function Send-HelloTraffic([int]$count = 20) {
    Write-Host "`n[2] Gui $count requests toi /api/hello de tao traffic cho Timeseries..." -ForegroundColor Cyan
    for ($i = 1; $i -le $count; $i++) {
        try {
            $null = Invoke-RestMethod -Uri "http://localhost:8080/api/hello" -TimeoutSec 2
            Write-Host -NoNewline "."
        } catch {
            Write-Host -NoNewline "x"
        }
        Start-Sleep -Milliseconds 150
    }
    Write-Host "`n  -> Hoan thanh! Kiem tra Panel 'HTTP /api/hello Request Rate' tren Grafana." -ForegroundColor Green
}

function Trigger-500Error([int]$count = 10) {
    Write-Host "`n[3] Gui $count requests loi 500 toi /api/error de kich hoat Alert..." -ForegroundColor Red
    for ($i = 1; $i -le $count; $i++) {
        try {
            $null = Invoke-RestMethod -Uri "http://localhost:8080/api/error" -TimeoutSec 2
        } catch {
            Write-Host -NoNewline "!"
        }
        Start-Sleep -Milliseconds 200
    }
    Write-Host "`n  -> Hoan thanh gui loi 500! Alert Rule se chuyen sang Firing va gui canh bao Telegram/Slack." -ForegroundColor Yellow
}

if ($Action -eq "check") {
    Check-Health
} elseif ($Action -eq "hello") {
    Send-HelloTraffic 30
} elseif ($Action -eq "error") {
    Trigger-500Error 15
} else {
    Check-Health
    Send-HelloTraffic 15
    Trigger-500Error 10
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "Truy cap Grafana: http://localhost:3000 (admin / admin)" -ForegroundColor Yellow
Write-Host "Truy cap Prometheus: http://localhost:9090" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

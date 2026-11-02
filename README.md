# Docker Lab v5：Prometheus Alertmanager + Email 測試通知

本專案完整延續 **v4 fixed**：Flask、Nginx、PostgreSQL、pgAdmin、DB 權限與備份、Prometheus、Grafana、Exporters。**本版只增加 Alertmanager、Mailpit，並修改 Prometheus 告警轉送設定。** Compose 名稱依舊是 `flask-nginx-postgres-lab`；`postgres_data` 與 `pgadmin_data` 都保留。

## 目的與部署方式

預設使用 Mailpit 作為本機 SMTP 測試收件箱，不會對外寄送電子郵件。不需要輸入真實 SMTP 帳號密碼即可測通 `Prometheus -> Alertmanager -> Mailpit`。實際寄送真實信箱，請依下方「切換真實 SMTP」額外設定。

**重要：先備份 `.env` 與資料庫，將 ZIP 中的檔案合併到既有的專案路徑，保留現有 `.env`、資料庫 Volume，不要執行 `docker compose down -v`。**

在 Windows PowerShell（位於專案目錄）執行：

```powershell
# 可選：在既有 .env 新增（無設定時會採預設值）
Add-Content .env "`nALERTMANAGER_PORT=9093`nMAILPIT_UI_PORT=8025"

docker compose config --quiet
docker compose up -d mailpit alertmanager
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
# 上述檢查成功後，讓既有 Prometheus 載入新 alerting 設定
docker compose restart prometheus
docker compose ps
```

若 Prometheus 容器尚未建立，可執行 `docker compose up -d prometheus` 再檢查 config。

開啟：
- Alertmanager: <http://localhost:9093>
- Mailpit Inbox: <http://localhost:8025>
- Prometheus Alerts: <http://localhost:9090/alerts>
- Prometheus Alertmanagers: <http://localhost:9090/status> (在 UI Status 頁的 Alertmanagers 區塊)
- Grafana: <http://localhost:3000>

## 手動測試通知（不需要停止正式服務）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .lert-check.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .lert-test.ps1
```

開啟 <http://localhost:8025>，正常約 10–30 秒收到「DockerLabManualTest」告警郵件。`group_wait=10s`，首次啟動或網路負載會造成額外延遲。腳本送出的告警有約 2 分鐘的到期時間；到期時可能另外收到 resolved 郵件。

如看不到郵件，先確認 `docker compose logs --tail=100 alertmanager`、`docker compose logs --tail=100 mailpit`，以及 Alertmanager UI 內的 alert 狀態；亦可查 `alertmanager_notifications_failed_total`。

### 驗證真正服務故障告警（選用）

**僅供本機實驗：** 暫停 Flask，讓既有 `WebProbeFailed` 規則觸發：

```powershell
docker compose stop app
# 約 1 到 2 分鐘後檢查 Prometheus Alerts、Alertmanager 與 Mailpit
docker compose start app
```

v4 的 `WebProbeFailed` 使用 `for: 1m`；Prometheus 每 15s 評估一次，加上 Alertmanager 分組等待 10s，所以不是立即通知。一定要重新啟動 Flask。

## 服務與功能

| 服務 | 網址 | 說明 |
| --- | --- | --- |
| alertmanager | http://localhost:9093 | 告警聚合、路由、分組、沉默及通知狀態 |
| mailpit | http://localhost:8025 | 本機 SMTP 假收件箱 |
| prometheus | http://localhost:9090 | 以 alerting.alertmanagers 轉發 firing alerts |
| grafana | http://localhost:3000 | 圖表（保持 v4 原有資料） |

在 Prometheus UI 查看 `ALERTS{alertstate="firing"}` 或查詢 `up{job="alertmanager"}` 確認 Alertmanager 被監控。

## 切換真實 SMTP（選用，需要自備郵件服務）

預設 SMTP 是 `mailpit:1025`，只在 Docker 本機網路使用 `require_tls: false`；**此設定不可直接挪用於網際網路 SMTP。**

1. 複製 `monitoring/alertmanager/alertmanager.smtp.example.yml` 覆蓋 `monitoring/alertmanager/alertmanager.yml`（先備份原本的 Lab 設定）。
2. 用文字編輯器修改 `smtp_smarthost`、`smtp_from`、`smtp_auth_username`、`to`。例如外部 SMTP Port 587 + STARTTLS；若提供者要求 465 implicit TLS，請改 Port 並確認提供者支援方式。
3. 在 `monitoring/alertmanager/secrets/smtp_password.txt` 建立只有一行的 SMTP 專用密碼或 App Password。**不要提交 Git、不要傳到聊天中。** 這個檔案以 bind mount 形式載入容器內 `/etc/alertmanager/secrets/smtp_password.txt`。Windows 權限請限制其他本機使用者存取。
4. 驗證設定並套用：

```powershell
docker compose exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml
docker compose restart alertmanager
docker compose logs --tail=60 alertmanager
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .lert-test.ps1
```

**注意：** 寄到真實信箱需要 SMTP 出站網路及帳號授權。企業 SMTP 與 Gmail/Microsoft 365 的認證政策各有差異，不能保證一般帳密可用。應遵守 SMTP 服務政策，不建議在 `.env` 或 Git 中儲存郵件服務登入密碼。若要改回本機 Mailpit，將原本 `alertmanager.yml` 還原並重啟 Alertmanager 即可。

## 安全與常見故障

- Web 管理介面限制綁定 `127.0.0.1`。Mailpit 的 SMTP 1025 **沒有對主機發布 port**。
- `mailpit_data` 存放測試郵件，不要用真實客戶資料寄入這個測試系統。
- `alertmanager_data` 保存 silences 等資訊。避免 `docker compose down -v`，否則會刪除這兩個新 Volume，並一起刪除其他服務的 Volume。
- Alertmanager / Mailpit 都是本機演練用途，沒有設置 HTTPS / Web UI 使用者驗證，勿直接公開到 Internet。
- Prometheus 顯示 firing 但 Mailpit 沒信：檢查 Alertmanager 是否啟動、Prometheus 的 Alertmanagers 設定，以及 Email Receiver 與 SMTP 連線。
- `docker compose logs --tail=100 alertmanager` 用來確認 SMTP 連線或模板錯誤。
- 本文件只在離線環境進行 YAML/JSON/Python 等靜態驗證，尚未在你的 Docker Desktop 執行端對端容器測試。

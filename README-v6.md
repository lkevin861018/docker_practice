# Docker Lab v6｜Windows 11 容器安全強化與 Trivy 掃描

## 架構與相容性

這版延續 v5 所有容器、Prometheus、Grafana、Alertmanager、Mailpit、PostgreSQL 角色及備份工具，**不移除既有 Volume**。
只對 Flask `app` 服務預設套用保守的權限強化，其餘服務維持 v5 行為。
**v6 不會自動把現有 PostgreSQL、pgAdmin、Grafana 的密碼改掉。**

### 新增檔案

- `trivy-scan.ps1`：掃描本機 Docker Image（經 `docker image save`，不掛 Docker socket），產生 JSON 漏洞報告及 CycloneDX SBOM，同時檢查 `compose.yaml`、`Dockerfile` 設定風險。
- `security-check.ps1` + `app/security_verify.py`：檢查 Flask 容器是否非 root、唯讀、Linux Capabilities 與 NoNewPrivs，以及 API/DB 是否可用。
- `setup-app-secret.ps1`：建立本機 Compose Secrets 使用的文字檔。
- `compose.security-secrets.yaml`：選用的 Flask 資料庫密碼檔案掛載。
- `README-v6.md`：本教學。

### Flask 安全變更（在 `compose.yaml`）

```yaml
app:
  image: flask-nginx-postgres-lab-app:v6
  read_only: true
  tmpfs:
    - /tmp:rw,nosuid,noexec,size=64m
  cap_drop:
    - ALL
  security_opt:
    - no-new-privileges:true
  pids_limit: 128
  mem_limit: 512m
```

`app/Dockerfile` 既有 `USER appuser` 並非 root，予以保留。`app/app.py` 新增可優先使用 `DB_PASSWORD_FILE` 讀取資料庫密碼，舊的 `DB_PASSWORD` 仍可使用。
**不對 db 採用唯讀根目錄或強制變更使用者**，PostgreSQL 必須能正常寫入持久化資料。

## 1. 以 v5 原路徑升級

1. 確認 `backup.ps1` 已成功備份且備份檔有效，至少完成一次還原測試；不要只看 `.dump` 檔存在。
2. 保留 `.env`，**不要刪除任何 Volume**，不要執行 `docker compose down -v`。
3. 複製 v6 升級 ZIP 的檔案到原目錄，特別是 `compose.yaml`、`app/app.py`、三個新 PS 腳本以及 `compose.security-secrets.yaml`。
4. PowerShell（Windows 11）：

```powershell
cd C:\Users\WenLiang\Desktop\docker\docker_flask_nginx_postgres
docker compose config --quiet
docker compose up -d --build --no-deps app
docker compose ps app
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\security-check.ps1
```

如果 `--no-deps` 時 PostgreSQL 尚未啟動，先使用 `docker compose up -d --wait db` 啟動資料庫；若既有 `flask_app` 資料庫角色尚未建立，先完成 v3 的 `db-setup` 流程。

測試：

```powershell
Invoke-RestMethod http://localhost:8080/healthz
Invoke-RestMethod http://localhost:8080/api/visits
```

## 2. Trivy 掃描已建置的 Docker Images

預設掃描 `app`、`nginx`、`db`：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\trivy-scan.ps1
```

只掃描 Flask，且有 CRITICAL 發現時回傳失敗：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\trivy-scan.ps1 -Services app -FailOnCritical
```

掃描更多已存在的 Image（會使用更多磁碟空間與時間）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\trivy-scan.ps1 -Services "app,nginx,db,grafana,prometheus"
```

會在 `reports/trivy/<時間>/` 產生 `<服務>-vulnerabilities.json`、`<服務>-sbom.cdx.json` 以及 `config-findings.json`。
Trivy 使用 `aquasec/trivy:0.76.0`，需要下載漏洞資料庫；首次執行須有網際網路。
掃描器沒有掛載 Docker Engine socket，而是先以 `docker image save` 暫存單一 Image，再由 Trivy 讀取 Docker archive；掃描後暫存的 `.tar` 會移除。所需可用空間視 Image 大小而定，可能達數 GB。
Trivy Cache 會存在獨立的 `docker-lab-trivy-cache` Volume，不會碰 `postgres_data`。

**掃描限制：** HIGH/CRITICAL 只是已知元件弱點的對應結果，不代表漏洞在應用中可達或已經遭利用；無發現也不代表系統無漏洞。報告應結合網路曝險、受影響版本、修補狀態與服務上下文判斷優先順序。

## 3. 選用：Flask 使用 Docker Compose Secrets

安全性更進一步時，可避免 Flask 的密碼直接出現在其容器環境變數中。
此範例為 **Docker Compose 的本機檔案型 Secret**，不是外部 KMS，Windows 主機上的 Secret 仍以純文字儲存，必須搭配 NTFS 權限及磁碟加密；`.env` 內仍保留原密碼供 `db-setup` 使用，所以不是全系統移除明文密碼。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup-app-secret.ps1
```

輸入 **與 `.env` 的 APP_DB_PASSWORD 完全相同** 的既有密碼。完成後確認 `secrets/app_db_password.txt` 已建立（不必印出內容）。

```powershell
docker compose -f compose.yaml -f compose.security-secrets.yaml config --quiet
docker compose -f compose.yaml -f compose.security-secrets.yaml up -d --no-deps --force-recreate app
```

**重要：** Compose 覆寫檔必須在每次 `up` 操作中一同使用，否則下次重建可能恢復原本使用環境變數的設定。`docker compose exec app ...` 依然可使用主 Compose 執行。

可檢查 Secret 是否已掛載（不輸出密碼）：

```powershell
docker compose exec app python -c "import os; print(os.path.isfile('/run/secrets/app_db_password'))"
```

預期 `True`。若要回復一般環境變數設定：

```powershell
docker compose -f compose.yaml up -d --no-deps --force-recreate app
```

## 4. 安全檢查與已知限制

- **最小權限**：Flask 在 Image 中以非 root 啟動，並透過 `cap_drop: ALL` 刪除 Linux capabilities；仍非可完全隔離惡意程式的沙箱。
- **唯讀根檔案系統**：根目錄唯讀，但 `/tmp` 是獨立 tmpfs，可暫存必要資料。資料庫仍透過 Volume 寫入。
- **不要隨意套用到 Nginx/pgAdmin/Grafana/PostgreSQL**：它們可能需要寫入 PID、快取或資料目錄，要先確定可寫掛載及啟動流程。
- **cAdvisor**：原 v5 `cadvisor` profile 仍使用 `privileged: true`，僅在受信任的 Linux 研究環境啟用；沒有自動開啟。
- **Docker Engine socket**：不要把 `/var/run/docker.sock` 提供給不可信容器。即使 `:ro` 掛載 socket，也不等同限制 Docker API 的權限。
- **弱點處置**：先針對確有修補版本與曝險路徑的重大弱點更新 Image 與 Python 相依套件，重建後重掃。
- **本機入口**：原來的 Nginx、Grafana、pgAdmin、Prometheus、Alertmanager 與 Mailpit 皆綁到 Windows `127.0.0.1`；沒有提供公開部署的 HTTPS 或完整登入授權保護。

## 5. 官方參考

- https://docs.docker.com/reference/compose-file/services/
- https://docs.docker.com/compose/how-tos/use-secrets/
- https://trivy.dev/docs/latest/guide/target/container_image/
- https://trivy.dev/docs/latest/guide/supply-chain/sbom/
- https://trivy.dev/docs/latest/scanner/misconfiguration/


# Docker Lab v7：GitHub Actions CI/CD（接續 v6）

## 目標與保護界線

- PR / main push：Flask 單元測試 → PostgreSQL + Nginx 整合測試 → Trivy 高/重大弱點檢查 → CycloneDX SBOM。
- **只有 main 的 push 且所有檢查通過時**，才發布「同一份已掃描映像檔」到 GitHub Container Registry（GHCR），名稱：`ghcr.io/<owner>/<repo>-flask-app:<40位Git SHA>`。
- Ubuntu 部署為**手動 workflow_dispatch**，並可在 `production` Environment 設定審核者。部署只更新 `app` 服務，不刪除 Volume、不執行 db-setup、不修改 PostgreSQL。
- v7 的部署是假設 Ubuntu Server **事先已完整部署此專案**，包含 Docker Engine、Compose、`.env`、PostgreSQL role、`compose.yaml`、`compose.deploy.yaml`、`ci/deploy/remote-deploy.sh`。
- 不會將 Windows 本機 Docker Desktop 的 Volume 自動複製至 Ubuntu。初次移轉資料需要獨立規劃備份及還原。

## 1. Windows 11 安裝及驗證

在既有專案目錄操作：

```powershell
cd C:\Users\WenLiang\Desktop\docker\docker_flask_nginx_postgres
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\ci\windows-validate.ps1
```

解壓 v7 升級包、**只合併其檔案**，保留 `.env`、`secrets/`、`monitoring/alertmanager/secrets/`、所有備份及 Docker Volume。v7 新增 `.github/workflows`、`app/tests`、`ci` 及 `compose.deploy.yaml`；不需要執行 `docker compose down -v`。

可在本機 Docker Desktop 執行單元測試（非必須先有 GitHub）：

```powershell
docker compose build app
docker compose run --rm --no-deps -v "${PWD}/app/tests:/app/tests:ro" --entrypoint python app -m unittest discover -s /app/tests -v
```

若 PowerShell 的 volume 路徑格式有問題，可改成明確絕對路徑：`-v "C:/Users/.../app/tests:/app/tests:ro"`。

## 2. 建立 GitHub Repository

在 GitHub 建立**空的**儲存庫（可設為 Private）。於 Windows PowerShell：

```powershell
git init
git branch -M main
git add .
git status --short
git commit -m "Add v7 Flask CI CD and security scanning"
git remote add origin https://github.com/OWNER/REPOSITORY.git
git push -u origin main
```

若已有 Git remote/branch，不要重複 init 或覆寫 remote。`git status` 必須確認**沒有** `.env`、真實密碼、`backups/`、`secrets/` 或 `reports/`。建立 GitHub 的操作需依身分驗證方法（如 Git Credential Manager）登入。

## 3. CI Workflow：.github/workflows/ci.yml

觸發：`pull_request`、`push main`，或手動執行。採 GitHub-hosted `ubuntu-latest`；CI `.env.ci` 內全是隨機、短暫使用的測試密碼。`publish` 是獨立工作，僅它持有 `packages: write` 權限，並使用驗證工作上傳的**同一份映像檔 TAR**進行發布，避免重新建置造成版本漂移。CI 會在獨立的 runner 上建新 PostgreSQL 資料庫，不會觸及 Windows 的真實 Volume。

若任一測試失敗，或掃描到 **HIGH / CRITICAL** CVE，流程失敗，**不發布**。報告會以 GitHub Actions Artifact 保存：`trivy-vulnerabilities.json`、`sbom.cdx.json`。

Trivy 使用 `docker save` + `trivy image --input`，不需要把 Docker Socket 掛到 Trivy 容器。注意不同時期漏洞資料庫的變化會使結果不同。請優先修補，若需風險接受，應有核准期限與明確例外政策，不建議直接停用安全閘門。

映像檔名稱依 repository 完整路徑產生，例如 `ghcr.io/example/docker-lab-flask-app:1234...40位字元`。GHCR 可能預設為 Private，部署機需有讀取權限。

## 4. Ubuntu Server 前置作業（首次手動一次）

需要已安裝 Linux Docker Engine + Compose plugin 的 Ubuntu Server；非 Windows Docker Desktop。部署主機必須預先有完整的 v7 專案，路徑固定：`/opt/docker-lab`。不要把 `.env` 及秘密檔案放進 Git。

由管理員建立服務帳號與目錄後，把完整專案的**必要設定檔**放在 `/opt/docker-lab`（如 compose.yaml、compose.deploy.yaml、nginx/、db/、monitoring/、pgadmin/、app/、ci/deploy/），並建立**該主機自己的 `.env`**。

先依 v6 步驟手動啟動 DB、執行 db-setup、部署網站、驗證健康狀態並完成資料備份；再執行：

```bash
cd /opt/docker-lab
bash ci/deploy/preflight.sh
```

建議以專用 `deployer` 帳號執行，僅允許被核准的操作；**Docker 群組約等同主機 root 權限**，因此部署帳號與 SSH 金鑰具有高敏感性。最小化 SSH 入口和主機權限。

### 私有 GHCR Image：在 Ubuntu Server 上事先登入

如果 GHCR 映像檔是 Private，需要在 Ubuntu 端使用有 `read:packages` 權限的專用憑證登入（GitHub PAT classic / 組織支援的其他讀取方法）：

```bash
read -rs GHCR_TOKEN
printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USER --password-stdin
unset GHCR_TOKEN
```

不應將 GHCR 的帳密、Docker config 或伺服器 `.env` 上傳到 GitHub Repository。公開 GHCR 映像可依 Registry 公開拉取政策存取。

## 5. 設定 GitHub Actions 部署權限

在儲存庫 Settings → Environments 建立 `production`，在方案支援時設定 Required reviewers / branch restrictions。建立：

- Repository/Environment variables：`DEPLOY_HOST`（Ubuntu DNS/IPv4）、`DEPLOY_USER`（專用部署帳號）。
- Environment secrets：`SSH_PRIVATE_KEY`（只部署用的 SSH 私鑰）、`SSH_KNOWN_HOSTS`（事前驗證過 fingerprint 的 Ubuntu SSH 公鑰主機記錄）。

先在 Ubuntu 上建立**獨立 SSH key pair**，只把公鑰加入 deployer 的 `~/.ssh/authorized_keys`。在安全管道儲存私鑰到 GitHub secret。`SSH_KNOWN_HOSTS` 內容可以由管理員取得，再與 Ubuntu 主機上執行 `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` 的結果核對後使用。**不要**把未經核對的 `ssh-keyscan` 輸出當作可信資訊。

部署 Workflow 不會自動複製檔案、不會設定 Ubuntu、也不會自動對外開放 Port。原本 Nginx 仍是綁定 `127.0.0.1:8080`；若要讓外界存取應另規劃 HTTPS 與受控反向代理。

## 6. 進行正式部署

1. Push 到 main 後，於 GitHub Actions → `CI - Flask tests, integration, Trivy and GHCR` 查看通過紀錄。
2. 從通過的 main commit 取得完整 **40 位 SHA**；確認對應 GHCR tag 已發布。
3. Actions → `CD - manually approved app-only deploy` → Run workflow，輸入該 SHA。
4. 若啟用 Environment required reviewers，需先核准。Remote 腳本會 `docker pull`、只重建 `app`，接著檢查 `http://127.0.0.1:8080/healthz`。
5. 通過後更新 `.ci-last-good-image`；未通過會嘗試回滾到前一次成功的 Flask Image（第一次使用無前次 image 時，嘗試回到伺服器原本的本機 v6 image）。資料庫不會回滾；任何資料庫 schema 變更都應另外設計遷移、備份與回滾程序。

指令不會調用 `docker compose down -v`。所有 deployments 只使用已先行 `docker pull` 的 GHCR image。

## 7. 檢查 CI 是否成功

CI 中預期至少看見以下步驟：

```text
PASS: Nginx homepage
PASS: Flask health + PostgreSQL connection
PASS: PostgreSQL INSERT through API
PASS: PostgreSQL SELECT through API
Trivy gate - passed (depends on actual CVE database)
Published: ghcr.io/.../flask-app:<SHA> (main push only)
```

目前專案是**實驗應用**，並未建立正式登入/授權、公開 HTTPS、資料遷移及完整的 production HA。CI 通過不等於可直接上正式網際網路。

## 常見問題

- `GitHub Actions` 顯示 `secrets.GITHUB_TOKEN` 沒權限：檢查工作流程 package write、儲存庫的 package 授權與組織政策。
- `Trivy` 高風險 CVE：先看 `trivy-vulnerabilities.json`，更新 `python:3.13-slim` 或 requirements，再重新提交。此 gate 為刻意嚴格的練習設定。
- Ubuntu `pull access denied`：檢查 GHCR image tag、private package 可見性、server-side registry 登入權限。
- `connection refused :22`：檢查 SSH、防火牆、跳板與 Ubuntu SSH 設定（這個範例採預設 SSH 22）。
- `pg_isready` 失敗：先恢復 v6 PostgreSQL 與權限，不要讓 CD 在失效資料庫上繼續更新。
- Docker Desktop 本機無法連上 Ubuntu：CI 部署 SSH 是由 GitHub-hosted runner 發出，需以安全的網路方案讓 runner 可連接部署主機；若 Ubuntu 僅在 NAT / 內網，不應直接暴露 SSH，可改採 self-hosted runner 或內部跳板並重新評估權限隔離。

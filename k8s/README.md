# Docker Lab v9 | Kubernetes on Windows 11

目標：在 **Docker Desktop Kubernetes (kubeadm 單節點)** 執行既有 Flask + Nginx + PostgreSQL v8 應用。這是**新的獨立測試資料庫**，不會重用 Compose 的 PostgreSQL Volume、Tailscale Funnel、Grafana 或 pgAdmin。

## 0. 前置條件

- Docker Desktop 正常運作，切換到 Linux Containers。
- Docker Desktop > Kubernetes > Create cluster，為了本次**本機建置 Image**實驗，優先使用 `kubeadm` 單節點（`kind` 的 Image 儲存通常與主機分開）。
- 在 PowerShell 確認：`kubectl config use-context docker-desktop`；`kubectl get nodes`；`kubectl get storageclass`，要有可用的預設 StorageClass（否則 PVC 會 Pending）。
- **不要**使用 Docker Desktop 的 Reset Kubernetes Cluster 來排錯，這會刪除叢集資源。

## 1. 建置 Flask Image

在專案根目錄 `docker_flask_nginx_postgres` 內：

```powershell
docker build -t flask-k8s-lab:v1 .\app
docker image inspect flask-k8s-lab:v1
```

若使用 `kubeadm` 模式，且可與 Docker Engine 共用本機 Image，下面 `imagePullPolicy: Never` 才會成功。如果 Pod 顯示 `ErrImageNeverPull`，代表 Kubernetes 節點看不到該 Image。**不要反覆重建資料庫**，應先將 Image 推到可讓叢集下載的 Registry，並把 `25-db-setup-job.yaml`、`30-flask.yaml` 的 image 改成該 Registry Image，將 `imagePullPolicy` 改成 `IfNotPresent`。若 Registry 為私有，還需 `imagePullSecret`。`kind` 模式尤其常需要這一步。

## 2. 部署

```powershell
kubectl config use-context docker-desktop
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\k8s\deploy.ps1
```

腳本依序：建立 Namespace、產生各自獨立的隨機密碼 Secret（不顯示密碼）、套用 Nginx + PostgreSQL ConfigMap、建立 PostgreSQL StatefulSet 與新 PVC、等資料庫就緒、執行資料庫權限初始化 Job、部署 Flask、部署 Nginx。

如果不用腳本，手動命令順序：

```powershell
kubectl apply -f .\k8s\00-namespace.yaml
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\k8s\setup-secrets.ps1
kubectl apply -f .\k8s\10-configmaps.yaml
kubectl apply -f .\k8s\20-postgres.yaml
kubectl -n docker-k8s-lab rollout status statefulset/db --timeout=240s
kubectl apply -f .\k8s\25-db-setup-job.yaml
kubectl -n docker-k8s-lab wait --for=condition=complete job/role-setup --timeout=180s
kubectl apply -f .\k8s\30-flask.yaml
kubectl -n docker-k8s-lab rollout status deployment/flask --timeout=180s
kubectl apply -f .\k8s\40-nginx.yaml
kubectl -n docker-k8s-lab rollout status deployment/nginx --timeout=180s
```

## 3. 使用網站

在另一個 **保持開啟** 的 PowerShell 視窗：

```powershell
kubectl -n docker-k8s-lab port-forward service/nginx 18088:80
```

瀏覽 http://localhost:18088 （只有本機能存取，與目前 8080 Compose 網站互不干擾）。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\k8s\test.ps1
```

## 4. kubectl 常用指令

```powershell
kubectl -n docker-k8s-lab get pods,deploy,sts,svc,pvc
kubectl -n docker-k8s-lab logs deployment/flask --tail=50
kubectl -n docker-k8s-lab logs job/role-setup
kubectl -n docker-k8s-lab describe pod -l app=flask
kubectl -n docker-k8s-lab scale deployment/flask --replicas=3
kubectl -n docker-k8s-lab rollout status deployment/flask
kubectl -n docker-k8s-lab rollout undo deployment/flask
kubectl -n docker-k8s-lab get events --sort-by=.lastTimestamp
```

Flask 複本增多共用**同一個** PostgreSQL。PostgreSQL StatefulSet 固定 `replicas: 1`，不可直接增到 3 當作資料庫叢集。

## 5. 常見故障

| 現象 | 優先檢查 |
|------|---------|
| `ErrImageNeverPull` | Kubernetes 節點沒有 `flask-k8s-lab:v1`，改用 Registry + `IfNotPresent` |
| `Pending` / PVC Pending | `kubectl get storageclass`, `kubectl describe pvc -n docker-k8s-lab` |
| `CrashLoopBackOff` | `kubectl logs` / `kubectl describe pod` |
| Flask `/healthz` 503 | `kubectl logs job/role-setup`、DB Secret、Pod ready、DB Service |
| 無法打開 localhost:18088 | port-forward 視窗是否還開著，或 Windows 本地端 Port 衝突 |
| `Job already exists` | Job 為一次性，修改 Template 需另外建立新名稱或謹慎重建 Job |

## 6. 安全與資料注意事項

- Kubernetes Namespace 是資源範圍，**不等於完整安全隔離**。
- 此範例的 DB Secret 會存在 Kubernetes API / etcd；Secret 的 Base64 編碼**不是加密**。`setup-secrets.ps1` 會短暫寫入檔案後刪除，不要把 Secret 或 `.env` commit 到 GitHub。
- PostgreSQL Pod 用新 PVC `data-db-0`，與 Compose `postgres_data` 完全不同，不會自動同步舊資料。
- `kubectl delete namespace docker-k8s-lab` 會刪除包含 PVC 的資源，可能使測試資料遺失。需要保留時務必先備份資料庫。
- 不要將本機 `kubectl port-forward --address 0.0.0.0` 直接當成公網服務。正式上線應另設 Ingress / Gateway、TLS 與認證。
- 原版 Flask `POST /api/visits` 預設允許資料寫入；本機僅以 localhost 存取，切勿未經存取控管就公開。
- Docker Desktop 的 Reset Kubernetes 可能清除 StatefulSet/PVC；本地 PVC 不能替代備份。

## 7. 未納入此次 K8s 基礎版本的現有功能

pgAdmin、Prometheus、Grafana、Alertmanager、Tailscale Funnel 仍由原本 Docker Compose 管理。這次不自動搬遷這些容器，也沒有自動遷移舊資料庫。下一階段可導入 Helm、Ingress Controller、External Secrets 與 Tailscale Kubernetes Operator。

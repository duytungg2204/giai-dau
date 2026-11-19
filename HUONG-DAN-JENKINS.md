# Jenkins CI/CD

Jenkins chạy native trên Windows, không chạy trong Docker. Ứng dụng và PostgreSQL tiếp tục chạy trong Docker Compose. Jenkins chạy dưới tài khoản Windows hiện tại để dùng Docker Desktop, Git và Node.js.

## Đăng nhập Jenkins

Mở http://localhost:8081. Tài khoản quản trị đã tạo là `duytungg2204`. Mật khẩu được lưu trong file local:

```text
%USERPROFILE%\.jenkins-home\secrets\jenkins-admin-credentials.txt
```

File chỉ cấp quyền cho tài khoản Windows hiện tại, Administrators và SYSTEM; file không được commit.

Jenkins được cài ở `%LOCALAPPDATA%\Programs\JenkinsRuntime`; nếu đã dừng, chạy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\start-jenkins-windows.ps1
```

Scheduled Task `Jenkins Native Controller` tự chạy script này khi tài khoản Windows đăng nhập. Docker Desktop cần phiên người dùng đăng nhập để pipeline build/deploy được.

## Job theo dõi `main`

Job `giai-dau-ci` đã được tạo và cấu hình:

- Repo: `https://github.com/duytungg2204/giai-dau.git` (private)
- Credential: `github-read`
- Branch: `*/main`
- Pipeline script: `Jenkinsfile`
- SCM polling: mỗi phút

Jenkins dùng credential lấy từ Git Credential Manager của tài khoản Windows. Credential được mã hóa trong Jenkins và chỉ gắn với checkout repo. Nó kế thừa quyền repo của tài khoản GitHub; nếu token bị thu hồi hoặc hết hạn, cập nhật trong **Manage Jenkins → Credentials → System → Global credentials**. Không đưa token vào source code hoặc `.env`.

Jenkins poll GitHub mỗi phút vì chỉ chạy trên localhost, không nhận được webhook trực tiếp từ GitHub. Commit mới trên `main` sẽ tự kích hoạt pipeline.

Nếu cần tạo lại job, chọn **New Item → Pipeline → Pipeline script from SCM**, rồi nhập repo, credential, branch và Script Path như cấu hình trên.

## Build, deploy và rollback

Pipeline chạy `npm ci`, `npm run check`, rồi build Docker image có tag theo commit. Tham số `DEPLOY_TARGET` chọn nơi deploy:

- `compose` (mặc định): dùng `.env` trong `DEPLOY_DIR`, chỉ cập nhật app. Nếu app mới không trả HTTP 200 ở `/api/bootstrap-status`, pipeline khôi phục image trước đó. PostgreSQL và volume Compose hiện tại không bị thay đổi.
- `kubernetes`: dùng cluster `kind` local; Jenkins nạp image vừa build trực tiếp vào cluster, không cần registry. Script nối container PostgreSQL hiện có vào mạng nội bộ của kind, tạo Kubernetes Service/EndpointSlice và Secret DB tạm từ `.env`, sau đó cập nhật Deployment. Pipeline chờ readiness; nếu rollout lỗi, script rollback Deployment về revision trước.

### Chuẩn bị Kubernetes lần đầu

Cluster local đã được tạo bằng `scripts/setup-kubernetes-windows.ps1`; cấu hình cluster và cổng nằm trong `k8s/kind-config.yaml`. Nếu cần tạo lại trên máy này:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\setup-kubernetes-windows.ps1
```

Kubernetes app dùng chung PostgreSQL Compose đang có; Secret được tạo tự động từ file `.env` local và không commit lên Git. Database chỉ kết nối qua mạng Docker nội bộ, cổng host `5432` vẫn bind vào `127.0.0.1`. Không xóa cluster nếu muốn giữ workload của Kubernetes.

Khi Jenkins job `giai-dau-ci` nhận Jenkinsfile mới, chọn `DEPLOY_TARGET=kubernetes` để deploy. App Compose hiện tại tiếp tục ở `http://localhost:8000`; app Kubernetes ở `http://localhost:8002`. Kubernetes mặc định dùng namespace `giai-dau`, Deployment `giai-dau-app`, container `app`.

Thư mục deploy mặc định là `%USERPROFILE%\Downloads\cuoikytkpm-main\cuoikytkpm-main`, nơi chứa `.env` local. Nếu repo nằm ở chỗ khác, đặt tham số job `DEPLOY_DIR` thành thư mục có `.env`.

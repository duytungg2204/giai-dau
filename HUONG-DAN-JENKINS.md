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

Pipeline chạy `npm ci`, `npm run check`, build Docker image theo commit rồi deploy ứng dụng bằng Compose. Nếu validate hoặc build lỗi, bước deploy không chạy và container hiện tại tiếp tục phục vụ. Nếu container mới không trả HTTP 200 ở `/api/bootstrap-status`, pipeline khôi phục image trước đó và kiểm tra lại app. PostgreSQL và volume dữ liệu không bị thay đổi.

Thư mục deploy mặc định là `%USERPROFILE%\Downloads\cuoikytkpm-main\cuoikytkpm-main`, nơi chứa `.env` local. Nếu repo nằm ở chỗ khác, đặt tham số job `DEPLOY_DIR` thành thư mục có `.env`.

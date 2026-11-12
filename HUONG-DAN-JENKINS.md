# Jenkins CI/CD

Jenkins chạy native trên Windows, không chạy trong Docker. Ứng dụng và PostgreSQL tiếp tục chạy trong Docker Compose. Jenkins chạy dưới tài khoản Windows hiện tại để dùng Docker Desktop, Git và Node.js.

## Đăng nhập Jenkins lần đầu

Mở http://localhost:8081. Mật khẩu mở khóa ban đầu nằm trong:

```text
%USERPROFILE%\.jenkins-home\secrets\initialAdminPassword
```

Chọn **Install suggested plugins**, tạo tài khoản quản trị, rồi đăng nhập. Jenkins dùng cổng 8081.

Jenkins được cài ở `%LOCALAPPDATA%\Programs\JenkinsRuntime`; nếu đã dừng, chạy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\start-jenkins-windows.ps1
```

## Cho Jenkins quyền đọc repo private

Repo `duytungg2204/giai-dau` là private. Tạo GitHub token chỉ có quyền đọc nội dung repo, rồi trong Jenkins mở **Manage Jenkins → Credentials → System → Global credentials → Add Credentials**:

- Kind: **Username with password**
- Username: `duytungg2204`
- Password: GitHub token
- ID: `github-read`

Token chỉ lưu trong Jenkins Credentials, không đưa vào source code hoặc `.env`.

## Tạo pipeline theo dõi `main`

1. Chọn **New Item**, đặt tên `giai-dau-ci`, chọn **Pipeline**.
2. Ở **Pipeline**, chọn **Pipeline script from SCM**.
3. SCM: **Git**; Repository URL: `https://github.com/duytungg2204/giai-dau.git`; Credentials: `github-read`.
4. Branch Specifier: `*/main`; Script Path: `Jenkinsfile`; lưu job.
5. Chạy **Build Now** một lần để Jenkins đọc trigger trong Jenkinsfile.

Jenkins poll GitHub mỗi phút vì Jenkins đang chạy trên localhost, không nhận được webhook trực tiếp từ GitHub. Commit mới trên `main` sẽ tự kích hoạt pipeline.

## Build, deploy và rollback

Pipeline chạy `npm ci`, `npm run check`, build Docker image theo commit rồi deploy ứng dụng bằng Compose. Nếu validate hoặc build lỗi, bước deploy không chạy và container hiện tại vẫn tiếp tục phục vụ. Nếu container mới không trả HTTP 200 ở `/api/bootstrap-status`, pipeline khôi phục image trước đó và kiểm tra lại app. PostgreSQL và volume dữ liệu không bị thay đổi.

Thư mục deploy mặc định là `%USERPROFILE%\Downloads\cuoikytkpm-main\cuoikytkpm-main`, nơi chứa `.env` local. Nếu repo nằm ở chỗ khác, đặt tham số job `DEPLOY_DIR` thành thư mục có `.env`.

Image Docker Hub là tùy chọn riêng; cấu hình Jenkins credential/registry nếu cần publish image ra ngoài máy này.

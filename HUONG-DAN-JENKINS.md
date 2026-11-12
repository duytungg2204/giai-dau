# Jenkins CI/CD

Jenkins chạy native trên Windows, không chạy trong Docker. Ứng dụng và PostgreSQL vẫn chạy bằng Docker Compose. Agent Jenkins cần Git, Node.js 22+, Docker Desktop CLI và quyền dùng Docker Desktop của tài khoản đang đăng nhập.

## Chạy Jenkins trên máy Windows này

Java 21 và Jenkins LTS được cài ở `%LOCALAPPDATA%\Programs\JenkinsRuntime`; Jenkins home nằm tại `%USERPROFILE%\.jenkins-home`. Chạy PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\start-jenkins-windows.ps1
```

Mở http://localhost:8081. Lần đầu, nhập mật khẩu từ `%USERPROFILE%\.jenkins-home\secrets\initialAdminPassword`, cài Suggested Plugins, rồi tạo tài khoản quản trị. Jenkins chạy dưới tài khoản Windows hiện tại, không phải Docker container hay LocalSystem service.

## Cấu hình job

Tạo Pipeline job, trỏ tới repository Git và chọn `Jenkinsfile`. Có thể bật GitHub webhook hoặc polling SCM theo cấu hình job. Pipeline chạy `npm ci`, `npm run check`, rồi build image bằng Docker CLI trên nhánh `main`.

Để đẩy image Docker Hub, thêm Jenkins username/password credential có ID `hubdocker`, rồi cấu hình tham số `DOCKERHUB_REPO` theo dạng `username/repository`. `IMAGE_TAG` mặc định là `latest`.

Pipeline không cài hoặc gọi Jenkins Docker Pipeline plugin. Không cần Docker-in-Docker. Deploy ứng dụng lên máy đích bằng `docker compose up -d --build`; pipeline không chứa đường dẫn Windows gắn cứng của một máy cụ thể.

## Khởi chạy ứng dụng

Xem [HUONG-DAN-DOCKER.md](HUONG-DAN-DOCKER.md) để cấu hình `.env` và khởi chạy ứng dụng cùng PostgreSQL.

# Jenkins CI/CD

Jenkins chạy cài trực tiếp trên Windows, không chạy trong Docker. Ứng dụng và PostgreSQL vẫn chạy bằng Docker Compose. Agent Jenkins cần cài Git, Node.js 22+, Docker Desktop CLI và được phép dùng Docker Desktop của tài khoản chạy agent.

## Cấu hình job

Tạo Pipeline job, trỏ tới repository Git và chọn `Jenkinsfile`. Có thể bật GitHub webhook hoặc polling SCM theo cấu hình job. Pipeline chạy `npm ci`, `npm run check`, rồi build image bằng Docker CLI trên nhánh `main`.

Để đẩy image Docker Hub, thêm Jenkins username/password credential có ID `hubdocker`, rồi cấu hình tham số `DOCKERHUB_REPO` theo dạng `username/repository`. `IMAGE_TAG` mặc định là `latest`.

Pipeline không cài hoặc gọi Jenkins Docker Pipeline plugin. Không cần Docker-in-Docker. Deploy ứng dụng lên máy đích bằng `docker compose up -d --build`; pipeline không chứa đường dẫn Windows gắn cứng của một máy cụ thể.

## Khởi chạy ứng dụng

Xem [HUONG-DAN-DOCKER.md](HUONG-DAN-DOCKER.md) để cấu hình `.env` và khởi chạy ứng dụng cùng PostgreSQL.

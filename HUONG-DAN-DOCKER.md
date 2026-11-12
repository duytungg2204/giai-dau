# Chạy ứng dụng bằng Docker

Yêu cầu Docker Desktop đang chạy.

## Khởi chạy

PowerShell tại thư mục dự án:

```powershell
Copy-Item .env.example .env
notepad .env
```

Đổi `POSTGRES_PASSWORD` thành mật khẩu riêng và đặt `POSTGRES_PASSWORD_URL_ENCODED` thành dạng URL-encoded của cùng mật khẩu (ký tự như `@`, `:`, `/` cần mã hóa). Sau đó chạy:

```powershell
docker compose up -d --build
docker compose ps
```

Mở http://localhost:8000/giai-dau.html. PostgreSQL lưu dữ liệu trong volume `postgres_data`; cổng database chỉ mở trên máy local.

## Quản lý

```powershell
docker compose logs -f app
docker compose down
```

`docker compose down -v` sẽ xóa cả dữ liệu PostgreSQL.

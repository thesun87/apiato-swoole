# Apiato + Laravel Octane (Swoole)

Dự án API framework xây dựng trên [Apiato](https://apiato.io) (Porto SAP pattern) chạy với Laravel Octane + Swoole extension. Không cần cài PHP trên máy local — toàn bộ chạy qua Docker.

**Stack:**
- PHP 8.3 + Swoole extension
- Apiato 13.x (Porto architecture)
- Laravel Octane 2.x
- PostgreSQL 16
- Redis 7 (cache + queue + session)
- Laravel Passport (OAuth2)
- Supervisor (process manager)

---

## Yêu cầu

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (hoặc Docker Engine + Compose plugin)
- Không cần PHP, Composer, hay bất kỳ tool nào khác trên máy host

---

## Setup lần đầu

### 1. Clone repo và vào thư mục `src/`

```bash
git clone <repo-url>
cd apiato-swoole
```

### 2. Copy file `.env`

```bash
cp src/.env.example src/.env
```

### 3. Build và khởi động containers

```bash
docker compose up -d --build
```

Lần đầu build mất khoảng 5–10 phút (compile Swoole extension).

### 4. Generate App Key

```bash
docker compose exec app php artisan key:generate
```

### 5. Chạy migrations và seed data

```bash
docker compose exec app php artisan migrate
docker compose exec app php artisan db:seed
```

Seed tạo tài khoản admin mặc định:
- Email: `admin@admin.com`
- Password: `admin`

### 6. Cài Passport keys và tạo OAuth client

```bash
docker compose exec app php artisan passport:install
docker compose exec app php artisan passport:client --password --name="Web Client" --provider=users --no-interaction
```

Lấy `Client ID` và `Client Secret` từ output, cập nhật vào `src/.env`:

```dotenv
CLIENT_WEB_ID=<uuid từ output>
CLIENT_WEB_SECRET=<secret từ output>
```

Sau đó reload Octane:

```bash
docker compose exec app php artisan octane:reload
```

---

## Kiểm tra hoạt động

### API đang chạy

```bash
curl -I http://localhost:8000/v1 -H "Host: localhost"
```

Phải thấy header `Server: swoole-http-server` — xác nhận Swoole đang serve, không phải php-fpm.

### Đăng nhập lấy token

```bash
curl -X POST http://localhost:8000/v1/clients/web/login \
  -H "Content-Type: application/json" \
  -H "Host: localhost" \
  -d '{"email":"admin@admin.com","password":"admin"}'
```

Response trả về `access_token` và `refresh_token`.

### Gọi endpoint có xác thực

```bash
curl http://localhost:8000/v1/profile \
  -H "Authorization: Bearer <access_token>" \
  -H "Host: localhost" \
  -H "Accept: application/json"
```

### Hello endpoint (Porto demo)

```bash
curl http://localhost:8000/v1/hello -H "Host: localhost"
# {"message":"Hello from Apiato + Swoole!"}
```

---

## Lưu ý quan trọng về routing

Apiato dùng **domain-based routing**. Biến `API_URL` trong `.env` phải là hostname không có port:

```dotenv
# ĐÚNG
API_URL=http://localhost

# SAI — routes sẽ trả về 404
API_URL=http://localhost:8000
```

Khi gọi API từ bên ngoài container (curl, Postman, browser), thêm header:

```
Host: localhost
```

Hoặc dùng Postman với URL `http://localhost:8000/v1/...` và thêm Header `Host: localhost`.

---

## Các lệnh hay dùng

```bash
# Khởi động tất cả services
docker compose up -d

# Rebuild image (sau khi thay đổi Dockerfile)
docker compose up -d --build app

# Chạy artisan commands
docker compose exec app php artisan <command>

# Reload Octane workers (sau khi thêm routes/code mới)
docker compose exec app php artisan octane:reload

# Xem logs Octane
docker compose exec app tail -f /var/log/supervisor/octane.log

# Xem logs queue worker
docker compose exec app tail -f /var/log/supervisor/queue.log

# Kiểm tra trạng thái supervisor (octane + queue workers)
docker compose exec app supervisorctl status

# Vào shell container
docker compose exec app bash

# Dừng tất cả
docker compose down

# Dừng và xóa volumes (reset database)
docker compose down -v
```

---

## Cấu trúc Porto Architecture

```
src/app/
├── Ship/                          # Shared infrastructure (base classes, configs, kernel)
│   ├── Configs/
│   ├── Parents/
│   │   ├── Actions/
│   │   ├── Controllers/
│   │   ├── Models/
│   │   └── ...
│   └── ...
└── Containers/
    └── AppSection/
        ├── Authentication/        # Login, logout, register, refresh token
        ├── Authorization/         # Roles & permissions
        ├── User/                  # User profile, CRUD
        └── Hello/                 # Demo container (Porto pattern example)
            ├── Actions/
            │   └── GetHelloAction.php
            └── UI/
                └── API/
                    ├── Controllers/
                    │   └── GetHelloController.php
                    └── Routes/
                        └── GetHello.v1.public.php
```

### Tạo Container mới

Một Container = một domain. Cấu trúc tối thiểu:

```
app/Containers/<Section>/<ContainerName>/
├── Actions/
│   └── <UseCaseName>Action.php
└── UI/
    └── API/
        ├── Controllers/
        │   └── <UseCaseName>Controller.php
        └── Routes/
            └── <UseCaseName>.v1.public.php   # public route (không cần auth)
            └── <UseCaseName>.v1.private.php  # private route (cần auth:api)
```

Route file naming convention:
- `.v1.public.php` — không cần authentication
- `.v1.private.php` — cần `auth:api` middleware

---

## Services và ports

| Service    | Container       | Port host | Port container |
|------------|-----------------|-----------|----------------|
| App (Octane) | `apiato_app`   | 8000      | 8000           |
| PostgreSQL | `apiato_postgres` | 5432    | 5432           |
| Redis      | `apiato_redis`  | 6379      | 6379           |

### Kết nối database từ host

```
Host: localhost
Port: 5432
Database: apiato
Username: apiato
Password: secret
```

---

## Troubleshooting

| Vấn đề | Nguyên nhân | Cách fix |
|--------|-------------|----------|
| 404 trên mọi route | `API_URL` có port | Đổi thành `API_URL=http://localhost` |
| Octane crash khi start | APP_KEY trống | Chạy `php artisan key:generate` |
| Port 8000 already in use | Swoole process cũ còn giữ port | `docker compose restart app` |
| DB connection refused | Postgres chưa healthy | Đợi hoặc kiểm tra `docker compose ps` |
| Routes không update | Octane cache route cũ | `php artisan octane:reload` |
| Passport 401 | CLIENT_WEB_ID/SECRET sai | Chạy lại `passport:client` và update `.env` |

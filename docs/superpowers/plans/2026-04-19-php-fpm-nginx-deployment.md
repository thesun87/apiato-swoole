# PHP-FPM + Nginx Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tạo bộ Docker độc lập hoàn toàn để deploy ứng dụng Apiato/Laravel bằng PHP-FPM + Nginx, tách biệt hoàn toàn với setup Swoole/Octane hiện tại — file Dockerfile riêng, docker-compose riêng, không chia sẻ bất kỳ config nào.

**Architecture:** Tạo thư mục `docker-fpm/` chứa toàn bộ config của stack FPM: PHP-FPM image, Nginx image, supervisord. File `docker-compose.fpm.yml` ở root project quản lý stack độc lập với các services: `app` (PHP-FPM + queue workers), `nginx`, `postgres`, `redis`. Stack Swoole giữ nguyên 100%, không đụng vào.

**Tech Stack:** PHP 8.3-FPM, Nginx 1.25-alpine, Docker Compose (file riêng), Supervisor (FPM + queue workers), Laravel (không cần Octane)

---

## File Structure

### Files to Create (tất cả đều mới, không đụng vào `docker/`)
```
docker-fpm/
├── php/
│   ├── Dockerfile          — PHP 8.3-FPM image với extensions đầy đủ
│   ├── php-fpm.conf        — FPM pool config (www pool, port 9000)
│   ├── php.ini             — PHP runtime settings với opcache
│   └── supervisord.conf    — Supervisor: chạy php-fpm + queue workers
└── nginx/
    ├── Dockerfile          — Nginx 1.25-alpine image
    ├── nginx.conf          — Main nginx config
    └── conf.d/
        └── default.conf    — Server block Laravel (FastCGI → app:9000)

docker-compose.fpm.yml      — Stack FPM hoàn toàn độc lập ở root project
```

### Files NOT to touch
- `docker/` — giữ nguyên (Swoole stack)
- `docker-compose.yml` — giữ nguyên (Swoole stack)
- `src/` — code Laravel không thay đổi

---

## Task 1: Tạo PHP-FPM Dockerfile

**Files:**
- Create: `docker-fpm/php/Dockerfile`

- [ ] **Step 1: Tạo thư mục và Dockerfile**

```dockerfile
FROM php:8.3-fpm

RUN apt-get update && apt-get install -y \
    git curl zip unzip libzip-dev libpq-dev \
    libonig-dev libxml2-dev supervisor \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install \
    pdo pdo_pgsql pgsql \
    bcmath mbstring opcache zip

RUN pecl install redis \
    && docker-php-ext-enable redis

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

COPY docker-fpm/php/php.ini /usr/local/etc/php/conf.d/custom.ini
COPY docker-fpm/php/php-fpm.conf /usr/local/etc/php-fpm.d/www.conf
COPY docker-fpm/php/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN mkdir -p /var/log/supervisor /var/log/php-fpm

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

- [ ] **Step 2: Verify**

```bash
ls docker-fpm/php/Dockerfile
```

Expected: `docker-fpm/php/Dockerfile`

---

## Task 2: Tạo PHP-FPM pool config

**Files:**
- Create: `docker-fpm/php/php-fpm.conf`

- [ ] **Step 1: Tạo www pool config**

```ini
[www]
user = www-data
group = www-data

; TCP socket — Nginx kết nối qua Docker network tới service name "app"
listen = 0.0.0.0:9000

; Dynamic: tự scale từ 4 lên 20 processes theo tải
pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 6
pm.max_requests = 500

; Logging
access.log = /var/log/php-fpm/access.log
php_admin_value[error_log] = /var/log/php-fpm/error.log
php_admin_flag[log_errors] = on

; Truyền ENV vars từ Docker vào PHP process
clear_env = no
```

- [ ] **Step 2: Verify**

```bash
ls docker-fpm/php/php-fpm.conf
```

Expected: `docker-fpm/php/php-fpm.conf`

---

## Task 3: Tạo PHP ini

**Files:**
- Create: `docker-fpm/php/php.ini`

- [ ] **Step 1: Tạo php.ini với opcache**

```ini
; Memory & execution
memory_limit = 256M
max_execution_time = 60
max_input_time = 60

; Upload
upload_max_filesize = 20M
post_max_size = 20M

; Error (production-safe)
display_errors = Off
log_errors = On
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT

; Opcache — bắt buộc cho FPM để đạt performance
opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.validate_timestamps = 1
opcache.revalidate_freq = 2
opcache.fast_shutdown = 1

date.timezone = UTC
```

- [ ] **Step 2: Verify**

```bash
ls docker-fpm/php/php.ini
```

Expected: `docker-fpm/php/php.ini`

---

## Task 4: Tạo Supervisor config

**Files:**
- Create: `docker-fpm/php/supervisord.conf`

Container PHP dùng supervisord để quản lý 2 loại process trong 1 container: php-fpm (application server) và queue workers (background jobs).

- [ ] **Step 1: Tạo supervisord.conf**

```ini
[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[program:php-fpm]
process_name=%(program_name)s
command=php-fpm --nodaemonize
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/supervisor/php-fpm.log
stdout_logfile_maxbytes=10MB

[program:queue-worker]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/html/artisan queue:work redis --sleep=3 --tries=3 --max-time=3600
numprocs=2
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/supervisor/queue.log
stdout_logfile_maxbytes=10MB
```

- [ ] **Step 2: Verify**

```bash
ls docker-fpm/php/supervisord.conf
```

Expected: `docker-fpm/php/supervisord.conf`

---

## Task 5: Tạo Nginx config

**Files:**
- Create: `docker-fpm/nginx/nginx.conf`
- Create: `docker-fpm/nginx/conf.d/default.conf`

- [ ] **Step 1: Tạo main nginx.conf**

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    include /etc/nginx/conf.d/*.conf;
}
```

- [ ] **Step 2: Tạo server block**

`fastcgi_pass app:9000` — `app` là tên service trong `docker-compose.fpm.yml`.

```nginx
server {
    listen 80;
    server_name _;
    root /var/www/html/public;
    index index.php;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    # Static files served by Nginx directly, không qua PHP
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass app:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_read_timeout 60;
        fastcgi_connect_timeout 10;
        fastcgi_buffer_size 128k;
        fastcgi_buffers 4 256k;
    }

    location ~ /\. {
        deny all;
    }

    location ~ ^/(storage|bootstrap/cache) {
        deny all;
    }
}
```

- [ ] **Step 3: Verify**

```bash
ls docker-fpm/nginx/nginx.conf docker-fpm/nginx/conf.d/default.conf
```

Expected: cả 2 file tồn tại

---

## Task 6: Tạo Nginx Dockerfile

**Files:**
- Create: `docker-fpm/nginx/Dockerfile`

Build context trong `docker-compose.fpm.yml` là root project (`.`), nên COPY path là `docker-fpm/nginx/...`.

- [ ] **Step 1: Tạo Nginx Dockerfile**

```dockerfile
FROM nginx:1.25-alpine

RUN rm /etc/nginx/conf.d/default.conf

COPY docker-fpm/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker-fpm/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
```

- [ ] **Step 2: Verify**

```bash
ls docker-fpm/nginx/Dockerfile
```

Expected: `docker-fpm/nginx/Dockerfile`

---

## Task 7: Tạo docker-compose.fpm.yml

**Files:**
- Create: `docker-compose.fpm.yml`

File này hoàn toàn độc lập. Không import, extend, hay reference bất cứ thứ gì từ `docker-compose.yml`.

- [ ] **Step 1: Tạo docker-compose.fpm.yml**

```yaml
version: '3.9'

services:
  app:
    build:
      context: .
      dockerfile: docker-fpm/php/Dockerfile
    image: apiato-fpm-app
    container_name: apiato_fpm_app
    restart: unless-stopped
    volumes:
      - ./src:/var/www/html
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - apiato_fpm_net
    environment:
      - APP_ENV=${APP_ENV:-production}

  nginx:
    build:
      context: .
      dockerfile: docker-fpm/nginx/Dockerfile
    image: apiato-fpm-nginx
    container_name: apiato_fpm_nginx
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./src:/var/www/html:ro
    depends_on:
      - app
    networks:
      - apiato_fpm_net

  postgres:
    image: postgres:16-alpine
    container_name: apiato_fpm_postgres
    restart: unless-stopped
    ports:
      - "5433:5432"
    environment:
      POSTGRES_DB: "${DB_DATABASE:-apiato}"
      POSTGRES_USER: "${DB_USERNAME:-apiato}"
      POSTGRES_PASSWORD: "${DB_PASSWORD:-secret}"
    volumes:
      - fpm_postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USERNAME:-apiato}"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - apiato_fpm_net

  redis:
    image: redis:7-alpine
    container_name: apiato_fpm_redis
    restart: unless-stopped
    ports:
      - "6380:6379"
    volumes:
      - fpm_redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - apiato_fpm_net

volumes:
  fpm_postgres_data:
  fpm_redis_data:

networks:
  apiato_fpm_net:
    driver: bridge
```

**Lý do port khác:**
- Nginx: `8080:80` (Swoole dùng `8000`)
- Postgres: `5433:5432` (Swoole dùng `5432`)
- Redis: `6380:6379` (Swoole dùng `6379`)
- Container names đều có prefix `apiato_fpm_` để tránh xung đột khi cả 2 stack chạy đồng thời
- Named volumes `fpm_postgres_data`, `fpm_redis_data` — tách biệt data với stack Swoole

- [ ] **Step 2: Verify syntax**

```bash
docker compose -f docker-compose.fpm.yml config --quiet && echo "OK"
```

Expected: `OK`

- [ ] **Step 3: Commit toàn bộ FPM stack**

```bash
git add docker-fpm/ docker-compose.fpm.yml
git commit -m "feat: add standalone PHP-FPM + Nginx deployment stack"
```

---

## Task 8: Smoke test FPM stack

**Files:** (không tạo file mới)

- [ ] **Step 1: Build**

```bash
docker compose -f docker-compose.fpm.yml build
```

Expected: Build thành công `apiato-fpm-app` và `apiato-fpm-nginx`, không có lỗi

- [ ] **Step 2: Start stack**

```bash
docker compose -f docker-compose.fpm.yml up -d
```

Expected: 4 containers running:
- `apiato_fpm_app`
- `apiato_fpm_nginx`
- `apiato_fpm_postgres`
- `apiato_fpm_redis`

- [ ] **Step 3: Chạy migrations**

```bash
docker compose -f docker-compose.fpm.yml exec app php artisan migrate --force
```

Expected: `Migration table created successfully` hoặc `Nothing to migrate`

- [ ] **Step 4: Test HTTP qua Nginx**

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api
```

Expected: `200` hoặc `401` (Laravel đang chạy, không phải 502)

- [ ] **Step 5: Kiểm tra logs nếu có lỗi**

```bash
docker compose -f docker-compose.fpm.yml logs app --tail=50
docker compose -f docker-compose.fpm.yml logs nginx --tail=50
```

Expected: Không có PHP fatal error, không có `upstream connect error` trong Nginx

- [ ] **Step 6: Stop stack**

```bash
docker compose -f docker-compose.fpm.yml down
```

---

## Task 9: Cập nhật README

**Files:**
- Modify: `README.md` (ở root project)

- [ ] **Step 1: Kiểm tra README**

```bash
ls README.md
```

- [ ] **Step 2: Thêm section vào README**

Thêm section sau vào cuối README (hoặc sau phần "Getting Started"):

```markdown
## PHP-FPM + Nginx Stack (Alternative Deployment)

Stack độc lập hoàn toàn với Swoole. Dùng PHP-FPM làm application server và Nginx làm web server.

### Cấu trúc

```
docker-fpm/        # Tất cả config của stack FPM
docker-compose.fpm.yml  # File compose độc lập
```

### Khởi động

```bash
# Build và start
docker compose -f docker-compose.fpm.yml up -d --build

# Migrations (lần đầu)
docker compose -f docker-compose.fpm.yml exec app php artisan migrate

# Passport setup (lần đầu)
docker compose -f docker-compose.fpm.yml exec app php artisan passport:install

# Stop
docker compose -f docker-compose.fpm.yml down
```

### Ports

| Service  | Port  |
|----------|-------|
| Nginx    | 8080  |
| Postgres | 5433  |
| Redis    | 6380  |

Ports khác với Swoole stack để có thể chạy song song nếu cần.

### So sánh với Swoole

| | Swoole (docker-compose.yml) | PHP-FPM (docker-compose.fpm.yml) |
|---|---|---|
| Entry point | `docker compose up` | `docker compose -f docker-compose.fpm.yml up` |
| PHP server | Laravel Octane + Swoole | PHP-FPM |
| Web server | Built-in Octane (port 8000) | Nginx (port 8080) |
| Config dir | `docker/` | `docker-fpm/` |
| Data volumes | `postgres_data`, `redis_data` | `fpm_postgres_data`, `fpm_redis_data` |
```

- [ ] **Step 3: Commit README**

```bash
git add README.md
git commit -m "docs: add PHP-FPM + Nginx stack documentation to README"
```

---

## Self-Review

### Spec coverage
- [x] PHP-FPM Dockerfile riêng trong `docker-fpm/php/` → Task 1
- [x] FPM pool config → Task 2
- [x] PHP ini với opcache → Task 3
- [x] Supervisor quản lý FPM + queue workers → Task 4
- [x] Nginx main config → Task 5
- [x] Nginx server block (FastCGI `app:9000`) → Task 5
- [x] Nginx Dockerfile riêng trong `docker-fpm/nginx/` → Task 6
- [x] `docker-compose.fpm.yml` độc lập hoàn toàn → Task 7
- [x] Container names và volumes có prefix riêng (`apiato_fpm_`, `fpm_`) → Task 7
- [x] Smoke test → Task 8
- [x] Documentation → Task 9
- [x] Stack Swoole không bị đụng chạm

### Placeholder scan
- Không có TBD/TODO
- Tất cả code blocks đầy đủ nội dung
- Tất cả commands có expected output

### Type/name consistency
- `fastcgi_pass app:9000` trong Nginx conf → khớp với service name `app` trong `docker-compose.fpm.yml`
- Port `9000` nhất quán giữa `php-fpm.conf` (`listen = 0.0.0.0:9000`) và Nginx conf
- Build context `.` trong compose → COPY paths trong Dockerfile dùng `docker-fpm/php/` và `docker-fpm/nginx/` đúng
- Container prefix `apiato_fpm_` nhất quán cho tất cả containers
- Volume prefix `fpm_` nhất quán cho postgres và redis volumes

### Isolation đảm bảo
- `docker/` và `docker-compose.yml` (Swoole) → không đụng vào
- Network riêng `apiato_fpm_net` (Swoole dùng `apiato_net`)
- Ports khác nhau hoàn toàn (8080, 5433, 6380 vs 8000, 5432, 6379)
- Named volumes khác nhau hoàn toàn

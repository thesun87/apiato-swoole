# Apiato + Laravel Octane (Swoole) + Docker Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap an Apiato 13.x project running on Laravel Octane with Swoole inside Docker, using PostgreSQL as the database, Redis for cache and queues, and Laravel Passport for authentication — with zero PHP installed on the host machine.

**Architecture:** Apiato follows the Porto SAP pattern layered on top of Laravel. The codebase is split into a **Ship** layer (shared infrastructure) and **Containers** (domain modules). We run this inside Docker using a custom PHP 8.3 + Swoole image, Laravel Octane as the HTTP server, and Supervisor to manage the Octane worker and queue worker processes.

**Tech Stack:** PHP 8.3, Apiato 13.x, Laravel Octane 2.x, Swoole extension, PostgreSQL 16, Redis 7, Laravel Passport, Docker Compose, Supervisor

---

## Apiato Framework — Quick Reference

Before implementing, understand these key concepts:

| Layer | Location | Purpose |
|-------|----------|---------|
| **Ship** | `app/Ship/` | Shared base classes, middleware, configs, kernel |
| **Container** | `app/Containers/<Section>/<Name>/` | One business domain (e.g., `AppSection/User`) |
| **Action** | `<Container>/Actions/` | One use-case per class (e.g., `CreateUserAction`) |
| **Task** | `<Container>/Tasks/` | Reusable business logic shared across Actions |
| **Repository** | `<Container>/Data/Repositories/` | Data access layer (extends Apiato's `Repository`) |
| **Model** | `<Container>/Models/` | Eloquent model |
| **Controller** | `<Container>/UI/API/Controllers/` | Thin — calls one Action, returns Transformer |
| **Request** | `<Container>/UI/API/Requests/` | Validation + authorization rules |
| **Transformer** | `<Container>/UI/API/Transformers/` | Formats the JSON response |
| **Route** | `<Container>/UI/API/Routes/` | One file per endpoint |

---

## File Structure

```
apiato-swoole/
├── docker/
│   ├── php/
│   │   ├── Dockerfile              # PHP 8.3 + Swoole image
│   │   └── supervisord.conf        # Octane + queue worker
│   └── nginx/                      # (not used — Octane serves directly)
├── docker-compose.yml              # app, postgres, redis services
├── docker-compose.override.yml     # dev overrides (volume mounts, ports)
├── .env.example                    # env template
└── (Laravel/Apiato source)         # created by composer in Task 1
```

---

## Task 1: Create the Apiato Project via Docker

**Goal:** Use a temporary Docker container to run `composer create-project` so no PHP is needed on the host.

**Files:**
- Create: `docker-compose.yml`
- Create: `.env.example`

- [ ] **Step 1: Create the project directory and enter it**

```bash
mkdir apiato-swoole && cd apiato-swoole
```

- [ ] **Step 2: Run `composer create-project` inside a temporary PHP container**

```bash
docker run --rm \
  -v "$(pwd):/app" \
  -w /app \
  composer:2 \
  create-project apiato/apiato . --prefer-dist --no-interaction
```

Expected output: Composer downloads Apiato and all dependencies into the current directory. You should see `app/`, `bootstrap/`, `config/`, `routes/`, etc. created.

- [ ] **Step 3: Set correct file permissions**

```bash
sudo chown -R $USER:$USER .
chmod -R 775 storage bootstrap/cache
```

On Windows (WSL2 or Git Bash), skip chown and just set permissions:
```bash
chmod -R 775 storage bootstrap/cache
```

- [ ] **Step 4: Copy `.env.example` to `.env`**

```bash
cp .env .env.example
```

> Note: Apiato ships with a `.env` pre-configured. We copy it to `.env.example` for version control and will edit `.env` in Task 3.

- [ ] **Step 5: Commit**

```bash
git init
git add .
git commit -m "feat: initial Apiato project scaffold"
```

---

## Task 2: Create the PHP + Swoole Docker Image

**Goal:** Build a custom PHP 8.3 image with the Swoole extension and all required PHP extensions.

**Files:**
- Create: `docker/php/Dockerfile`
- Create: `docker/php/supervisord.conf`

- [ ] **Step 1: Create `docker/php/Dockerfile`**

```dockerfile
FROM php:8.3-cli

# System dependencies
RUN apt-get update && apt-get install -y \
    git curl zip unzip libzip-dev libpq-dev libssl-dev \
    libonig-dev libxml2-dev libbrotli-dev \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions
RUN docker-php-ext-install \
    pdo pdo_pgsql pgsql \
    bcmath mbstring opcache zip pcntl

# Redis extension
RUN pecl install redis \
    && docker-php-ext-enable redis

# Swoole extension (with OpenSSL + brotli + async DNS)
RUN pecl install swoole \
    && docker-php-ext-enable swoole

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Supervisor
RUN apt-get update && apt-get install -y supervisor \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

# Copy supervisor config
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

- [ ] **Step 2: Create `docker/php/supervisord.conf`**

```ini
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:octane]
process_name=%(program_name)s
command=php /var/www/html/artisan octane:start --server=swoole --host=0.0.0.0 --port=8000 --workers=4
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/supervisor/octane.log
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

- [ ] **Step 3: Commit**

```bash
git add docker/
git commit -m "feat: add PHP 8.3 + Swoole Docker image with Supervisor"
```

---

## Task 3: Create Docker Compose Configuration

**Goal:** Define all services (app, postgres, redis) and wire them together.

**Files:**
- Create: `docker-compose.yml`
- Create: `docker-compose.override.yml`
- Modify: `.env`

- [ ] **Step 1: Create `docker-compose.yml`**

```yaml
version: '3.9'

services:
  app:
    build:
      context: .
      dockerfile: docker/php/Dockerfile
    image: apiato-swoole-app
    container_name: apiato_app
    restart: unless-stopped
    ports:
      - "8000:8000"
    volumes:
      - .:/var/www/html
    environment:
      APP_ENV: "${APP_ENV:-local}"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - apiato_net

  postgres:
    image: postgres:16-alpine
    container_name: apiato_postgres
    restart: unless-stopped
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: "${DB_DATABASE:-apiato}"
      POSTGRES_USER: "${DB_USERNAME:-apiato}"
      POSTGRES_PASSWORD: "${DB_PASSWORD:-secret}"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USERNAME:-apiato}"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - apiato_net

  redis:
    image: redis:7-alpine
    container_name: apiato_redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - apiato_net

volumes:
  postgres_data:
  redis_data:

networks:
  apiato_net:
    driver: bridge
```

- [ ] **Step 2: Update `.env` for Docker services**

Edit `.env` and set the following values (replace what Apiato generated):

```dotenv
APP_NAME=Apiato
APP_ENV=local
APP_KEY=                        # will be generated in Task 5
APP_DEBUG=true
APP_URL=http://localhost:8000

# API
API_RATE_LIMIT_ENABLED=false

# Database — PostgreSQL
DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_DATABASE=apiato
DB_USERNAME=apiato
DB_PASSWORD=secret

# Cache
CACHE_DRIVER=redis
CACHE_STORE=redis

# Queue
QUEUE_CONNECTION=redis

# Redis
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=6379

# Session
SESSION_DRIVER=redis

# Broadcast
BROADCAST_CONNECTION=log

# Passport
CLIENT_WEB_ID=2
CLIENT_WEB_SECRET=              # set after passport:install in Task 6
```

- [ ] **Step 3: Update `config/database.php` to ensure pgsql is the default**

Open `config/database.php` and verify:
```php
'default' => env('DB_CONNECTION', 'pgsql'),
```

If it says `'mysql'`, change it to `'pgsql'`.

- [ ] **Step 4: Commit**

```bash
git add docker-compose.yml .env.example docker/
git commit -m "feat: add Docker Compose with postgres and redis services"
```

---

## Task 4: Install Laravel Octane + Swoole

**Goal:** Add Octane to the project and configure it for Swoole.

**Files:**
- Modify: `composer.json`
- Create: `config/octane.php` (auto-generated)

- [ ] **Step 1: Install Octane via Composer inside the running container**

First, build and start the containers:
```bash
docker compose up -d --build
```

Then exec into the app container:
```bash
docker compose exec app bash
```

Inside the container, install Octane:
```bash
composer require laravel/octane
```

Expected: Octane package downloaded, no errors.

- [ ] **Step 2: Publish Octane config**

Still inside the container:
```bash
php artisan octane:install --server=swoole
```

Expected output:
```
Swoole extension is installed.
INFO  Octane installed successfully.
```

This creates `config/octane.php`.

- [ ] **Step 3: Verify `config/octane.php` has Swoole as the server**

The file should contain:
```php
'server' => env('OCTANE_SERVER', 'swoole'),
```

If it shows `'roadrunner'`, change to `'swoole'`.

- [ ] **Step 4: Exit the container and commit**

```bash
exit
git add composer.json composer.lock config/octane.php
git commit -m "feat: install Laravel Octane with Swoole server"
```

---

## Task 5: Generate App Key and Run Migrations

**Goal:** Generate the application key and run the initial database migrations.

- [ ] **Step 1: Generate app key inside the container**

```bash
docker compose exec app php artisan key:generate
```

Expected output:
```
INFO  Application key set successfully.
```

Your `.env` `APP_KEY` should now be populated.

- [ ] **Step 2: Run migrations**

```bash
docker compose exec app php artisan migrate
```

Expected output:
```
INFO  Running migrations.
  ✓ 0001_01_01_000000_create_users_table
  ✓ 0001_01_01_000001_create_cache_table
  ✓ 0001_01_01_000002_create_jobs_table
  ...
```

- [ ] **Step 3: Run database seeder**

```bash
docker compose exec app php artisan db:seed
```

Expected: Seeds run, default admin created (email: `admin@admin.com`, password: `admin`).

- [ ] **Step 4: Commit the updated `.env.example`**

Copy the current `.env` (without secrets) to `.env.example`:
```bash
# Update .env.example with new keys (without the actual APP_KEY value)
```

```bash
git add .env.example
git commit -m "chore: update env example with octane and postgres config"
```

---

## Task 6: Install and Configure Laravel Passport

**Goal:** Set up OAuth2 authentication with Passport.

**Files:**
- Modify: `.env`
- Modify: `app/Ship/Configs/` (passport config if it exists)

- [ ] **Step 1: Install Passport keys inside the container**

```bash
docker compose exec app php artisan passport:install
```

Expected output:
```
Personal access client created successfully.
Client ID: 1
Client secret: <secret1>

Password grant client created successfully.
Client ID: 2
Client secret: <secret2>
```

- [ ] **Step 2: Set Passport credentials in `.env`**

Copy the Client ID 2 (password grant) credentials to `.env`:
```dotenv
CLIENT_WEB_ID=2
CLIENT_WEB_SECRET=<secret2 from previous step>
```

- [ ] **Step 3: Verify authentication routes are available**

```bash
docker compose exec app php artisan route:list | grep oauth
```

Expected: Routes like `POST v1/oauth/token`, `POST v1/clients/web/login`, `POST v1/api/logout` should be listed.

- [ ] **Step 4: Test login endpoint**

```bash
curl -X POST http://localhost:8000/v1/clients/web/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@admin.com","password":"admin"}'
```

Expected response:
```json
{
  "data": {
    "token_type": "Bearer",
    "expires_in": 31536000,
    "access_token": "eyJ...",
    "refresh_token": "def5..."
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add .env.example
git commit -m "feat: configure Laravel Passport OAuth2 authentication"
```

---

## Task 7: Verify Octane is Running Correctly via Swoole

**Goal:** Confirm Octane is serving requests through Swoole (not php-fpm).

- [ ] **Step 1: Check Supervisor status inside the container**

```bash
docker compose exec app supervisorctl status
```

Expected output:
```
octane                           RUNNING   pid 12, uptime 0:05:32
queue-worker:queue-worker_00     RUNNING   pid 15, uptime 0:05:32
queue-worker:queue-worker_01     RUNNING   pid 16, uptime 0:05:32
```

- [ ] **Step 2: Verify Swoole is responding**

```bash
curl -I http://localhost:8000
```

Expected: HTTP/1.1 200 or 404 with headers. Look for no `X-Powered-By: PHP` or nginx headers — Swoole serves directly.

- [ ] **Step 3: Check Octane log for swoole startup message**

```bash
docker compose exec app cat /var/log/supervisor/octane.log | head -30
```

Expected to see:
```
INFO  Server running…
Local: http://0.0.0.0:8000
```

- [ ] **Step 4: Test the API root endpoint**

```bash
curl http://localhost:8000/v1
```

Expected: JSON response (even if empty or 404, confirms routing works).

- [ ] **Step 5: Test an authenticated endpoint**

```bash
# Get a token first
TOKEN=$(curl -s -X POST http://localhost:8000/v1/clients/web/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@admin.com","password":"admin"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['access_token'])")

# Use token to call authenticated profile endpoint
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/v1/users/profile
```

Expected: JSON response with user data.

---

## Task 8: Octane Memory Leak Safeguards

**Goal:** Configure Octane to avoid common memory leak issues with long-running Swoole processes.

**Files:**
- Modify: `config/octane.php`
- Modify: `app/Providers/AppServiceProvider.php`

- [ ] **Step 1: Configure Octane listeners in `config/octane.php`**

Open `config/octane.php` and ensure the `listeners` section includes state reset handlers:

```php
'listeners' => [
    WorkerStarting::class => [
        EnsureUploadedFilesAreValid::class,
        EnsureQueueDriver::class => ['sync'],
    ],

    RequestReceived::class => [
        ...Octane::prepareApplicationForNextRequest(),
    ],

    RequestHandled::class => [
        FlushTemporaryContainerInstances::class,
    ],

    RequestTerminated::class => [
        // ...
    ],
],
```

> This is typically pre-configured. Just verify it's there.

- [ ] **Step 2: Set max requests before worker restart**

In `config/octane.php`:
```php
'max_requests' => env('OCTANE_MAX_REQUESTS', 500),
```

Add to `.env`:
```dotenv
OCTANE_MAX_REQUESTS=500
```

- [ ] **Step 3: Commit**

```bash
git add config/octane.php .env.example
git commit -m "feat: configure Octane memory management for Swoole workers"
```

---

## Task 9: Create a Sample Container to Verify Porto Architecture

**Goal:** Create a minimal "Hello" container to verify the Porto pattern works end-to-end.

**Files:**
- Create: `app/Containers/AppSection/Hello/UI/API/Routes/GetHello.v1.public.php`
- Create: `app/Containers/AppSection/Hello/UI/API/Controllers/GetHelloController.php`
- Create: `app/Containers/AppSection/Hello/Actions/GetHelloAction.php`

- [ ] **Step 1: Create the controller**

Create `app/Containers/AppSection/Hello/UI/API/Controllers/GetHelloController.php`:

```php
<?php

namespace App\Containers\AppSection\Hello\UI\API\Controllers;

use App\Ship\Parents\Controllers\ApiController;

class GetHelloController extends ApiController
{
    public function __invoke(): array
    {
        return ['message' => 'Hello from Apiato + Swoole!'];
    }
}
```

- [ ] **Step 2: Create the route file**

Create `app/Containers/AppSection/Hello/UI/API/Routes/GetHello.v1.public.php`:

```php
<?php

use App\Containers\AppSection\Hello\UI\API\Controllers\GetHelloController;
use Illuminate\Support\Facades\Route;

Route::get('hello', GetHelloController::class)
    ->name('api_hello_get_hello');
```

- [ ] **Step 3: Create the Action class**

Create `app/Containers/AppSection\Hello\Actions\GetHelloAction.php`:

```php
<?php

namespace App\Containers\AppSection\Hello\Actions;

use App\Ship\Parents\Actions\Action;

class GetHelloAction extends Action
{
    public function run(): string
    {
        return 'Hello from Apiato + Swoole!';
    }
}
```

- [ ] **Step 4: Restart Octane to pick up new routes**

```bash
docker compose exec app php artisan octane:reload
```

Expected: `INFO  Workers reloaded successfully.`

- [ ] **Step 5: Test the new endpoint**

```bash
curl http://localhost:8000/v1/hello
```

Expected:
```json
{"message": "Hello from Apiato + Swoole!"}
```

- [ ] **Step 6: Commit**

```bash
git add app/Containers/
git commit -m "feat: add Hello container to verify Porto architecture"
```

---

## Task 10: Redis Cache and Queue Smoke Test

**Goal:** Verify Redis cache and queue are connected and working.

- [ ] **Step 1: Test Redis cache connection**

```bash
docker compose exec app php artisan tinker --no-interaction \
  --execute="Cache::put('test', 'ok', 60); echo Cache::get('test');"
```

Expected output: `ok`

- [ ] **Step 2: Dispatch a test job to verify queue**

```bash
docker compose exec app php artisan tinker --no-interaction \
  --execute="dispatch(new \Illuminate\Queue\CallQueuedClosure(function() { \Log::info('Queue works!'); }));"
```

Then check the queue worker log:
```bash
docker compose exec app tail -20 /var/log/supervisor/queue.log
```

Expected: Log entry showing the job was processed.

- [ ] **Step 3: Verify Redis keys exist**

```bash
docker compose exec redis redis-cli keys "*"
```

Expected: You should see queue and cache keys like `apiato_cache:*` or `queues:default`.

---

## Quick Reference: Common Commands

```bash
# Start all services
docker compose up -d

# Rebuild the app image
docker compose up -d --build app

# Run artisan commands
docker compose exec app php artisan <command>

# View Octane logs
docker compose exec app tail -f /var/log/supervisor/octane.log

# View queue logs
docker compose exec app tail -f /var/log/supervisor/queue.log

# Restart Octane workers (after code changes)
docker compose exec app php artisan octane:reload

# Stop all
docker compose down

# Stop and remove volumes (reset DB)
docker compose down -v
```

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Swoole not found | Extension not loaded | Check `docker/php/Dockerfile` — ensure `pecl install swoole` and `docker-php-ext-enable swoole` |
| DB connection refused | Postgres not healthy | `docker compose ps` — wait for postgres to be healthy |
| Migrations fail | Wrong DB driver | Ensure `DB_CONNECTION=pgsql` in `.env` |
| Routes not found | Octane cached old routes | `php artisan octane:reload` |
| Passport keys missing | `passport:install` not run | Run `docker compose exec app php artisan passport:install` |
| Memory growing | No max_requests set | Set `OCTANE_MAX_REQUESTS=500` in `.env` |

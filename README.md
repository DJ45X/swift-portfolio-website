# SwiftPortfolioProject

💧 A portfolio / journal web app built with the [Vapor](https://vapor.codes) web framework, Fluent, and Leaf.

The app uses **in-memory SQLite** for fast, dependency-free local development and **PostgreSQL** for production. The database is selected automatically from environment variables (see [Database configuration](#database-configuration)), so the same image runs in both environments without code changes.

## Local development

For running and testing locally (e.g. from Xcode), no database setup is required — the app uses an in-memory SQLite store that is rebuilt and re-seeded on each launch.

Build the project:
```bash
swift build
```

Run the server (listens on http://localhost:8080):
```bash
swift run
```

Run the tests:
```bash
swift test
```

To persist data locally between runs, set `SQLITE_FILE=1` to use a `db.sqlite` file instead of the in-memory store:
```bash
SQLITE_FILE=1 swift run
```

## Database configuration

The driver is chosen at startup, in priority order:

| Condition | Driver | Use case |
| --- | --- | --- |
| `DATABASE_URL` or `DATABASE_HOST` is set | PostgreSQL | Production |
| `SQLITE_FILE=1` | File-backed SQLite (`db.sqlite`) | Local persistence |
| _(none of the above)_ | In-memory SQLite | Local development / tests (default) |

PostgreSQL is configured either with a single connection URL or with individual variables:

| Variable | Default | Description |
| --- | --- | --- |
| `DATABASE_URL` | _(unset)_ | Full connection string, e.g. `postgres://user:pass@host:5432/dbname`. Takes precedence over the variables below. |
| `DATABASE_HOST` | _(unset)_ | PostgreSQL host. Setting this enables the PostgreSQL driver. |
| `DATABASE_PORT` | `5432` | PostgreSQL port. |
| `DATABASE_USERNAME` | `vapor` | Database user. |
| `DATABASE_PASSWORD` | _(empty)_ | Database password. |
| `DATABASE_NAME` | `vapor` | Database name. |
| `LOG_LEVEL` | `info` (prod) | Vapor log level (`trace`, `debug`, `info`, …). |

Database migrations run automatically on startup, so no separate migration step is needed.

## Running with Docker locally

The repository includes a `Dockerfile` and `docker-compose.yml` for building and running a production-like image on your machine:

```bash
docker compose build
docker compose up app
```

This builds the image locally and serves on http://localhost:8080.

## Production deployment

Production runs the pre-built image from the **GitHub Container Registry (GHCR)** against a PostgreSQL container, using `docker-compose.prod.yml`. The image is published by CI (configured separately).

On your VPS:

1. **Copy the deployment files** to the server — `docker-compose.prod.yml` and a `.env` file.

2. **Create a `.env` file** next to `docker-compose.prod.yml`:
   ```env
   # Image to pull from GHCR
   REGISTRY_IMAGE=ghcr.io/<owner>/swift-portfolio-project:latest

   # PostgreSQL credentials
   DATABASE_NAME=portfolio
   DATABASE_USERNAME=portfolio
   DATABASE_PASSWORD=change-me-to-a-strong-secret

   # Optional
   LOG_LEVEL=info
   ```
   Replace `<owner>` with your GitHub username/org and set a strong `DATABASE_PASSWORD`.

3. **Authenticate to GHCR** (only needed if the package is private):
   ```bash
   echo "$GITHUB_TOKEN" | docker login ghcr.io -u <owner> --password-stdin
   ```

4. **Pull and start** the app and database:
   ```bash
   docker compose -f docker-compose.prod.yml pull
   docker compose -f docker-compose.prod.yml up -d
   ```
   PostgreSQL data is persisted in the `db_data` named volume, and migrations run automatically on first boot.

5. **Expose it through cloudflared.** The app is published on `127.0.0.1:8080`. Point your existing cloudflared tunnel's ingress at the app, using whichever matches your setup:
   - **cloudflared on the host network:** target `http://localhost:8080`.
   - **cloudflared in its own container:** attach the `app` service to the tunnel's Docker network and target `http://app:8080`, or point the tunnel at the host's address.

### Updating to a new release

```bash
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d
```

The app re-runs any pending migrations on startup. To follow logs:
```bash
docker compose -f docker-compose.prod.yml logs -f app
```

## See more

- [Vapor Website](https://vapor.codes)
- [Vapor Documentation](https://docs.vapor.codes)
- [Vapor GitHub](https://github.com/vapor)
- [Vapor Community maintained packages](https://github.com/vapor-community)
</content>
</invoke>

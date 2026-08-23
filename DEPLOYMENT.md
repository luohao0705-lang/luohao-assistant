# Private deployment runbook

This app is intentionally a private, single-user deployment. The checked-in files contain no production secrets and do not use the previously exposed root password.

## Server prerequisites

1. Point `luohao.hsh6.com` A/AAAA records at the server and verify that public DNS resolves before starting Caddy.
2. Provide a fresh SSH key or a non-root deployment account. Rotate any credential that has appeared in chat or logs.
3. Install Docker Engine and the Compose plugin on the Linux host.

## Configure secrets

From `deploy/`, copy `.env.example` to `.env` and replace every placeholder:

- `POSTGRES_PASSWORD`: random database password.
- `JWT_SECRET`: at least 32 random characters.
- `APP_PASSWORD`: an Argon2id hash, generated locally with the backend tooling. Never put the plaintext password in git.
- `DEEPSEEK_API_KEY`: production DeepSeek key, installed only on the server.

Keep `.env` mode `0600`. Do not paste the secret file into support chats.

## Start and verify

```sh
cd /srv/luohao-assistant/deploy
docker compose pull
docker compose up -d --build
docker compose ps
curl -fsS https://luohao.hsh6.com/health
curl -fsS https://luohao.hsh6.com/health/ready
```

The API container runs `alembic upgrade head` before Uvicorn. Caddy terminates HTTPS and proxies only to the internal API service.

After the health checks pass, run the public API verifier:

```sh
sh /srv/luohao-assistant/deploy/verify.sh https://luo.hsh6.com
```

## Backup

Run `deploy/backup.sh` on a schedule and copy the encrypted backup off-host. Test restore before treating the system as production-ready.

## iOS private install

On macOS, generate the Xcode project from `ios/project.yml`, add the Swift files to the target, select a personal Team, and install to the registered iPhone using a development/ad hoc signing profile. Add the microphone, speech-recognition, and Face ID usage descriptions already present in the project file.

Production status remains blocked until DNS, secure SSH access, production secrets, Docker/PostgreSQL, and a signed real-device Xcode build are verified.

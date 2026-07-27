import { promisify } from "node:util";
import { execFile } from "node:child_process";
import { existsSync, statSync } from "node:fs";

const execFileAsync = promisify(execFile);
const args = process.argv.slice(2);

function option(name, fallback) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : fallback;
}

function requiredOption(name) {
  const value = option(name, "");
  if (!value) throw new Error(`${name} is required`);
  return value;
}

if (process.env.DISPOSABLE_ENVIRONMENT !== "true") {
  throw new Error(
    "Refusing to restore: set DISPOSABLE_ENVIRONMENT=true for a disposable target.",
  );
}

const dumpPath = requiredOption("--dump");
if (!existsSync(dumpPath) || statSync(dumpPath).size === 0) {
  throw new Error(`Backup dump does not exist or is empty: ${dumpPath}`);
}

const postgresImage = option("--postgres-image", "postgres:15.18-alpine3.24");
const postgresContainer = option(
  "--postgres-container",
  "bma-local-restore-postgres",
);
const backendContainer = option(
  "--backend-container",
  "bma-local-restore-backend",
);
const restoreVolume = option("--volume", "bma_local_restore_pg_data");
const keepTarget = args.includes("--keep");

if (restoreVolume === "bma_staging_pg_data") {
  throw new Error("Refusing to use the active staging database volume.");
}

const restoreUser = "restore_user";
const restorePassword = "local_restore_password";
const restoreDatabase = "restore_db";
const restoreJwtSecret = "local_restore_jwt_secret_12345678901234567890";

async function docker(dockerArgs, options = {}) {
  return execFileAsync("docker", dockerArgs, {
    maxBuffer: 4 * 1024 * 1024,
    ...options,
  });
}

async function dockerExists(kind, name) {
  try {
    await docker([kind, "inspect", name]);
    return true;
  } catch {
    return false;
  }
}

async function waitForDatabase() {
  for (let attempt = 1; attempt <= 30; attempt += 1) {
    try {
      await docker([
        "exec",
        postgresContainer,
        "pg_isready",
        "-U",
        restoreUser,
        "-d",
        restoreDatabase,
      ]);
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }

  throw new Error("Disposable PostgreSQL did not become ready within 30 seconds.");
}

let startedPostgres = false;
let startedBackend = false;
let volumeCreated = false;
const restoreStartedAt = Date.now();

async function cleanup() {
  if (startedBackend) {
    await docker(["rm", "-f", backendContainer]).catch(() => undefined);
  }
  if (startedPostgres) {
    await docker(["rm", "-f", postgresContainer]).catch(() => undefined);
  }
  if (!keepTarget && volumeCreated) {
    await docker(["volume", "rm", restoreVolume]).catch(() => undefined);
  }
}

try {
  if (await dockerExists("container", postgresContainer)) {
    throw new Error(`Container already exists: ${postgresContainer}`);
  }
  if (await dockerExists("volume", restoreVolume)) {
    throw new Error(`Volume already exists: ${restoreVolume}`);
  }
  if (!(await dockerExists("image", "bma-backend:local"))) {
    throw new Error("Required local image bma-backend:local was not found.");
  }

  await docker(["volume", "create", restoreVolume]);
  volumeCreated = true;
  await docker([
    "run",
    "-d",
    "--name",
    postgresContainer,
    "-e",
    `POSTGRES_USER=${restoreUser}`,
    "-e",
    `POSTGRES_PASSWORD=${restorePassword}`,
    "-e",
    `POSTGRES_DB=${restoreDatabase}`,
    "-v",
    `${restoreVolume}:/var/lib/postgresql/data`,
    postgresImage,
  ]);
  startedPostgres = true;

  await waitForDatabase();
  await docker(["cp", dumpPath, `${postgresContainer}:/tmp/restore.dump`]);
  await docker([
    "exec",
    postgresContainer,
    "pg_restore",
    "--clean",
    "--if-exists",
    "--no-owner",
    "--dbname",
    restoreDatabase,
    "--username",
    restoreUser,
    "/tmp/restore.dump",
  ]);

  const verificationSql = [
    "SELECT json_build_object(",
    "  'migrationCount', (SELECT count(*) FROM drizzle.__drizzle_migrations),",
    "  'users', (SELECT count(*) FROM public.users),",
    "  'projects', (SELECT count(*) FROM public.projects),",
    "  'proposals', (SELECT count(*) FROM public.proposals),",
    "  'attachments', (SELECT count(*) FROM public.project_attachments)",
    ")::text;",
  ].join("\n");
  const verification = await docker([
    "exec",
    postgresContainer,
    "psql",
    "--username",
    restoreUser,
    "--dbname",
    restoreDatabase,
    "--tuples-only",
    "--no-align",
    "--command",
    verificationSql,
  ]);
  console.log("Restored database verification:");
  console.log(verification.stdout.trim());

  await docker([
    "run",
    "-d",
    "--name",
    backendContainer,
    "--network",
    `container:${postgresContainer}`,
    "-e",
    "NODE_ENV=production",
    "-e",
    "PORT=8081",
    "-e",
    `DATABASE_URL=postgresql://${restoreUser}:${restorePassword}@localhost:5432/${restoreDatabase}`,
    "-e",
    `JWT_SECRET=${restoreJwtSecret}`,
    "-e",
    "PUBLIC_API_URL=http://localhost:8088/api/v1",
    "-e",
    "CORS_ORIGINS=http://localhost:8088",
    "-e",
    "UPLOAD_STORAGE_DIR=/app/uploads",
    "-e",
    "COOKIE_SECURE=false",
    "-e",
    "COOKIE_SAME_SITE=lax",
    "-e",
    "COOKIE_DOMAIN=",
    "bma-backend:local",
  ]);
  startedBackend = true;

  await new Promise((resolve) => setTimeout(resolve, 3000));
  await docker([
    "exec",
    backendContainer,
    "wget",
    "--spider",
    "--no-verbose",
    "http://localhost:8081/health/live",
  ]);
  await docker([
    "exec",
    backendContainer,
    "wget",
    "--spider",
    "--no-verbose",
    "http://localhost:8081/health/ready",
  ]);

  console.log(
    `Disposable database restore and temporary Backend readiness passed in ${Date.now() - restoreStartedAt} ms.`,
  );
} finally {
  await cleanup();
}

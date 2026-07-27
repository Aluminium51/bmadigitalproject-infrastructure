import { createWriteStream, mkdirSync } from "node:fs";
import { join } from "node:path";
import { spawn } from "node:child_process";

const outputDir = process.env.BACKUP_DIR || join(process.cwd(), "backups");
mkdirSync(outputDir, { recursive: true });

const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
const outputPath = join(outputDir, "bma_staging_db_" + timestamp + ".dump");

const envFile = process.env.DB_ENV_FILE || "env/db.staging";
const composeFile = process.env.DB_COMPOSE_FILE || "compose.db.staging.yml";

const command = [
  "export PGPASSWORD=\"$POSTGRES_BACKUP_PASSWORD\"",
  "pg_dump",
  "--format=custom",
  "--host=localhost",
  "--username=\"$POSTGRES_BACKUP_USER\"",
  "--dbname=\"$POSTGRES_DB\"",
].join(" ");

const child = spawn(
  "docker",
  [
    "compose",
    "--env-file",
    envFile,
    "-f",
    composeFile,
    "exec",
    "-T",
    "postgres",
    "sh",
    "-c",
    command,
  ],
  {
    stdio: ["ignore", "pipe", "inherit"],
    shell: false,
  },
);

child.stdout.pipe(createWriteStream(outputPath));
child.on("close", (code) => {
  if (code !== 0) process.exit(code ?? 1);
  console.log("Staging database backup written to " + outputPath);
});

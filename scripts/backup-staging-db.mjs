import {
  createHash,
  createReadStream,
  createWriteStream,
  mkdirSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { basename, join } from "node:path";
import { spawn } from "node:child_process";

const outputDir = process.env.BACKUP_DIR || join(process.cwd(), "backups");
mkdirSync(outputDir, { recursive: true });

const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
const outputPath = join(outputDir, "bma_staging_db_" + timestamp + ".dump");

const envFile = process.env.DB_ENV_FILE || "env/db.staging";
const composeFile = process.env.DB_COMPOSE_FILE || "compose.db.staging.yml";

const command = [
  'export PGPASSWORD="$POSTGRES_BACKUP_PASSWORD"',
  "pg_dump",
  "--format=custom",
  "--host=localhost",
  '--username="$POSTGRES_BACKUP_USER"',
  '--dbname="$POSTGRES_DB"',
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

const outputStream = createWriteStream(outputPath, { mode: 0o600 });
const outputFinished = new Promise((resolve, reject) => {
  outputStream.on("close", resolve);
  outputStream.on("error", reject);
});

child.stdout.pipe(outputStream);
child.on("close", async (code) => {
  await outputFinished;

  if (code !== 0) process.exit(code ?? 1);

  const { size } = statSync(outputPath);
  if (size === 0) {
    throw new Error("Backup command produced an empty dump: " + outputPath);
  }

  const checksum = await new Promise((resolve, reject) => {
    const hash = createHash("sha256");
    const input = createReadStream(outputPath);
    input.on("data", (chunk) => hash.update(chunk));
    input.on("error", reject);
    input.on("end", () => resolve(hash.digest("hex")));
  });

  const checksumPath = outputPath + ".sha256";
  writeFileSync(
    checksumPath,
    checksum + "  " + basename(outputPath) + "\n",
    { mode: 0o600 },
  );

  console.log("Staging database backup written to " + outputPath);
  console.log("SHA-256 checksum written to " + checksumPath);
});

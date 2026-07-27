import {
  createReadStream,
  createWriteStream,
  mkdirSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { createHash } from "node:crypto";
import { basename, join } from "node:path";
import { spawn } from "node:child_process";
import { pipeline } from "node:stream/promises";

const args = process.argv.slice(2);

function option(name, fallback) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : fallback;
}

const outputDir = option(
  "--output-dir",
  process.env.BACKUP_DIR || join(process.cwd(), "backups"),
);
mkdirSync(outputDir, { recursive: true });

const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
const outputPath = join(outputDir, "bma_staging_db_" + timestamp + ".dump");

const envFile = option(
  "--env-file",
  process.env.DB_ENV_FILE || "env/db.staging",
);
const composeFile = option(
  "--compose-file",
  process.env.DB_COMPOSE_FILE || "compose.db.staging.yml",
);

const command = [
  'PGPASSWORD="$POSTGRES_BACKUP_PASSWORD"',
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
const outputPipeline = pipeline(child.stdout, outputStream);
const exitCode = await new Promise((resolve, reject) => {
  child.once("error", reject);
  child.once("close", (code) => resolve(code ?? 1));
});

try {
  await outputPipeline;
} catch (error) {
  throw new Error("Could not write the database dump", { cause: error });
}

if (exitCode !== 0) {
  throw new Error(`pg_dump failed with exit code ${exitCode}`);
}

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

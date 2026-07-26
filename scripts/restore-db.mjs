import { createReadStream, statSync } from "node:fs";
import { spawn } from "node:child_process";

const inputPath = process.argv[2];
if (!inputPath) throw new Error("Usage: node scripts/restore-db.mjs <backup.dump>");
statSync(inputPath);
const linux = process.argv.includes("--linux");
const composeFiles = ["-f", "compose.db.dev.yml"];
if (linux) composeFiles.push("-f", "compose.db.linux.override.yml");

const child = spawn("docker", [
  "compose",
  "--env-file",
  ".env.db.dev",
  ...composeFiles,
  "exec",
  "-T",
  "postgres",
  "sh",
  "-c",
  'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_restore --clean --if-exists --no-owner --host=localhost --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"',
], { stdio: ["pipe", "inherit", "inherit"], shell: false });

createReadStream(inputPath).pipe(child.stdin);
child.on("close", (code) => process.exit(code ?? 1));

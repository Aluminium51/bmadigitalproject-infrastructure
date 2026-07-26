import { mkdirSync, createWriteStream } from "node:fs";
import { spawn } from "node:child_process";
import { join } from "node:path";

const outputDir = join(process.cwd(), "backups");
mkdirSync(outputDir, { recursive: true });
const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
const outputPath = join(outputDir, `bma_db_${timestamp}.dump`);
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
  'export PGPASSWORD="$POSTGRES_PASSWORD"; pg_dump --format=custom --host=localhost --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"',
], { stdio: ["ignore", "pipe", "inherit"], shell: false });

child.stdout.pipe(createWriteStream(outputPath));
child.on("close", (code) => {
  if (code !== 0) process.exit(code ?? 1);
  console.log(`Database backup written to ${outputPath}`);
});

import { existsSync, statSync } from "node:fs";
import { resolve } from "node:path";
import { promisify } from "node:util";
import { execFile } from "node:child_process";

const execFileAsync = promisify(execFile);
const args = process.argv.slice(2);

function option(name, fallback) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : fallback;
}

if (process.env.DISPOSABLE_ENVIRONMENT !== "true") {
  throw new Error(
    "Refusing to restore uploads: set DISPOSABLE_ENVIRONMENT=true.",
  );
}

const archivePath = resolve(option("--archive", ""));
const volume = option("--volume", "bma_local_restore_uploads");
const image = option("--image", "alpine:3.21.3");

if (!archivePath || !existsSync(archivePath) || statSync(archivePath).size === 0) {
  throw new Error("A non-empty --archive path is required.");
}
if (["bma_staging_uploads", "bma_staging_local_uploads"].includes(volume)) {
  throw new Error("Refusing to overwrite an active staging or local-validation upload volume.");
}

async function docker(args) {
  return execFileAsync("docker", args, { maxBuffer: 2 * 1024 * 1024 });
}

try {
  await docker(["volume", "create", volume]);
  await docker([
    "run",
    "--rm",
    "-v",
    `${volume}:/target`,
    "-v",
    `${archivePath}:/backup/archive.tar.gz:ro`,
    image,
    "sh",
    "-c",
    "find /target -mindepth 1 -delete; tar -xzf /backup/archive.tar.gz -C /target",
  ]);
  const stats = await docker([
    "run",
    "--rm",
    "-v",
    `${volume}:/source:ro`,
    image,
    "sh",
    "-c",
    "files=$(find /source -type f | wc -l); bytes=$(du -sk /source | awk '{print $1 * 1024}'); printf '%s %s\\n' \"$files\" \"$bytes\"",
  ]);
  console.log(`Upload restore completed into disposable volume ${volume}.`);
  console.log(`Restored files and bytes: ${stats.stdout.trim()}`);
} finally {
  await docker(["volume", "rm", volume]).catch(() => undefined);
}

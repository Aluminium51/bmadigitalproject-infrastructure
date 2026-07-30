import { createReadStream, mkdirSync, statSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { basename, join, resolve } from "node:path";
import { promisify } from "node:util";
import { execFile } from "node:child_process";

const execFileAsync = promisify(execFile);
const args = process.argv.slice(2);

function option(name, fallback) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : fallback;
}

const sourcePath = option("--path", process.env.UPLOAD_HOST_PATH || "/opt/bma/uploads");
const sourceVolume = option("--volume", process.env.UPLOAD_VOLUME || "");
if (sourceVolume && process.env.UPLOAD_HOST_PATH) {
  throw new Error("Choose either --path/UPLOAD_HOST_PATH or --volume/UPLOAD_VOLUME, not both.");
}
const sourceStats = sourceVolume ? undefined : statSync(sourcePath, { throwIfNoEntry: false });
if (!sourceVolume && !sourceStats?.isDirectory()) {
  throw new Error(`Upload directory does not exist: ${sourcePath}`);
}
const outputDir = resolve(option("--output-dir", "backups"));
const image = option("--image", "alpine:3.21.3");
mkdirSync(outputDir, { recursive: true });

const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
const archiveName = `bma_staging_uploads_${timestamp}.tar.gz`;
const archivePath = join(outputDir, archiveName);
const mount = `${outputDir}:/backup`;
const sourceMount = sourceVolume ? `${sourceVolume}:/source:ro` : `${resolve(sourcePath)}:/source:ro`;

async function docker(args) {
  return execFileAsync("docker", args, { maxBuffer: 2 * 1024 * 1024 });
}

const stats = await docker([
  "run",
  "--rm",
  "-v",
  sourceMount,
  image,
  "sh",
  "-c",
  "files=$(find /source -type f | wc -l); bytes=$(du -sk /source | awk '{print $1 * 1024}'); printf '%s %s\\n' \"$files\" \"$bytes\"",
]);
const [fileCount, totalBytes] = stats.stdout.trim().split(/\s+/);

await docker([
  "run",
  "--rm",
  "-v",
  sourceMount,
  "-v",
  mount,
  image,
  "tar",
  "-czf",
  `/backup/${archiveName}`,
  "-C",
  "/source",
  ".",
]);

const { size } = statSync(archivePath);
if (size === 0) throw new Error("Upload archive is empty.");

const checksum = await new Promise((resolveChecksum, reject) => {
  const hash = createHash("sha256");
  const input = createReadStream(archivePath);
  input.on("data", (chunk) => hash.update(chunk));
  input.on("error", reject);
  input.on("end", () => resolveChecksum(hash.digest("hex")));
});

const checksumPath = `${archivePath}.sha256`;
writeFileSync(checksumPath, `${checksum}  ${basename(archivePath)}\n`, { mode: 0o600 });

console.log(`Upload backup written to ${archivePath}`);
console.log(`Files: ${fileCount || 0}`);
console.log(`Source bytes: ${totalBytes || 0}`);
console.log(`SHA-256 checksum written to ${checksumPath}`);

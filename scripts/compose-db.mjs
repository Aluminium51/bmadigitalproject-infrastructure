import { spawnSync } from "node:child_process";

const args = process.argv.slice(2);
const platform = args[0] === "--linux" ? "linux" : "desktop";
const composeFiles = ["-f", "compose.db.dev.yml"];
if (platform === "linux") composeFiles.push("-f", "compose.db.linux.override.yml");

const result = spawnSync("docker", [
  "compose",
  "--env-file",
  ".env.db.dev",
  ...composeFiles,
  ...args.filter((arg) => arg !== "--linux"),
], { stdio: "inherit", shell: false });

process.exit(result.status ?? 1);

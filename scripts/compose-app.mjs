import { spawnSync } from "node:child_process";

const args = process.argv.slice(2);
const platform = args[0] === "--linux" ? "linux" : "desktop";
const composeFiles = ["-f", "compose.app.dev.yml"];
const envFile = platform === "linux" ? ".env.app.dev.linux" : ".env.app.dev";
if (platform === "linux") composeFiles.push("-f", "compose.linux.override.yml");
else composeFiles.push("-f", "compose.desktop.override.yml");

const result = spawnSync("docker", [
  "compose",
  "--env-file",
  envFile,
  ...composeFiles,
  ...args.filter((arg) => arg !== "--linux"),
], { stdio: "inherit", shell: false });

process.exit(result.status ?? 1);

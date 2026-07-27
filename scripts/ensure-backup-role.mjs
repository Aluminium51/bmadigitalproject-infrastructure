import { spawn } from "node:child_process";

const args = process.argv.slice(2);
const envFileIndex = args.indexOf("--env-file");
const composeFileIndex = args.indexOf("--compose-file");

const envFile = envFileIndex >= 0 ? args[envFileIndex + 1] : "env/db.staging";
const composeFile =
  composeFileIndex >= 0
    ? args[composeFileIndex + 1]
    : "compose.db.staging.yml";

if (!envFile || !composeFile) {
  throw new Error(
    "Usage: node scripts/ensure-backup-role.mjs [--env-file path] [--compose-file path]",
  );
}

const sql = [
  "SELECT format(",
  "  'DO $do$",
  "   BEGIN",
  "     IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = %L) THEN",
  "       CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT;",
  "     ELSE",
  "       ALTER ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT;",
  "     END IF;",
  "   END",
  "   $do$;',",
  "  :'backup_user',",
  "  :'backup_user',",
  "  :'backup_password',",
  "  :'backup_user',",
  "  :'backup_password'",
  ") \\gexec",
  "",
  "GRANT CONNECT ON DATABASE :\"db_name\" TO :\"backup_user\";",
  "GRANT pg_read_all_data TO :\"backup_user\";",
].join("\n");

const command = [
  'PGPASSWORD="$POSTGRES_PASSWORD"',
  "psql",
  "-v",
  "ON_ERROR_STOP=1",
  "-h",
  "localhost",
  "-U",
  "\"$POSTGRES_USER\"",
  "-d",
  "\"$POSTGRES_DB\"",
  "-v",
  "backup_user=\"$POSTGRES_BACKUP_USER\"",
  "-v",
  "backup_password=\"$POSTGRES_BACKUP_PASSWORD\"",
  "-v",
  "db_name=\"$POSTGRES_DB\"",
  "-f",
  "-",
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
    stdio: ["pipe", "inherit", "inherit"],
    shell: false,
  },
);

child.stdin.end(sql);
child.on("close", (code) => process.exit(code ?? 1));

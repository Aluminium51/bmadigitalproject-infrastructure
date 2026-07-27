const baseUrl = (
  process.env.STAGING_BASE_URL ||
  process.argv[2] ||
  ""
).replace(/\/+$/, "");

if (!baseUrl) {
  throw new Error(
    "Usage: STAGING_BASE_URL=https://staging.example.com node scripts/smoke-test-staging.mjs",
  );
}

const checks = [
  { path: "/", status: 200, content: "text/html" },
  { path: "/health/live", status: 200, content: "application/json" },
  { path: "/health/ready", status: 200, content: "application/json" },
  { path: "/openapi-v1.json", status: 200, content: "application/json" },
  { path: "/docs/", status: 200, content: "text/html" },
  { path: "/api/v1/projects", status: 401, content: "application/json" },
];

async function request(path) {
  const response = await fetch(baseUrl + path, {
    redirect: "follow",
    signal: AbortSignal.timeout(15000),
  });
  const body = await response.text();
  return {
    response,
    body,
    contentType: response.headers.get("content-type") || "",
  };
}

for (const check of checks) {
  const result = await request(check.path);
  const matchesContentType = result.contentType.includes(check.content);

  console.log(
    check.path +
      " -> " +
      result.response.status +
      " " +
      result.contentType,
  );

  if (result.response.status !== check.status || !matchesContentType) {
    throw new Error(
      "Smoke test failed for " +
        check.path +
        ": expected " +
        check.status +
        " and " +
        check.content,
    );
  }
}

const home = await request("/");
const assetUrls = [
  ...home.body.matchAll(/<script[^>]+src="([^"]+\.js[^"]*)"/gi),
].map((match) => new URL(match[1], baseUrl).toString());

const forbiddenPatterns = [
  /host\.docker\.internal/i,
  /postgresql:\/\//i,
  /:5432(?:\b|\/)/i,
  /:8081(?:\b|\/)/i,
  /(?:10\.\d{1,3}|192\.168\.\d{1,3}|172\.(?:1[6-9]|2\d|3[0-1]))\.\d{1,3}\.\d{1,3}/i,
];

for (const assetUrl of [...new Set(assetUrls)]) {
  const response = await fetch(assetUrl, {
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) {
    throw new Error("Could not fetch browser bundle " + assetUrl);
  }
  const body = await response.text();

  for (const pattern of forbiddenPatterns) {
    if (pattern.test(body)) {
      throw new Error(
        "Private backend/database address detected in browser bundle " +
          assetUrl +
          ": " +
          pattern,
      );
    }
  }
}

console.log(
  "Smoke tests passed, including unauthenticated 401 and browser-bundle private-IP checks.",
);

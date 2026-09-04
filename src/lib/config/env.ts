import { z } from "zod";

const envSchema = z.object({
  LM_STUDIO_BASE_URL: z.string().default("http://localhost:1234/v1"),
  LM_STUDIO_API_KEY: z.string().default("lm-studio"),
  DATABASE_URL: z.string().default("./data/local.db"),
  RUNTIME_MODE: z.enum(["local", "remote"]).default("local"),
  WEB_SEARCH_ENABLED: z
    .string()
    .optional()
    .transform((v) => v !== "false")
    .pipe(z.boolean()),
  WEB_SEARCH_MAX_RESULTS: z.coerce.number().int().min(1).max(20).default(5),
  WEB_SEARCH_MAX_CALLS_PER_REQUEST: z.coerce.number().int().min(1).max(5).default(2),
  WEB_SEARCH_TIMEOUT_MS: z.coerce.number().int().min(1000).default(25000),
  WEB_SEARCH_PROVIDER: z
    .enum(["auto", "duckduckgo", "brave", "searxng"])
    .default("searxng"),
  BRAVE_SEARCH_API_KEY: z.string().optional(),
  SEARXNG_URL: z
    .string()
    .default("http://localhost:8080")
    .transform((v) => v.trim().replace(/\/$/, "")),
  CF_ACCESS_ENABLED: z
    .string()
    .optional()
    .transform((v) => v === "true")
    .pipe(z.boolean()),
  CF_ACCESS_TEAM_DOMAIN: z.string().optional(),
  CF_ACCESS_AUD: z.string().optional(),
  HEALTH_CHECK_TOKEN: z.string().optional(),
  EMAIL_ENABLED: z
    .string()
    .optional()
    .transform((v) => v === "true")
    .pipe(z.boolean()),
  FILES_ENABLED: z
    .string()
    .optional()
    .transform((v) => v === "true")
    .pipe(z.boolean()),
  GOOGLE_OAUTH_CLIENT_ID: z.string().optional(),
  GOOGLE_OAUTH_CLIENT_SECRET: z.string().optional(),
  GOOGLE_OAUTH_REDIRECT_URI: z.string().url().optional(),
  PUBLIC_BASE_URL: z.string().url().optional(),
  OAUTH_TOKEN_ENCRYPTION_KEY: z.string().optional(),
});

export type Env = z.infer<typeof envSchema>;

let cached: Env | null = null;

export function getEnv(): Env {
  if (!cached) {
    cached = envSchema.parse({
      LM_STUDIO_BASE_URL: process.env.LM_STUDIO_BASE_URL,
      LM_STUDIO_API_KEY: process.env.LM_STUDIO_API_KEY,
      DATABASE_URL: process.env.DATABASE_URL,
      RUNTIME_MODE: process.env.RUNTIME_MODE,
      WEB_SEARCH_ENABLED: process.env.WEB_SEARCH_ENABLED,
      WEB_SEARCH_MAX_RESULTS: process.env.WEB_SEARCH_MAX_RESULTS,
      WEB_SEARCH_MAX_CALLS_PER_REQUEST: process.env.WEB_SEARCH_MAX_CALLS_PER_REQUEST,
      WEB_SEARCH_TIMEOUT_MS: process.env.WEB_SEARCH_TIMEOUT_MS,
      WEB_SEARCH_PROVIDER: process.env.WEB_SEARCH_PROVIDER,
      BRAVE_SEARCH_API_KEY: process.env.BRAVE_SEARCH_API_KEY,
      SEARXNG_URL: process.env.SEARXNG_URL,
      CF_ACCESS_ENABLED: process.env.CF_ACCESS_ENABLED,
      CF_ACCESS_TEAM_DOMAIN: process.env.CF_ACCESS_TEAM_DOMAIN,
      CF_ACCESS_AUD: process.env.CF_ACCESS_AUD,
      HEALTH_CHECK_TOKEN: process.env.HEALTH_CHECK_TOKEN,
      EMAIL_ENABLED: process.env.EMAIL_ENABLED,
      FILES_ENABLED: process.env.FILES_ENABLED,
      GOOGLE_OAUTH_CLIENT_ID: process.env.GOOGLE_OAUTH_CLIENT_ID,
      GOOGLE_OAUTH_CLIENT_SECRET: process.env.GOOGLE_OAUTH_CLIENT_SECRET,
      GOOGLE_OAUTH_REDIRECT_URI: process.env.GOOGLE_OAUTH_REDIRECT_URI,
      PUBLIC_BASE_URL: process.env.PUBLIC_BASE_URL,
      OAUTH_TOKEN_ENCRYPTION_KEY: process.env.OAUTH_TOKEN_ENCRYPTION_KEY,
    });
  }
  return cached;
}

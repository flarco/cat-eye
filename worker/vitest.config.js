import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: { WEBHOOK_SECRET: "test-secret", DEVICE_AAAA: "token-a", DEVICE_BBBB: "token-b" },
      },
    }),
  ],
});

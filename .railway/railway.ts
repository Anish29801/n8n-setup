import { defineRailway, project, service } from "railway/iac";

export default defineRailway(() => {
  const n8n = service("n8n", {
    source: {
      dockerfilePath: "./Dockerfile",
    },
    healthcheckPath: "/",
    port: 5678,
    env: {
      N8N_PORT: "5678",
      N8N_PROTOCOL: "https",
      N8N_SECURE_COOKIE: "true",
      GENERIC_TIMEZONE: "Asia/Kolkata",
      TZ: "Asia/Kolkata",
      N8N_RUNNERS_ENABLED: "true",
      N8N_DIAGNOSTICS_ENABLED: "false",
      N8N_VERSION_NOTIFICATIONS_ENABLED: "false",
      N8N_HIRING_BANNER_ENABLED: "false",
      NODE_ENV: "production",
      N8N_BASIC_AUTH_ACTIVE: "true",
      N8N_BASIC_AUTH_USER: "admin",
    },
    volumes: [
      {
        mountPath: "/home/node/.n8n",
      },
    ],
  });

  return project("n8n", {
    resources: [n8n],
  });
});

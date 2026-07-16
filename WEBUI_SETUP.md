# 🖥️ Developer Portal (Web UI) Integration Guide

This guide covers how to dockerize, configure, and deploy the Next.js Frontend (Developer Portal) alongside your Core Platform.

> **💡 Note:** This entire guide is completely **optional**. The platform is designed to run perfectly via Git commits (headless). You only need to follow this guide if you want to provide your teams with a visual UI!

You should only follow this guide **after completing Phase 1 through Phase 8** of the main writeup, so that your Keycloak, GitLab, and Kubernetes tokens are already generated and ready!

---

## 1. Clone the Frontend Repository

Since the frontend relies on environment variables that are baked into the code at build-time, you must build the image yourself using your own Tailscale IPs. First, clone the Web UI source code:

```bash
git clone https://github.com/<YOUR_GITHUB_USERNAME>/stackr-webui.git
cd stackr-webui
```

---

## 2. Prepare the Client-Side Variables (.env.production)

Because Next.js runs in the user's browser, the public URLs must be injected into the static JavaScript at **build time**. 

In your newly cloned frontend directory, create a `.env.production` file configured with your Tailscale IPs:

```env
# ─────────────────────────────────────────────────────────────────────────────
# Inetum+ Platform — Environment Variables (Production / AKS)
# ─────────────────────────────────────────────────────────────────────────────

NEXT_PUBLIC_APP_URL=http://stackr.<YOUR_TAILSCALE_IP>.nip.io
NEXT_PUBLIC_APP_ENV=production

# Public URL used by the browser for SSO redirects
NEXT_PUBLIC_KEYCLOAK_URL=http://keycloak.<YOUR_TAILSCALE_IP>.nip.io
NEXT_PUBLIC_KEYCLOAK_REALM=Devsecops_Platform_Users
NEXT_PUBLIC_KEYCLOAK_CLIENT_ID=inetum-plus

# GitLab Admin (Central Source of Truth)
NEXT_PUBLIC_GITLAB_URL=http://gitlab.<YOUR_TAILSCALE_IP>.nip.io
GITLAB_GROUP=root
GITLAB_TENANT_REPO=platform-gitops
GITLAB_REGISTRY_PATH=registry
GITLAB_DEFAULT_BRANCH=main

# Argo CD
NEXT_PUBLIC_ARGOCD_URL=http://argocd.<YOUR_TAILSCALE_IP>.nip.io

# Cluster Base URL (per-tenant tool links)
NEXT_PUBLIC_CLUSTER_BASE_URL=http://<YOUR_TAILSCALE_IP>.nip.io

# FastAPI Backend
NEXT_PUBLIC_API_URL=http://platform-api.<YOUR_TAILSCALE_IP>.nip.io
```

---

## 3. Build and Push the Docker Image

With your `.env.production` file ready, build the image and push it to your Azure Container Registry (ACR).

```bash
# Build the image
docker build -t <YOUR_ACR_NAME>.azurecr.io/platform/frontend/webui:latest .

# Push to your registry
docker push <YOUR_ACR_NAME>.azurecr.io/platform/frontend/webui:latest
```

---

## 4. Inject Server-Side Secrets

Next.js handles secure tokens strictly on the server-side so they are never exposed to the browser. You must manually inject your secrets into the Kubernetes deployment manifest before applying it.

Open `BaseServices/overlays/admin_with_ui/webui.yaml` and update the following placeholders:

1.  **Image Name**: Replace `<YOUR_ACR_NAME>` with your actual registry.
2.  **`KEYCLOAK_CLIENT_SECRET`**: Paste your Keycloak Client Secret.
3.  **`KUBE_TOKEN`**: Paste your Kubernetes Service Account Token.

> 💡 **Where do I get these secrets?**
> - **KEYCLOAK_CLIENT_SECRET**: You created this in Phase 5! Log into Keycloak -> Clients -> `inetum-plus` -> Credentials, and copy the Secret.
> - **KUBE_TOKEN**: You created this in Phase 6 for the Platform API! Use the exact same token here.

```yaml
          env:
            - name: KEYCLOAK_INTERNAL_URL
              value: "http://keycloak-svc.admin:8080"
            - name: KEYCLOAK_CLIENT_SECRET
              value: "YOUR_ACTUAL_KEYCLOAK_SECRET"
            - name: KUBE_TOKEN
              value: "YOUR_ACTUAL_KUBE_TOKEN"
```

---

## 5. Update the Tailscale Ingress Rule

Open `BaseServices/overlays/admin_with_ui/webui-ingress.yaml` and replace `<YOUR_TAILSCALE_IP>` with your actual Tailscale IP:

```yaml
  - host: stackr.<YOUR_TAILSCALE_IP>.nip.io
```

---

## 6. Deploy the Stack!

You are now ready to spin up the entire cluster, complete with the Web UI!

Run the following command from the root of your GitOps repository:
```bash
kubectl apply -k BaseServices/overlays/admin_with_ui
```

Your Developer Portal is now live and accessible over your VPN at `http://stackr.<YOUR_TAILSCALE_IP>.nip.io`.

🎉 **Congratulations! Your Multi-Tenant GitOps Platform is 100% complete.**

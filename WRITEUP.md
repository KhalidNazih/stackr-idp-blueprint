# 🗺️ Stackr: Building a Secure Multi-Tenant GitOps Engine

This guide is designed to take you from zero to a fully automated, production-grade **GitOps Engine**. Beyond just provisioning an Azure Kubernetes Service (AKS) cluster, this architecture provides a complete multi-tenant foundation. You can also optionally deploy the Stackr Developer Portal on top of this to turn it into a full **Internal Developer Platform (IDP)**.

The platform is deployed securely with zero public exposure, relying entirely on **Tailscale** and **NGINX Ingress** to ensure your company's intellectual property and toolchains (GitLab, Jenkins, SonarQube, Nexus, Keycloak, OpenBao) are completely shielded from the internet.

---

## 🏗️ Phase 0: Azure Infrastructure Provisioning (AKS, ACR & Key Vault)

You must provision an AKS cluster and an Azure Container Registry (ACR) to host our internal backend platform images. 

Below is the manual configuration applied via the Azure Portal. *(Note: If you want an automated way to provision the infrastructure, use the Terraform file located in the `terraform/` directory of this repository!)*

### 1. The Core Infrastructure

*   **Cluster Name**: `<YOUR_CLUSTER_NAME>`
*   **Resource Group**: `<YOUR_RESOURCE_GROUP>`
*   **Region Location**: `<YOUR_REGION>` (Choose a region supported by your subscription).

### 2. The Compute Power (Node Pool)

*   **VM Size**: `<YOUR_VM_SIZE>` (e.g., Standard_D2s_v3).
*   **Scaling**: We set the auto-scaler to **min: 1** and **max: 2** nodes.
*   **Availability Zones**: `<YOUR_AVAILABILITY_ZONES>` (e.g., Zones 1, 2, 3).

### 3. The Network (Cilium CNI)

*   **Network Plugin**: Azure CNI Overlay powered by **Cilium**.
*   **Why we chose it**: Instead of the old Kubenet standard, Cilium uses modern eBPF technology in the Linux kernel. It is much faster and gives you advanced security capabilities (like Tetragon) without having to install heavy service meshes like Istio.

### 4. Identity & Security Features (Enabled)

We enabled two critical security add-ons required for your GitOps architecture:

*   **OIDC Issuer & Workload Identity**: Instead of using long-lived, hackable Service Principal passwords to talk to Azure, your pods use temporary identity tokens.
*   **Secrets Store CSI Driver**: This allows OpenBao (your Vault) to securely mount passwords directly from an Azure Key Vault into the Pod's memory without storing them in your Git repository.

### 5. Features we explicitly Disabled (To save RAM/Money)

*   **Azure Policy & Monitoring (Prometheus/Grafana)**: Disabled to save CPU/RAM overhead on your small nodes.
*   **Service Mesh (Istio)**: Disabled because it is too heavy for a 2-core node, and Cilium handles the routing perfectly anyway.
*   **Virtual Nodes & Image Cleaner**: Disabled to keep the architecture clean and simple.

---

### Step-by-Step Deployment

**Create Azure AKS Cluster:**
Create your AKS cluster through the Azure Portal using the exact configuration specified above.
<img width="959" height="448" alt="create_azure_aks" src="https://github.com/user-attachments/assets/6a53e9f9-ad50-49db-9da0-e42bf228f00c" />

### 2. Create Azure Container Registry (ACR)
Create an ACR to store your custom container images (e.g., `<YOUR_ACR_NAME>.azurecr.io`).
<img width="920" height="417" alt="acr_deployed" src="https://github.com/user-attachments/assets/99935c62-d247-4bb3-8ccb-51fab392873a" />

### 3. Attach ACR to AKS
Attach the ACR to the AKS cluster so the cluster can pull images securely without manual Docker logins.
<img width="955" height="355" alt="attach_acr_to_aks" src="https://github.com/user-attachments/assets/64857fa4-ca0f-4b65-b448-fa504e961060" />

### 4. Push Platform API to ACR
Build and push your backend platform image to the registry (e.g., `<YOUR_ACR_NAME>.azurecr.io/platform/backend/platform-api`).
<img width="808" height="395" alt="platform_api_pushed_to_acr" src="https://github.com/user-attachments/assets/2799d556-7589-4ea4-a5ae-cfb561c570fa" />

Run the following command to authenticate to your newly provisioned AKS cluster locally:
```bash
az aks get-credentials --resource-group <RESOURCE_GROUP> --name <CLUSTER_NAME>
```

### 5. Create Azure Key Vault & Managed Identity (For OpenBao Auto-Unseal)
To allow your OpenBao (Vault) to automatically unseal itself when the cluster boots, you must create a Key Vault and use OIDC to link it to your Kubernetes cluster.

1. **Create the Key Vault & Unseal Key**
   * Search for **Key vaults** in the portal and create one in your resource group.
   * Under **Access configuration**, select **Vault access policy**.
   * Once created, click **Keys**, then **Generate/Import**. Name it `openbao-unseal-key` (RSA) and create it.

2. **Create the Managed Identity**
   * Search for **Managed Identities** and create one named `openbao-identity`.
   * Open it and copy your **Client ID** and **Tenant ID**.

3. **Grant the Identity Access to the Vault**
   * Go back to your Key Vault, click **Access policies**, and click Create.
   * For **Key permissions**, select **Get**, **Wrap Key**, and **Unwrap Key**.
   * For **Principal**, select `openbao-identity` and click Create.

4. **Wire it to Kubernetes via OIDC**
   * Go to your AKS cluster Overview and copy the **OIDC Issuer URL**.
   * Go to your `openbao-identity` Managed Identity, click **Federated credentials**, and add one:
     * **Scenario**: Kubernetes accessing Azure resources
     * **Cluster OIDC issuer URL**: *(paste your URL)*
     * **Namespace**: `admin`
     * **Service account**: `openbao-sa`
     * **Credential name**: `openbao-fed-cred`

Finally, paste your copied **Client ID**, **Tenant ID**, and **Vault Name** into both `BaseServices/base/deployment/openbao-config.hcl` and `BaseServices/base/deployment/openbao-sa.yaml` before running your Kustomize deployment.

---

## 🔐 Phase 1: Secure Networking & Ingress (Tailscale + NGINX)

Our security posture mandates that no services are exposed to the public internet. We use Tailscale to provide a private VPN into the cluster, and NGINX Ingress to route traffic.

### 1. Install NGINX Ingress Controller
Install the F5 NGINX Ingress Controller. Configure it as an internal load balancer so it isn't assigned a public IP by Azure.
<img width="684" height="341" alt="install_the_f5_nginx_ingress_controller_internal" src="https://github.com/user-attachments/assets/9633b0fe-cc44-4928-bef1-9059e839c9b1" />

### 2. Install & Configure Tailscale Operator
Install the Tailscale Kubernetes Operator. You will need to provide an OAuth client ID and secret or an Auth Key from your Tailscale Admin Console.
<img width="634" height="392" alt="install_tailscale2" src="https://github.com/user-attachments/assets/7a633b4c-fcd5-47ac-93a8-ec5e306117bd" />


### 3. Expose NGINX to Tailnet
By annotating the NGINX Ingress LoadBalancer service, the Tailscale Operator intercepts it and creates a Tailscale Proxy Pod, securely exposing the Ingress controller to your Tailnet.
```yaml
# Add this annotation to your NGINX LoadBalancer service
tailscale.com/expose: "true"
```
<img width="766" height="357" alt="tailscale_proxy_pod" src="https://github.com/user-attachments/assets/f4bd5176-8e14-42e0-9da6-a8abe18f6028" />


Once connected, your NGINX Ingress Controller will appear as a new device in your Tailscale Admin Console. Take note of its assigned Tailscale IP (e.g., `<YOUR_TAILSCALE_IP>`).
<img width="863" height="285" alt="new_device_tailsale_nginx" src="https://github.com/user-attachments/assets/c26cc61c-5c1f-476e-a240-06210229114c" />

### 4. Connect Your Laptop to the Tailnet
Because all ingress traffic is completely private, you cannot access the cluster from the public internet. To interact with your GitOps Platform from your laptop:
1. Download and install the [Tailscale Desktop Client](https://tailscale.com/download) (available for Windows, Mac, and Linux).
2. Click the Tailscale icon in your system tray and select **Log in**.
3. **Authenticate using your own corporate email**. *(Note: The Tailscale administrator must either invite your email address to the company Tailnet via the Tailscale Admin Console, or the Tailnet must be integrated with your company's SSO like Microsoft Entra ID or Google Workspace).*
4. Your laptop is now securely tunneled directly into the cluster! You will be able to access the `100.x.x.x.nip.io` URLs from your local browser seamlessly.

---

## 🏗️ Phase 2: Bootstrapping the Core

With the infrastructure and secure networking in place, you must deploy the "Core Foundation" (GitLab, Keycloak, OpenBao, Redis, Postgres, and the Platform API). All services are deployed as `ClusterIP` to prevent unauthorized cluster-internal access.

### 1. Install Secrets Store CSI Driver & Vault Provider
The Core Stack uses `SecretProviderClass` configurations (for Zero-Secret-on-Disk projection). You must install the CSI Driver and Vault Provider before applying Kustomize manifests.
```bash
# Add Helm repositories
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install CSI Driver
helm upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true
```

> [!WARNING]
> **Helm Conflict Troubleshooting:** If you receive an error about existing CRDs or CSIDriver objects (e.g., `invalid ownership metadata`), it means AKS or a previous script pre-created them. Run the following to clean them up before retrying the Helm command:
> ```bash
> kubectl delete crd secretproviderclasses.secrets-store.csi.x-k8s.io secretproviderclasspodstatuses.secrets-store.csi.x-k8s.io
> kubectl delete csidriver secrets-store.csi.k8s.io
> ```

```bash
# Install Vault Helm (Agent/CSI mode only)
helm upgrade --install vault hashicorp/vault \
  --namespace admin \
  --create-namespace \
  --set "csi.enabled=true"
```

### 2. Deploy the Core Stack via Kustomize
Apply the `BaseServices` folder using the standard `admin` overlay to spin up your headless core architecture:
```bash
kubectl apply -k BaseServices/overlays/admin
```

> [!NOTE]
> **Expected Behavior:** Because we deploy everything simultaneously for a complete GitOps state, the `platform-api` and `postgres` pods will be stuck in a `ContainerCreating` crash-loop right now! This is completely normal because they are waiting to mount secrets from OpenBao, but OpenBao is completely empty right now. Don't worry! They will automatically turn green at the end of **Phase 6** when we configure OpenBao.

<img width="826" height="243" alt="image" src="https://github.com/user-attachments/assets/79aa62cf-954e-46d7-80f0-30160d19b7d3" />

### 3. Identify your Entry Points
The platform uses NGINX Ingress combined with Tailscale and wildcard DNS via `nip.io` for secure private routing. Assuming your Tailscale Ingress IP is `<YOUR_TAILSCALE_IP>`:

**Take note of your Ingress URLs:**
*   **GitLab**: `http://gitlab.<YOUR_TAILSCALE_IP>.nip.io`
*   **Keycloak**: `http://keycloak.<YOUR_TAILSCALE_IP>.nip.io`
*   **OpenBao**: `http://vault.<YOUR_TAILSCALE_IP>.nip.io`
*   **Platform API**: `http://api.<YOUR_TAILSCALE_IP>.nip.io`

---

## 🏗️ Phase 3: The Source of Truth (GitLab Setup)

### 1. Repository Initialization
1. Ensure your Tailscale VPN is active on your machine. Log in to your new GitLab (Default user: `root`).
   *Note: To retrieve your initial admin password, run:*
   ```bash
   kubectl exec -it -n admin deploy/gitlab -- grep 'Password:' /etc/gitlab/initial_root_password
   ```
2. Create a new project: `platform-gitops`.
3. Push this repository to that project. **This is now your Source of Truth.**

### 2. The Admin Access Token
1. Go to **Edit Profile** -> **Access** -> **Personal access tokens**.
2. Create a token named `PLATFORM_ADMIN_TOKEN` with `api` scope.
3. **SAVE THIS**. You will need it for the Platform API.

<img width="742" height="401" alt="image" src="https://github.com/user-attachments/assets/9b03989e-899b-4d0c-8980-4705f3145801" />

---

## 🧠 Phase 4: The Brain (Argo CD Setup)

### 1. Install & Expose Argo CD
Run the following commands to install Argo CD on your cluster and expose it via Ingress:

```bash
# Create the namespace
kubectl create namespace argocd

# Install Argo CD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Apply the ApplicationSet CRD (required for the ApplicationSet controller)
kubectl apply --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/crds/applicationset-crd.yaml

# Disable default HTTPS (run in insecure mode for HTTP lab access)
kubectl patch cm argocd-cmd-params-cm -n argocd --type merge -p '{"data": {"server.insecure": "true"}}'
kubectl rollout restart deploy argocd-server -n argocd

# Enable apiKey capability for the admin account (required to generate tokens)
kubectl patch cm argocd-cm -n argocd --type merge -p '{"data": {"accounts.admin": "apiKey, login"}}'

# Expose Argo CD via Ingress (Replace with your actual Tailscale IP if different)
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: argocd.<YOUR_TAILSCALE_IP>.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF
```

*Note: To retrieve the default `admin` password to log in, run:*
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
> **👉 Log In**: Open your browser and navigate to your Ingress URL (e.g., `http://argocd.<YOUR_TAILSCALE_IP>.nip.io`). Log in using the username `admin` and the password you just extracted!

### 2. Connect GitLab to Argo CD
1. Open Argo CD UI -> **Settings** -> **Repositories**.
2. **Connect Repo**: Click **Connect Repo using HTTPS** and configure:
   * **Repository URL**: `http://gitlab.admin/root/platform-gitops.git` (Use this internal DNS name so it is portable and matches the Orchestrator config!)
   * **Username**: `root`
   * **Password**: Your GitLab initial root password or Personal Access Token.
3. **Settings** -> **Projects**: Ensure the `default` project is ready.
<img width="845" height="158" alt="image" src="https://github.com/user-attachments/assets/b7c9bdf6-30ae-4942-ba13-9967efaedb33" />

### 3. Generate the ARGOCD_TOKEN (Web UI)
1. Go to **Settings** -> **Accounts** -> Select `admin`.
2. Click **Generate Token**. Set ID to `platform-api` and Expiration to `No Expiry`.
3. **SAVE THIS**.
<img width="844" height="443" alt="image" src="https://github.com/user-attachments/assets/2a1759a0-faa6-4c0c-a5e6-6cae2d00d48c" />
---

## 🔐 Phase 5: The Foundation (OpenBao & Keycloak)

### 1. Initialize OpenBao (Auto-Unseal)
OpenBao boots up "Sealed" by default on its first run. Because we wired it to Azure Key Vault, it will automatically unseal itself, but you still need to initialize it to get your Master Root Token and Recovery Keys.

1. **Initialize the Vault**:
   ```bash
   kubectl exec -it -n admin deploy/openbao -- bao operator init
   ```
   **CRITICAL**: Save the output! You will receive several `Recovery Keys` and one `Initial Root Token`. Do not lose the Root Token.

2. **Verify Auto-Unseal**: Check the status of your vault:
   ```bash
   kubectl exec -it -n admin deploy/openbao -- bao status
   ```
   You should see `Sealed: false`. (If it is true, it means your Azure Key Vault connection is misconfigured).

Once initialized, you must configure Vault to allow the Provisioner (Ansible) to write secrets automatically.
1. **Open an interactive shell inside the OpenBao container**:
   ```bash
   kubectl exec -it -n admin deploy/openbao -- /bin/sh
   ```
2. **Login to OpenBao** (run this inside the container shell):
   ```bash
   bao login [ROOT_TOKEN]
   ```
3. **Enable Secrets Engine & Auth** (run these inside the container shell):
   ```bash
   # Enable KV-V2 engine
   bao secrets enable -path=secret kv-v2

   # Enable Kubernetes Auth
   bao auth enable kubernetes
   
   # Configure Auth to trust the cluster
   bao write auth/kubernetes/config \
       kubernetes_host="https://kubernetes.default.svc"
   ```
4. **Create the Provisioner and Platform Policies & Roles** (run these inside the container shell):
   ```bash
   # A. Tenant Provisioner Config:
   echo 'path "secret/data/tenants/*" { capabilities = ["create", "read", "update", "delete", "list"] }' | bao policy write tenant-provisioner-policy -

   bao write auth/kubernetes/role/tenant-role \
       bound_service_account_names="*" \
       bound_service_account_namespaces="*" \
       policies=tenant-provisioner-policy \
       ttl=1h

   # B. Base Platform Components Config:
   echo 'path "secret/data/platform/*" { capabilities = ["read"] }' | bao policy write platform-policy -

   bao write auth/kubernetes/role/platform-role \
       bound_service_account_names="*" \
       bound_service_account_namespaces="admin" \
       policies=platform-policy \
       ttl=1h
   ```

### 3. Keycloak: Realm, Scope, & Client Setup
1. **Create the Realm**:
   1. Open the Keycloak Admin Console (http://keycloak.<YOUR_TAILSCALE_IP>.nip.io) and log in (default credentials: `admin` / `admin`).
   2. Click the realm dropdown in the top-left corner (initially labeled **master**).
   3. Click **Create Realm**, set the **Realm name** to `Devsecops_Platform_Users`, and click **Create**.
2. **Configure the Groups Scope**:
   1. Ensure you have switched to the **Devsecops_Platform_Users** realm in the top-left dropdown.
   2. Go to **Client Scopes** -> Click **Create Client Scope** -> Name it `groups`.
   3. Inside the `groups` scope, go to the **Mappers** tab -> Click **Configure a new mapper** (or **Add mapper** -> **By configuration**) -> Select **Group Membership**.
   4. Set the **Token Claim Name** to `groups`. Ensure **Add to ID token** and **Add to access token** are toggled on.
3. **Create the Platform Client (For Web UI & API)**:
   1. Go to **Clients** -> **Create client**.
   2. Set **Client type** to `OpenID Connect` and **Client ID** to `inetum-plus`. Click Next.
   3. Toggle **Client authentication** to ON, and click Save.
   4. Go to the **Credentials** tab and **Copy the Client Secret** (You will need this for the Web UI and OpenBao).
   5. Go to the **Settings** tab, scroll down to **Valid redirect URIs**, and add `http://platform.<YOUR_TAILSCALE_IP>.nip.io/*`. Click Save.

<img width="1634" height="437" alt="image" src="https://github.com/user-attachments/assets/9b4c67f4-07e9-4be8-b372-d477788f7b32" />

---

## 🧩 Phase 6: The Token Hunt (Secret Injection)

### 1. Extract the KUBE_TOKEN
```bash
kubectl get secret platform-api-token -n admin -o jsonpath='{.data.token}' | base64 -d
```
<img width="1694" height="166" alt="image" src="https://github.com/user-attachments/assets/148653a5-7a30-4248-9391-09d644bf7532" />

### 2. Inject into OpenBao
Login to OpenBao and write the `platform/api` secret:

> **💡 TIP**: You can find your numeric `GITLAB_PROJECT_ID` on the project's home page in GitLab, right under the project name.

```bash
kubectl exec -it -n admin deploy/openbao -- /bin/sh
# Inside the pod:
bao kv put secret/platform/api \
    API_SECRET_KEY="[YOUR_CUSTOM_RANDOM_KEY]" \
    ARGOCD_TOKEN="[PHASE 4 TOKEN]" \
    ARGOCD_URL="http://argocd-server.argocd" \
    DATABASE_URL="postgresql+asyncpg://inetum:inetum_secret@postgres-svc.admin:5432/inetum_platform" \
    GITLAB_DEFAULT_BRANCH="main" \
    GITLAB_GROUP="[YOUR_GITLAB_GROUP]" \
    GITLAB_PROJECT_ID="[YOUR_REPO_ID]" \
    GITLAB_REGISTRY_PATH="registry" \
    GITLAB_TENANT_REPO="platform-gitops" \
    GITLAB_TOKEN="[PHASE 3 TOKEN]" \
    GITLAB_URL="http://gitlab.admin" \
    KEYCLOAK_CLIENT_ID="admin-cli" \
    KEYCLOAK_CLIENT_SECRET="unused" \
    KEYCLOAK_INTERNAL_URL="http://keycloak.admin:8080" \
    KEYCLOAK_REALM="master" \
    KUBE_API_URL="https://kubernetes.default.svc" \
    KUBE_TOKEN="[PHASE 6 KUBE_TOKEN]" \
    REDIS_URL="redis://redis-svc.admin:6379/0"

# Also write the platform Postgres credentials:
bao kv put secret/platform/postgres \
    POSTGRES_DB="inetum_platform" \
    POSTGRES_USER="inetum" \
    POSTGRES_PASSWORD="inetum_secret"
```

### 3. Restart the Dependent Pods
Because the entire architecture was deployed simultaneously, the `platform-api` and `postgres` pods likely got stuck in a `ContainerCreating` loop waiting for these secrets to exist. 

Delete them to force Kubernetes to instantly recreate them so they pull your new secrets immediately!
```bash
kubectl delete pod -n admin -l app=platform-api
kubectl delete pod -n admin -l app=postgres
```

<img width="956" height="451" alt="image" src="https://github.com/user-attachments/assets/03ca026e-5533-4c04-bec0-14db36e728e1" />

---

## 🚀 Phase 7: Tenant Lifecycle (Tool Integration)

### 1. GitLab Admin Mapping (Ruby)
We solve the "CE doesn't have group sync" problem with this initializer:
```ruby
Warden::Manager.after_set_user do |user, auth, opts|
  raw_groups = auth.env['omniauth.auth']&.dig('extra', 'raw_info', 'groups') || []
  user.update_attribute(:admin, true) if raw_groups.include?("{{ .Values.access.groups.admins }}")
end
```

### 2. Jenkins `${readFile}`
Jenkins reads its secret directly from the CSI RAM-disk:
```yaml
clientSecret: "${readFile:/mnt/secrets/jenkins-secret}"
```

### 3. Nexus & Sonarqube Zero-Secret-on-Disk
Both Nexus (via `oauth2-proxy`) and Sonarqube consume OIDC secrets securely from the CSI mount. During initial deployments, the admin configures OIDC using credentials provisioned by Ansible and projected into RAM at `/mnt/secrets`.

---

## 🏗️ Phase 8: Onboarding a Tenant (The Registry)

### 1. Launch the Orchestrator
Apply the ApplicationSet to start the "watch" on your registry:
```bash
kubectl apply -f system/ApplicationSet.yaml
```

### 2. Create a Tenant File
Create a file like `registry/customer-01.yaml`. Notice we are using Tailscale `nip.io` ingress URLs instead of NodePorts.
```yaml
tenant_id: "customer-01"
display_name: "Customer Project 1"
business_unit: "Telecom"
environment: "dev"
infrastructure:
  cluster_server: "https://kubernetes.default.svc"
isolation:
  namespace: "customer-01-ns"
platform:
  public_base_url: "http://<YOUR_TAILSCALE_IP>.nip.io"
  keycloak:
    internal_url: "http://keycloak-svc.admin:8080"
    public_url: "http://keycloak.<YOUR_TAILSCALE_IP>.nip.io"
    realm: "Devsecops_Platform_Users"
  secrets:
    name: "customer-01-secrets"
services:
  jenkins:
    enabled: true
    client_id: "Jenkins"
    replicas: 1
  gitlab:
    enabled: true
    client_id: "Gitlab"
  nexus:
    enabled: false
    client_id: "nexus"
  sonarqube:
    enabled: false
    client_id: "sonarqube"
access:
  groups:
    admins: "customer-01-admins"
    users: "customer-01-users"
    developers:
      - "developer1@example.com"
      - "developer2@example.com"
  creator_email: "creator@example.com"
```

### 3. Commit and Push
```bash
git add registry/customer-01.yaml
git commit -m "add: tenant customer-01"
git push origin main
```

### 4. Automatic Flow
1. **Argo CD** detects the new file in `/registry`.
2. It generates a new **Namespace** `customer-01`.
3. It triggers a **PreSync Job**: Ansible creates the Keycloak groups and OIDC clients, then pushes the secrets to OpenBao.
4. Once Ansible is successful, Argo CD deploys **Jenkins**, **GitLab**, **Nexus**, or **Sonarqube**.
5. The **CSI Driver** mounts the secrets into the pods. **Your tenant is ready and accessible via Tailscale VPN.**

---

## 🛠️ Troubleshooting & Power Commands

| Component | Command | Purpose |
| :--- | :--- | :--- |
| **OpenBao** | `kubectl exec -n admin deploy/openbao -- bao status` | Check if Vault is **Sealed** |
| **CSI Driver** | `kubectl get secretproviderclasspodstatuses -A` | Verify secret projection into RAM |
| **Provisioner** | `kubectl logs -n [NS] -l job-name=provisioner` | Debug Ansible Keycloak automation |
| **Global Events** | `kubectl get events -A --sort-by='.lastTimestamp' \| tail -n 20` | See the latest cluster errors |
| **Stuck Pods** | `kubectl get pods -A \| grep -v 'Running\|Completed'` | Quickly find crashing or stuck pods across all namespaces |
| **Pod Errors** | `kubectl describe pod -n <ns> <pod>` | Debug `ContainerCreating` errors (e.g., `FailedAttachVolume`, `FailedMount`) |
| **Crash Logs** | `kubectl logs -n <ns> -l app=<app-name>` | Debug application start crashes (e.g., Postgres `lost+found` error) |
| **CSI Drivers** | `kubectl get pods -n kube-system \| grep csi` | Verify Azure Secrets & Storage CSI drivers are running |
| **Azure Disk Fix** | `kubectl scale deploy <name> -n <ns> --replicas=0`<br>`sleep 15`<br>`kubectl scale deploy <name> -n <ns> --replicas=1` | Fix Azure "Dangling Disk Attachment" deadlocks (`FailedAttachVolume`) by forcing the cluster autoscaler to detach/recreate |

<img width="959" height="426" alt="argocd_ui" src="https://github.com/user-attachments/assets/c2e2ae90-5bbb-462e-a761-9ec14f52753e" />

---

## 🌐 Phase 9: Deploying the Developer Portal (Optional)

Now that your entire GitOps platform is successfully running headless, you can optionally deploy the **Stackr Web UI**. 

Because you've already configured Keycloak and OpenBao, you already have the necessary `Client Secret` and `Kube Token` required to boot the frontend!

👉 **[Click here to follow the Web UI Configuration Guide](WEBUI_SETUP.md)** to build the frontend image and apply the `admin_with_ui` overlay!

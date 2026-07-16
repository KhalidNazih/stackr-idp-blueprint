# Stackr: Building a Secure Multi-Tenant GitOps Engine

This repository implements a production-grade, GitOps-driven architecture designed to function as a robust automation engine for your company. It automates the provisioning and secure management of multi-tenant environments, empowering development teams with isolated access to enterprise toolchains (GitLab, Jenkins, Nexus, SonarQube). **You can also optionally deploy the Stackr Developer Portal (Web UI) on top of this engine to create a fully-fledged Internal Developer Platform (IDP).**

The platform leverages a "Security-First" philosophy, ensuring that sensitive credentials never persist to physical storage, and strictly enforces zero public exposure by routing all traffic through a private Tailscale VPN.

## 🏛️ Core Architectural Principles

### 1. Declarative GitOps Lifecycle
The platform follows a strict declarative model using **Argo CD** and the **ApplicationSet controller**. 
*   **Source of Truth**: The `/registry` directory serves as the definitive state for all tenant configurations.
*   **Continuous Reconciliation**: The platform automatically detects and reconciles changes in the registry, ensuring that the live cluster state remains synchronized with the version-controlled manifests.

### 2. Identity Before Infrastructure (IBI) Mandate
To prevent unauthenticated service exposure, the platform enforces an **IBI mandate**.
*   **Pre-Sync Orchestration**: Using Argo CD Sync Waves and Hooks, an **Ansible-based provisioner** executes before any application infrastructure is deployed.
*   **Dynamic Identity Provisioning**: The provisioner automatically configures Keycloak realms, groups, and OIDC/SAML clients, ensuring that the identity provider (IdP) is fully operational and secured before tool deployment begins.

### 3. Zero-Secret-on-Disk (ZSoD) Posture
A primary security objective is the elimination of standard Kubernetes Secret objects for sensitive tenant and platform credentials.
*   **Encrypted Secret Engine**: **OpenBao (Vault)** serves as the authoritative source for all secrets.
*   **RAM-Disk Projection**: The **Secrets Store CSI Driver** projects secrets directly into Pod memory spaces via `tmpfs` mounts. 
*   **Attack Surface Reduction**: By ensuring sensitive data exists only in RAM, the platform effectively mitigates the risk of secret exposure through etcd compromises or physical disk forensics.

### 4. Policy Governance & Admission Control (Kyverno)
The platform achieves "Full Control" over the cluster's security posture via **Kyverno**.
*   **Trusted Registry Enforcement**: Mandatory blocking of images from public/external sources. All workloads must pull from the verified internal **Nexus Registry**.
*   **Hardened Pod Security Standards**: Strict prohibition of `privileged: true` containers and `hostPath` mounts to prevent container breakouts and host-level lateral movement.
*   **Deterministic Resource Management**: Enforcement of `resources.limits` and `resources.requests` for every workload to prevent "noisy neighbor" scenarios and ensure cluster stability.
*   **Automated Label Injection (Metadata Governance)**: Mutation policies that automatically inject `tenant-id` labels for precise auditing, cost-center allocation, and platform-wide observability.

### 5. eBPF-Based Runtime Security (Tetragon)
For "Full Security" at the kernel level, the platform utilizes **Tetragon** for real-time observability and enforcement.
*   **Process Execution Filtering**: Real-time blocking of unauthorized binaries (e.g., `nmap`, `nc`, `curl`, `wget`) within production namespaces to neutralize the "post-exploitation" phase of an attack.
*   **Sensitive File Access (FIM)**: Kernel-level protection of the **`/mnt/secrets`** RAM-disk. Tetragon terminates any unauthorized process attempting to read, copy, or exfiltrate credentials from the secret mount.
*   **Network Egress Control**: Continuous tracing and alerting on outbound connection attempts to unauthorized external IP ranges, preventing Command & Control (C2) communication.
*   **Privilege Escalation Detection**: Automated detection and blocking of `setuid` binaries or unexpected capability transitions at the kernel level to prevent local privilege escalation.

## 🚀 Provisioning Workflow

1.  **Registry Enrollment**: A tenant YAML configuration is committed to the `/registry` folder.
2.  **Controller Synthesis**: The ApplicationSet controller generates the tenant's Argo CD Application.
3.  **Identity Bootstrap**: An Ansible job (PreSync) provisions the required OIDC clients in Keycloak and populates the secret paths in OpenBao.
4.  **Policy Validation**: Kyverno validates the generated manifests against the platform's security policies.
5.  **Secure Workload Deployment**: Application Pods are deployed with a `SecretProviderClass` reference.
6.  **CSI Mounting**: The Secrets Store CSI Driver performs a K8s-to-Vault token exchange and mounts secrets to `/mnt/secrets` as an in-memory volume.
7.  **Runtime Monitoring**: Tetragon begins monitoring the new Pods' kernel-level activities to ensure runtime integrity.

## 🛠️ Technical Stack

*   **Orchestration**: Argo CD (ApplicationSets, Sync Waves, Hooks)
*   **Identity Management**: Keycloak (OIDC/SAML)
*   **Secret Management**: OpenBao (Vault), Secrets Store CSI Driver
*   **Security Policy**: Kyverno (Admission Control)
*   **Runtime Security**: Tetragon (eBPF-based Enforcement)
*   **Automation**: Ansible (Keycloak & OpenBao API modules)
*   **Infrastructure**: Azure Kubernetes Service (AKS)
*   **Networking & Ingress**: NGINX Ingress Controller, Tailscale (Private Ingress), `nip.io`

---

## 📖 Operational Procedures

For detailed bootstrapping, cluster initialization, and E2E tool integration (Jenkins, GitLab, Nexus, Sonarqube), refer to the **[WRITEUP.md](./WRITEUP.md)**.

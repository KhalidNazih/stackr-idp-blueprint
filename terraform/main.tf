terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

# 1. Create Azure Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "<YOUR_RESOURCE_GROUP_NAME>"
  location = "<YOUR_REGION_LOCATION>" # e.g. westeurope
}

# 2. Create Azure Container Registry (ACR)
resource "azurerm_container_registry" "acr" {
  name                = "<YOUR_ACR_NAME>" # Must be globally unique, e.g. stackrregistry
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# 3. Create Azure Kubernetes Service (AKS)
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "<YOUR_CLUSTER_NAME>" # e.g. Stackr
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "<YOUR_DNS_PREFIX>"

  # The Compute Power (Node Pool)
  default_node_pool {
    name                = "default"
    vm_size             = "<YOUR_VM_SIZE>" # e.g. Standard_D2s_v3
    enable_auto_scaling = true
    min_count           = 1
    max_count           = 2
    zones               = ["2", "3"]
  }

  identity {
    type = "SystemAssigned"
  }

  # The Network (Cilium CNI)
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    ebpf_data_plane     = "cilium"
  }

  # Identity & Security Features
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  tags = {
    Environment = "Production"
    Project     = "GitOps Platform"
  }
}

# 4. Attach ACR to AKS (Allow AKS to pull images from ACR)
resource "azurerm_role_assignment" "aks_to_acr" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

# 5. Create the Managed Identity for OpenBao
resource "azurerm_user_assigned_identity" "openbao" {
  name                = "openbao-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# 6. Create the Azure Key Vault for Auto-Unseal
resource "azurerm_key_vault" "vault" {
  name                       = "<YOUR_UNIQUE_VAULT_NAME>" # Must be globally unique
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = false # Set to true for production

  # Grant the Managed Identity Access to the Vault
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = azurerm_user_assigned_identity.openbao.principal_id

    key_permissions = [
      "Get",
      "WrapKey",
      "UnwrapKey",
    ]
  }

  # Grant your local user access to the Vault so Terraform can create the key
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create",
      "Delete",
      "Get",
      "Purge",
      "Recover",
      "Update",
      "GetRotationPolicy",
      "SetRotationPolicy"
    ]
  }
}

# 7. Create the Unseal Key
resource "azurerm_key_vault_key" "unseal_key" {
  name         = "openbao-unseal-key"
  key_vault_id = azurerm_key_vault.vault.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "wrapKey",
    "unwrapKey",
  ]
  
  depends_on = [
    azurerm_key_vault.vault
  ]
}

# 8. Wire the Identity to Kubernetes via OIDC
resource "azurerm_federated_identity_credential" "openbao_fed" {
  name                = "openbao-fed-cred"
  resource_group_name = azurerm_resource_group.rg.name
  parent_id           = azurerm_user_assigned_identity.openbao.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:admin:openbao-sa"
}


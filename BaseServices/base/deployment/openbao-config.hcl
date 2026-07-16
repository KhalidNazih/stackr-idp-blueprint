storage "file" {
  path = "/bao/data"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

seal "azurekeyvault" {
  tenant_id  = "<YOUR_AZURE_TENANT_ID>"
  client_id  = "<YOUR_MANAGED_IDENTITY_CLIENT_ID>"
  vault_name = "<YOUR_KEY_VAULT_NAME>"
  key_name   = "openbao-unseal-key"
}

ui = true
disable_mlock = true

# 1. Terraform & Provider Configuration
terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # The Azure DevOps pipeline will inject storage account details here during 'init'
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

# 2. Reference your EXISTING Resource Group
data "azurerm_resource_group" "main" {
  name = "VisualStudioOnline-B7676031D19941C29CB021209999B63D"
}

# 3. Reference your EXISTING Container Registry
data "azurerm_container_registry" "acr" {
  name                = "ecomprojectregistry"
  resource_group_name = data.azurerm_resource_group.main.name
}

# 4. Create Virtual Network inside the existing RG
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-ecom-prod"
  address_space       = ["10.0.0.0/16"]
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
}

# 5. Create Subnet for AKS nodes
resource "azurerm_subnet" "aks_subnet" {
  name                 = "snet-aks-nodes"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# 6. Create the AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-ecom-cluster"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  dns_prefix          = "ecomk8s"
  node_resource_group = "rg-ecom-aks-nodes"

  default_node_pool {
    name           = "default"
    node_count     = 1
    
    # SWITCHING TO D-SERIES (More likely to have quota)
    vm_size        = "Standard_B2ms" 
    
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    load_balancer_sku  = "standard"
    service_cidr       = "172.16.0.0/16"
    dns_service_ip     = "172.16.0.10"
    # docker_bridge_cidr removed to fix warnings
  }


  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

# 7. Role Assignment: Grant AKS permission to pull from ACR
# This is why the 'arm-connection' needs OWNER access on the RG
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = data.azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

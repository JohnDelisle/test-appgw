
provider "azurerm" {
  features {}
}

locals {
  location                           = "eastus2"
  sub_key                            = "app505"
  sdlc                               = "jmd"
  product                            = "testappgw"
  resource_group_name                = "${local.sub_key}-${local.product}-${local.sdlc}-${local.location}"
  appgw_name                         = "${local.resource_group_name}-appgw"
  backend_address_pool_name          = "${local.appgw_name}-pool"
  frontend_port_name_prefix          = "${local.appgw_name}-port"
  frontend_pub_ip_configuration_name = "${local.appgw_name}-pub-feip"
  gateway_ip_configuration_name      = "${local.appgw_name}-gwip"
  http_setting_name_prefix           = "${local.appgw_name}-http"
  http_listener_name_prefix          = "${local.appgw_name}-listener"
  request_routing_rule_name_prefix   = "${local.appgw_name}-rule"
  probe_name_prefix                  = "${local.appgw_name}-probe"
}

resource "azurerm_resource_group" "rg" {
  name     = local.resource_group_name
  location = local.location
}


// comment out after first apply
resource "azurerm_user_assigned_identity" "appgw_identity" {
  name                = "${local.appgw_name}-identity"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

// comment out after first apply
output "appgw_identity_id" {
  value = azurerm_user_assigned_identity.appgw_identity.id
}

// obtained after first apply - change "resourceGroups" to "ResourceGroups" and re-apply to test
// enable after first apply
/*
locals {
  appgw_identity_id = "XXXXXXXXXXXXXXXXXXXXXX"
}
*/

resource "azurerm_virtual_network" "vnet" {
  name                = "${azurerm_resource_group.rg.name}-vnet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "frontend" {
  name                 = "frontend"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.0.0/24"]
}

resource "azurerm_subnet" "backend" {
  name                 = "backend"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_public_ip" "appgw_pip" {
  name                = "${local.appgw_name}-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  allocation_method   = "Static"
}

resource "azurerm_application_gateway" "appgw" {
  name                = local.appgw_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  identity {
    type = "UserAssigned"
    // swap after first apply
    identity_ids = [azurerm_user_assigned_identity.appgw_identity.id]
    //identity_ids = [local.appgw_identity_id]
  }

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  autoscale_configuration {
    min_capacity = 1
    max_capacity = 3
  }

  frontend_ip_configuration {
    name                 = local.frontend_pub_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  frontend_port {
    name = "${local.frontend_port_name_prefix}-80"
    port = 80
  }

  http_listener {
    name                           = "${local.http_listener_name_prefix}-80"
    frontend_ip_configuration_name = local.frontend_pub_ip_configuration_name
    frontend_port_name             = "${local.frontend_port_name_prefix}-80"
    protocol                       = "http"
  }

  gateway_ip_configuration {
    name      = local.gateway_ip_configuration_name
    subnet_id = azurerm_subnet.frontend.id
  }

  backend_address_pool {
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    name                                = "${local.http_setting_name_prefix}-80"
    port                                = 80
    protocol                            = "http"
    cookie_based_affinity               = "disabled"
    pick_host_name_from_backend_address = false
    request_timeout                     = 300
    probe_name                          = "${local.probe_name_prefix}-80"
  }

  probe {
    name                = "${local.probe_name_prefix}-80"
    protocol            = "Http"
    path                = "/"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    host                = "test.example.com"
    match {
      status_code = ["200-399"]
      body        = ""
    }
  }

  request_routing_rule {
    name                       = "${local.request_routing_rule_name_prefix}-80"
    rule_type                  = "Basic"
    http_listener_name         = "${local.http_listener_name_prefix}-80"
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = "${local.http_setting_name_prefix}-80"
  }
}

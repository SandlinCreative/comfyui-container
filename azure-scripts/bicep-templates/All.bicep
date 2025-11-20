targetScope = 'subscription'

param appName string

@allowed([
  'prd'
  'stg'
  'dev'
])
param environment string

@allowed([
  'centralus'
  'eastus'
  'eastus2'
  'westus'
])
param location string

var resourceGroupName = '${appName}-${environment}'

module resourceGroup 'ResourceGroup.bicep' = {
  name: 'rg-${resourceGroupName}'
  params: {
    location: location
    rgName: resourceGroupName
  }
}

module dataOpsGroup 'DataOpsSecurityGroup.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${resourceGroupName}-dataops-group-${location}'
  dependsOn: [
    resourceGroup
  ]
}

module websiteGroup 'WebsiteSecurityGroup.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${resourceGroupName}-website-group-${location}'
  dependsOn: [
    mainWebsite
  ]
}

module appConfig 'AppConfiguration.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${resourceGroupName}-appconfig-${location}'
  params: {
    sku: environment == 'prd' ? 'standard' : 'free'
  }
  dependsOn: [
    resourceGroup
  ]
}

module vnet 'Subnet.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${resourceGroupName}-vnet-${location}'
  dependsOn: [
    resourceGroup
  ]
}

module keyVault 'KeyVault.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${resourceGroupName}-keyvault-${location}'
  dependsOn: [
    vnet
  ]
}

module appServicePlan 'WebPlan.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${resourceGroupName}-asp-${location}'
  dependsOn: [
    resourceGroup
  ]
}

module mainWebsite 'WebSite.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${resourceGroupName}-mainweb-${location}'
  params: {
    dotnetVersion: dotnetVersion
  }
  dependsOn: [
    vnet
    appServicePlan
  ]
}

module assignRoles 'RoleBasedAccess.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${resourceGroupName}-role-based-access-${location}'
  dependsOn: [
    websiteGroup
  ]
}

module commService 'CommunicationService.bicep' = {
  scope: az.resourceGroup(resourceGroupName)
  name: '${resourceGroupName}-communication-${location}'
  dependsOn: [
    emailService
  ]
}

metadata description = 'Creates an Azure API Management instance with MCP API configuration.'

param name string
param location string = resourceGroup().location
param tags object = {}

param publisherEmail string
param publisherName string
param sku object = {
  name: 'Consumption'
  capacity: 0
}
param publicNetworkAccess string = 'Enabled'
param backendUrl string = ''
param apiKeyHeaderName string = 'x-api-key'
@secure()
param apiKey string = ''

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: sku
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    publicNetworkAccess: publicNetworkAccess
  }
}

// Backend for Container App
resource backend 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = if (!empty(backendUrl)) {
  parent: apim
  name: 'mcp-backend'
  properties: {
    description: 'MCP Server Container App Backend'
    url: backendUrl
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// Named value for API Key
resource apiKeyValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = if (!empty(apiKey)) {
  parent: apim
  name: 'mcp-api-key'
  properties: {
    displayName: 'mcp-api-key'
    secret: true
    value: apiKey
  }
}

// MCP API
resource api 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apim
  name: 'mcp-api'
  properties: {
    displayName: 'MCP Server API'
    apiRevision: '1'
    description: 'Model Context Protocol Server API for PDF search and retrieval'
    subscriptionRequired: true
    path: 'mcp'
    protocols: ['https']
    isCurrent: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
  }
}

// API-level policy with rate limiting and CORS
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <rate-limit calls="100" renewal-period="60" />
    <cors allow-credentials="false">
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method>
        <method>POST</method>
      </allowed-methods>
      <allowed-headers>
        <header>Content-Type</header>
        <header>x-api-key</header>
        <header>Ocp-Apim-Subscription-Key</header>
      </allowed-headers>
    </cors>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

// Health endpoint
resource healthOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'health'
  properties: {
    displayName: 'Health Check'
    method: 'GET'
    urlTemplate: '/health'
    description: 'Check API health status'
  }
}

resource healthPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = if (!empty(backendUrl)) {
  parent: healthOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="mcp-backend" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

// MCP Tools endpoint (main endpoint for Copilot)
resource toolsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'tools'
  properties: {
    displayName: 'MCP Tools'
    method: 'POST'
    urlTemplate: '/api/tools'
    description: 'MCP tools endpoint for GitHub Copilot'
  }
}

resource toolsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = if (!empty(backendUrl) && !empty(apiKey)) {
  parent: toolsOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="mcp-backend" />
    <set-header name="x-api-key" exists-action="override">
      <value>{{mcp-api-key}}</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

// Search endpoint
resource searchOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'search'
  properties: {
    displayName: 'Search PDFs'
    method: 'POST'
    urlTemplate: '/api/search'
    description: 'Search for content in PDF documents'
  }
}

resource searchPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = if (!empty(backendUrl) && !empty(apiKey)) {
  parent: searchOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="mcp-backend" />
    <set-header name="x-api-key" exists-action="override">
      <value>{{mcp-api-key}}</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

// Fetch endpoint
resource fetchOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'fetch'
  properties: {
    displayName: 'Fetch Document'
    method: 'POST'
    urlTemplate: '/api/fetch'
    description: 'Retrieve specific PDF document or pages'
  }
}

resource fetchPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = if (!empty(backendUrl) && !empty(apiKey)) {
  parent: fetchOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="mcp-backend" />
    <set-header name="x-api-key" exists-action="override">
      <value>{{mcp-api-key}}</value>
    </set-header>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

output id string = apim.id
output name string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output portalUrl string = apim.properties.portalUrl ?? ''
output mcpApiUrl string = '${apim.properties.gatewayUrl}/mcp'

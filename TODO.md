# TODO

## 1. Granular Document Extraction (Section / Chapter / Page)

- [ ] Enrich the search index with **section**, **chapter**, and **page number** metadata during indexing
  - Extract headings / section titles from PDF structure (e.g. via Document Intelligence layout model)
  - Store `section_title`, `chapter_title`, and `page_number` as filterable/retrievable fields in the index
- [ ] Update the **fetch** tool to accept optional `section`, `chapter`, and `page` parameters
  - Allow agents to retrieve specific slices of a document instead of the full content
  - Support combinations: fetch by page range, by section name, by chapter, or any mix
- [ ] Update the **search** results to surface section/chapter/page in each hit so the agent can decide what to fetch
- [ ] Update MCP `tools/list` schemas to advertise the new parameters

## 2. Private Networking / Private Endpoints

- [ ] Enable **private endpoint** for the **Storage Account** (blob)
  - Create private DNS zone `privatelink.blob.core.windows.net`
  - Disable public network access on the storage account
- [ ] Enable **private endpoint** for **Azure AI Search**
  - Create private DNS zone `privatelink.search.windows.net`
  - Disable public network access on the search service
- [ ] Enable **private endpoint** for **Azure OpenAI** (Cognitive Services)
  - Create private DNS zone `privatelink.openai.azure.com`
  - Disable public network access on the cognitive services account
- [ ] Update the **VNet** and **subnet** configuration in `infra/core/network/vnet.bicep` to accommodate private endpoint subnets
- [ ] Ensure the **Container App** can reach all services through the VNet (VNet integration)
- [ ] Update **APIM** networking if needed (internal VNet mode or private endpoint)

## 3. Migrate from Azure OpenAI to AI Foundry

- [ ] Evaluate **Azure AI Foundry** (formerly Azure AI Studio) as a replacement for the standalone Azure OpenAI resource
  - Assess model availability (embedding model `text-embedding-3-large` and any future chat/completion models)
  - Compare pricing, quota management, and regional availability
- [ ] Create an **AI Foundry hub and project** to host the models
- [ ] Migrate the embedding model deployment from Azure OpenAI to AI Foundry
- [ ] Update the search pipeline (`setup-search-pipeline.sh`) to point the vectorizer at the AI Foundry endpoint
- [ ] Update Bicep templates (`infra/core/ai/cognitiveservices.bicep`, `infra/main.bicep`) to provision AI Foundry resources instead of standalone Azure OpenAI
- [ ] Validate that indexing and search still work end-to-end after migration

## 4. Evaluate Azure AI Content Understanding

- [ ] Investigate whether **Azure AI Content Understanding** (preview) is a better fit than the current Document Intelligence + AI Search indexer pipeline
  - Content Understanding provides a unified approach to extract text, layout, tables, figures, and semantic structure from documents
  - Compare extraction quality (sections, chapters, tables, figures) vs. current DI + custom skillset approach
  - Evaluate whether it simplifies the pipeline (fewer moving parts: no custom skillset, no separate vectorizer configuration)
  - Check regional availability and preview limitations
- [ ] If beneficial, prototype a Content Understanding–based pipeline and compare results with the current setup
- [ ] Document findings and recommendation

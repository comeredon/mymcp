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
- [ ] Enable **private endpoint** for **Azure AI Foundry** (Cognitive Services)
  - Create private DNS zone `privatelink.cognitiveservices.azure.com`
  - Disable public network access on the AI Foundry account
- [ ] Update the **VNet** and **subnet** configuration in `infra/core/network/vnet.bicep` to accommodate private endpoint subnets
- [ ] Ensure the **Container App** can reach all services through the VNet (VNet integration)
- [ ] Update **APIM** networking if needed (internal VNet mode or private endpoint)

## 3. ~~Migrate from Azure OpenAI to AI Foundry~~ ✅ DONE

- [x] ~~Evaluate **Azure AI Foundry** as a replacement for the standalone Azure OpenAI resource~~ → Consolidated into single `AIServices` resource
- [x] ~~Create an AI Foundry hub and project to host the models~~ → Using `kind: 'AIServices'` with model deployments
- [x] ~~Migrate the embedding model deployment from Azure OpenAI to AI Foundry~~ → Deployments (embeddings, chat) now on AI Foundry resource
- [x] ~~Update the search pipeline to point the vectorizer at the AI Foundry endpoint~~ → `setup-search-pipeline.sh` updated
- [x] ~~Update Bicep templates to provision AI Foundry resources instead of standalone Azure OpenAI~~ → `main.bicep` consolidated
- [ ] Validate that indexing and search still work end-to-end after migration

## 4. ~~Evaluate Azure AI Content Understanding~~ ✅ DONE

- [x] ~~Investigate whether **Azure AI Content Understanding** (preview) is a better fit than the current Document Intelligence + AI Search indexer pipeline~~ → Yes, adopted as replacement
  - Content Understanding provides a unified approach to extract text, layout, tables, figures, and semantic structure from documents
  - Built-in chunking via `chunkingProperties` eliminates the separate `TextSplitSkill`
  - Markdown output for tables/figures, cross-page table support, chunks spanning page boundaries
  - More cost effective than Document Intelligence Layout skill
- [x] ~~Prototype a Content Understanding–based pipeline and compare results~~ → Implemented in `setup-search-pipeline.sh/.ps1/.http`
- [x] ~~Document findings and recommendation~~ → `ContentUnderstandingSkill` replaces `DocumentIntelligenceLayoutSkill` + `SplitSkill`
- [ ] Validate end-to-end indexing and search after migration to Content Understanding

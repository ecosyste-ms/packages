# CycloneDX Transparency Exchange API Implementation Analysis
## Focus: PURL Lookup & CLE Generation

**Date:** 2025-10-29
**Status:** Technical Feasibility Analysis

---

## Executive Summary

The Transparency Exchange API (TEA) is in Beta 1, focusing on the consumer/read API. This analysis examines implementing TEA in Ecosyste.ms Packages with emphasis on:

1. **The PURL lookup use case** - The primary real-world pattern
2. **Product/Component mismatch** - A fundamental spec issue for package registries
3. **CLE generation** - Highly feasible with existing data

**Key Findings:**

- ✅ **Component-level TEA is a natural fit** - PURL → Package/Version mapping is 1:1
- ⚠️ **Product abstraction doesn't align** with package registry reality
- ✅ **CLE (Common Lifecycle Enumeration) generation is straightforward** from existing status data
- 💡 **Feedback opportunity** - TEA is in beta, we can influence the spec

**Recommendation:** Implement Component-centric TEA subset with PURL-first discovery + CLE generation

---

## 1. The PURL Lookup Reality

### 1.1 Primary TEA Use Case (C1)

From TEA requirements:
> "As a consumer that has an SBOM for a product, I want to be able to retrieve VEX and VDR files automatically both for current and old versions of the software. In the SBOM the product is identified by a PURL..."

**The pattern:**
```
User has: pkg:npm/react@18.2.0
User wants: SBOM, VEX, lifecycle status, security info
User queries: TEA API with PURL
User gets: Transparency artifacts
```

### 1.2 What PURLs Actually Represent

**PURL format:** `pkg:<type>/<namespace>/<name>@<version>`

**Examples from the real world:**
```
pkg:npm/react@18.2.0              → npm package "react" version 18.2.0
pkg:maven/org.apache.logging.log4j/log4j-core@2.24.3  → Maven artifact
pkg:cargo/serde@1.0.195            → Rust crate
pkg:pypi/django@5.0                → Python package
```

**What PURLs identify:**
- ✅ Individual components (packages/libraries)
- ✅ Specific versions of those components
- ✅ Package registry artifacts
- ✅ TEA "Component Release" concept

**What PURLs do NOT identify:**
- ❌ Products (higher-level abstractions)
- ❌ Product families
- ❌ Multi-component bundles
- ❌ Collections of related packages

### 1.3 Package Registry Reality

**npm publishes separately:**
- `pkg:npm/react` (core library)
- `pkg:npm/react-dom` (DOM bindings)
- `pkg:npm/react-native` (mobile framework)

**Maven publishes separately:**
- `pkg:maven/org.apache.logging.log4j/log4j-core`
- `pkg:maven/org.apache.logging.log4j/log4j-api`
- `pkg:maven/org.apache.logging.log4j/log4j-slf4j-impl`

**Each has its own PURL. There is no PURL for "React Product" or "Log4j Product".**

Package registries publish **components**, not products.

---

## 2. The Product/Component Mismatch

### 2.1 TEA's Hierarchy

```
Product (e.g., "Apache Log4j 2")
  └── Product Release (e.g., "2.24.3")
      ├── Collection (artifacts for the "product")
      └── Components
          ├── log4j-core (PURL: pkg:maven/.../log4j-core@2.24.3)
          └── log4j-api (PURL: pkg:maven/.../log4j-api@2.24.3)

Component (e.g., "log4j-core")
  └── Component Release (e.g., "2.24.3")
      └── Collection (artifacts for this specific component)
```

### 2.2 The Problems

**Problem 1: PURL Query Ambiguity**
- User queries: `pkg:maven/org.apache.logging.log4j/log4j-core@2.24.3`
- This is a Component Release, not a Product Release
- To get Product data, API must traverse Component → Product relationship
- But package registries don't define these relationships

**Problem 2: No Product Boundaries**
- What is the "React Product"?
  - Just react?
  - react + react-dom?
  - The entire React ecosystem?
- Who decides product boundaries?
- Package registries don't track this

**Problem 3: Discovery Flow Breaks**
- TEI (Transparency Exchange Identifier) uses PURLs
- PURLs identify components
- Discovery lands you at Component, not Product
- Product layer adds indirection for no gain

**Problem 4: Ecosystem Doesn't Think This Way**
- npm, PyPI, Maven, Cargo publish **packages** (components)
- Dependency resolution works on **packages**
- Package managers install **packages**
- No concept of "products" in package.json, Cargo.toml, pom.xml, etc.

### 2.3 When Products Make Sense

TEA's Product abstraction may be valuable for:

✅ **Commercial software vendors:**
- "Oracle Database 19c" is a product containing multiple components
- "Adobe Creative Suite" bundles multiple applications
- Vendor defines product boundaries explicitly

✅ **Embedded systems:**
- Device firmware as a product
- Contains multiple components from different sources
- Product sold as a unit

✅ **Enterprise bundles:**
- Application stack distributed together
- Curated component collection

**But for package registries:** The product abstraction is **artificial and unnecessary**.

### 2.4 Proposed Solution

**Make Products optional in the spec.**

Implementations serving package registries should be able to:
- Implement only Component/ComponentRelease endpoints
- Support PURL-based discovery directly to Components
- Still be considered TEA-conformant

This serves the primary use case (C1: PURL-based lookup) without forcing an unnatural abstraction.

---

## 3. Perfect Component Mapping

### 3.1 Natural 1:1 Alignment

| TEA Concept | Ecosyste.ms Model | Quality | Data Source |
|-------------|-------------------|---------|-------------|
| **Component** | **Package** | ✅ Perfect | packages table |
| Component UUID | PURL-derived UUID | ✅ Perfect | Generate from PURL (deterministic) |
| Component name | package.name | ✅ Perfect | packages.name |
| Component identifiers | PURL | ✅ Perfect | Already generated via purl gem |
| **Component Release** | **Version** | ✅ Perfect | versions table |
| Release UUID | PURL-derived UUID | ✅ Perfect | Generate from version PURL |
| Release version | version.number | ✅ Perfect | versions.number |
| Release date | version.published_at | ✅ Perfect | versions.published_at |
| Pre-release flag | version metadata | ✅ Good | Can infer or add field |
| Distributions | Download URLs | ⚠️ Moderate | Have URLs, need checksums |

### 3.2 Component Endpoints We Can Implement

| TEA Endpoint | Feasibility | Maps To |
|--------------|-------------|---------|
| `GET /component/{uuid}` | ✅ Trivial | Package.find_by(uuid) or resolve from PURL |
| `GET /component/{uuid}/releases` | ✅ Trivial | Package.versions with pagination |
| `GET /componentRelease/{uuid}` | ✅ Trivial | Version.find_by(uuid) or resolve from PURL |
| `GET /componentRelease/{uuid}/collection/latest` | ⚠️ Moderate | Generate collection from current data |
| `GET /componentRelease/{uuid}/collections` | ⚠️ Moderate | Collection versioning |

### 3.3 What We Skip (Products)

| TEA Endpoint | Why Skip |
|--------------|----------|
| `GET /product/{uuid}` | No product concept in package registries |
| `GET /product/{uuid}/releases` | N/A |
| `GET /products` | N/A |
| `GET /productRelease/{uuid}` | N/A |

**Result:** Implement ~50% of TEA endpoints while serving 100% of the PURL lookup use case.

---

## 4. CLE (Common Lifecycle Enumeration) - Strong Opportunity

### 4.1 What is CLE?

**Common Lifecycle Enumeration** - OWASP/ECMA TC54-TG3 standard

**Purpose:** Communicate component lifecycle events in machine-readable format

**Format:** JSON documents with PURL identifiers and ordered lifecycle events

**Event Types:**
- `released` - Version published
- `endOfLife` - No longer maintained
- `endOfSupport` - No more security patches
- `endOfDevelopment` - No new features
- `endOfDistribution` - No longer distributed
- `supersededBy` - Replaced by another version
- `componentRenamed` - Identifier changed
- `withdrawn` - Revoke previous event

### 4.2 Ecosyste.ms Data → CLE Events

**Direct mappings (high confidence):**

| CLE Event | Ecosyste.ms Data | Confidence |
|-----------|------------------|------------|
| `released` | version.published_at | ✅ Excellent - Have exact timestamps |
| `endOfDistribution` | version.status = 'removed' | ✅ Excellent - Yanked/removed versions |
| `endOfLife` | package.status = 'deprecated' | ✅ Good - Deprecated packages |

**Inference possible:**

| CLE Event | How to Infer | Confidence |
|-----------|--------------|------------|
| `supersededBy` | Compare with latest_release_number | ⚠️ Moderate - Can identify superseding version |
| `endOfDevelopment` | Last release > 2 years ago | ⚠️ Low - Just a guess |
| `endOfSupport` | No security patches in advisories | ⚠️ Low - Absence of evidence |

**Not tracked:**

| CLE Event | Status |
|-----------|--------|
| `componentRenamed` | ❌ Rarely in metadata |
| `endOfMarketing` | ❌ Not applicable to OSS |

### 4.3 Example CLE Document (npm left-pad)

**Context:** Famous npm package that was unpublished, breaking the internet

```json
{
  "$schema": "https://packages.ecosyste.ms/cle/schema/1.0.0.json",
  "identifier": "pkg:npm/left-pad",
  "updatedAt": "2024-03-20T15:30:00Z",
  "events": [
    {
      "id": 3,
      "type": "endOfDistribution",
      "effective": "2016-03-23T00:00:00Z",
      "published": "2024-03-20T15:30:00Z",
      "versions": [{"range": "vers:npm/*"}],
      "comment": "Package unpublished from npm registry"
    },
    {
      "id": 2,
      "type": "released",
      "effective": "2015-03-18T18:30:00Z",
      "published": "2024-03-20T15:30:00Z",
      "versions": [{"range": "vers:npm/0.0.1"}]
    },
    {
      "id": 1,
      "type": "released",
      "effective": "2014-12-31T12:00:00Z",
      "published": "2024-03-20T15:30:00Z",
      "versions": [{"range": "vers:npm/0.0.0"}]
    }
  ]
}
```

### 4.4 Example CLE Document (deprecated package)

**npm request - deprecated in favor of modern alternatives**

```json
{
  "$schema": "https://packages.ecosyste.ms/cle/schema/1.0.0.json",
  "identifier": "pkg:npm/request",
  "updatedAt": "2024-03-20T15:30:00Z",
  "events": [
    {
      "id": 4,
      "type": "endOfLife",
      "effective": "2020-02-11T00:00:00Z",
      "published": "2024-03-20T15:30:00Z",
      "versions": [{"range": "vers:npm/*"}],
      "comment": "Package deprecated",
      "metadata": {
        "deprecation_message": "request has been deprecated, see https://github.com/request/request/issues/3142",
        "alternatives": ["node-fetch", "axios", "native fetch()"]
      }
    },
    {
      "id": 3,
      "type": "released",
      "effective": "2019-02-14T12:00:00Z",
      "published": "2024-03-20T15:30:00Z",
      "versions": [{"range": "vers:npm/2.88.2"}],
      "metadata": {
        "license": "Apache-2.0"
      }
    }
  ]
}
```

### 4.5 CLE Generation Implementation

**Complexity:** LOW

**Required:**
1. CLE JSON schema validator
2. Event builder from package/version status
3. VERS (Version Range Specification) formatter
4. Event ID sequencing
5. ISO 8601 timestamp formatting

**Ruby implementation sketch:**

```ruby
class CleGenerator
  def generate(package)
    {
      "$schema": "https://packages.ecosyste.ms/cle/schema/1.0.0.json",
      "identifier": package.purl_without_version,
      "updatedAt": Time.now.utc.iso8601,
      "events": build_events(package)
    }
  end

  private

  def build_events(package)
    events = []
    event_id = 1

    # Released events for each version
    package.versions.order(published_at: :asc).each do |version|
      events << {
        id: event_id++,
        type: "released",
        effective: version.published_at.iso8601,
        published: Time.now.utc.iso8601,
        versions: [{ range: "vers:#{package.ecosystem}/#{version.number}" }],
        metadata: { license: version.licenses }.compact
      }
    end

    # Deprecation event
    if package.status == 'deprecated'
      events << {
        id: event_id++,
        type: "endOfLife",
        effective: package.updated_at.iso8601, # Best guess
        published: Time.now.utc.iso8601,
        versions: [{ range: "vers:#{package.ecosystem}/*" }],
        comment: "Package marked as deprecated",
        metadata: package.metadata.slice('deprecation_message', 'alternatives')
      }
    end

    # Removed versions
    package.versions.where(status: 'removed').each do |version|
      events << {
        id: event_id++,
        type: "endOfDistribution",
        effective: version.updated_at.iso8601,
        published: Time.now.utc.iso8601,
        versions: [{ range: "vers:#{package.ecosystem}/#{version.number}" }],
        comment: "Version removed from registry"
      }
    end

    events.sort_by { |e| -e[:id] } # Descending order
  end
end
```

### 4.6 CLE Value Proposition

**For users:**
- Machine-readable lifecycle status
- Historical timeline of package lifecycle
- Deprecation warnings with context
- Removed version tracking
- Can be queried programmatically

**For supply chain tools:**
- SBOM analysis can check if components are EOL
- Vulnerability scanners can prioritize EOL packages
- Dependency management tools can warn on deprecated packages
- Compliance tools can track component lifecycle

**For Ecosyste.ms:**
- First major implementation of CLE at scale (35+ ecosystems)
- Immediate value from existing data
- Simple to implement (no artifact generation complexity)
- Contributes to OWASP/ECMA standardization
- Foundation for more complex TEA artifacts

---

## 5. Implementation Approach: PURL-First Component TEA

### 5.1 Architecture

**Core concept:** PURL is the primary identifier, not UUID

```
User Query:
  GET /tea/v1/lookup?purl=pkg:npm/react@18.2.0

↓ Resolve PURL to Package + Version

↓ Generate UUID deterministically (UUID v5 from PURL)

↓ Return Component Release with Collection

Response:
  {
    "uuid": "deterministic-from-purl",
    "componentName": "react",
    "version": "18.2.0",
    "identifiers": [{"idType": "PURL", "idValue": "pkg:npm/react@18.2.0"}],
    "releaseDate": "2022-06-14T18:00:00Z",
    "collection": {
      "artifacts": [
        {"name": "CLE", "type": "OTHER", "url": "..."},
        {"name": "License", "type": "LICENSE", "url": "..."},
        {"name": "Advisories", "type": "VULNERABILITIES", "url": "..."}
      ]
    }
  }
```

### 5.2 Endpoints to Implement

**Priority 1: PURL Lookup (Primary Use Case)**
```
GET /tea/v1/lookup?purl={purl}
```
- Parses PURL
- Resolves to package/version
- Generates deterministic UUID
- Redirects (303) to appropriate endpoint
- Or returns JSON directly

**Priority 2: Component Endpoints**
```
GET /tea/v1/component/{uuid}
GET /tea/v1/component/{uuid}/releases
```
- Component metadata
- List of releases

**Priority 3: Component Release Endpoints**
```
GET /tea/v1/componentRelease/{uuid}
GET /tea/v1/componentRelease/{uuid}/collection/latest
```
- Specific version metadata
- Artifact collection

**Priority 4: Artifact Serving**
```
GET /tea/v1/artifact/{uuid}
```
- Serve generated CLE documents
- Serve license information
- Serve advisory data

### 5.3 UUID Generation Strategy

**Option A: Deterministic from PURL (Recommended)**

```ruby
require 'digest/uuid'

def component_uuid_from_purl(purl)
  # pkg:npm/react → same UUID every time
  purl_without_version = purl.split('@').first
  Digest::UUID.uuid_v5(Digest::UUID::DNS_NAMESPACE, purl_without_version)
end

def component_release_uuid_from_purl(purl)
  # pkg:npm/react@18.2.0 → same UUID every time
  Digest::UUID.uuid_v5(Digest::UUID::DNS_NAMESPACE, purl)
end
```

**Benefits:**
- No database storage needed
- Same PURL always generates same UUID
- Different servers generate same UUID
- Decentralized

**Option B: Store UUIDs**

Add columns:
```ruby
add_column :packages, :tea_component_uuid, :uuid
add_column :versions, :tea_component_release_uuid, :uuid
```

**Benefits:**
- Explicit UUID management
- Can use random UUIDs if desired
- UUID indexed for fast lookup

**Recommendation:** Option A (deterministic) - simpler, no migration needed

### 5.4 Collection Generation

**Initial implementation: Version 1 only (no collection versioning)**

```ruby
class TeaCollectionGenerator
  def generate(version)
    {
      uuid: version.tea_component_release_uuid,
      version: 1,
      date: Time.now.utc.iso8601,
      belongsTo: "COMPONENT_RELEASE",
      updateReason: {
        type: "INITIAL_RELEASE",
        comment: "Initial collection"
      },
      artifacts: generate_artifacts(version)
    }
  end

  private

  def generate_artifacts(version)
    artifacts = []

    # CLE artifact
    artifacts << {
      uuid: "cle-#{version.id}",
      name: "Common Lifecycle Enumeration",
      type: "OTHER", # Or propose new type: "LIFECYCLE"
      formats: [{
        mimeType: "application/json",
        description: "CLE document with lifecycle events",
        url: cle_artifact_url(version)
      }]
    }

    # License artifact
    if version.licenses.present?
      artifacts << {
        uuid: "license-#{version.id}",
        name: "License Information",
        type: "LICENSE",
        formats: [{
          mimeType: "application/json",
          description: "SPDX license: #{version.licenses}",
          url: license_artifact_url(version)
        }]
      }
    end

    # Advisory artifact
    if version.package.advisories.any?
      artifacts << {
        uuid: "advisories-#{version.id}",
        name: "Security Advisories",
        type: "VULNERABILITIES",
        formats: [{
          mimeType: "application/json",
          description: "Known security vulnerabilities",
          url: advisories_artifact_url(version)
        }]
      }
    end

    artifacts
  end
end
```

**Future: Collection versioning**
- Increment collection.version when data changes
- Store previous versions
- Track update reasons (VEX_UPDATED, ARTIFACT_CORRECTED, etc.)

### 5.5 Artifact Types (Phase 1)

**1. CLE Document**
```json
{
  "type": "OTHER",  # Or propose "LIFECYCLE" type to TEA spec
  "mimeType": "application/json",
  "url": "/tea/v1/artifact/cle-{package-id}"
}
```

**2. License Document**
```json
{
  "type": "LICENSE",
  "mimeType": "application/json",
  "content": {
    "licenses": ["MIT"],
    "normalized_licenses": ["MIT"],
    "spdx_url": "https://spdx.org/licenses/MIT.html"
  }
}
```

**3. Advisory/Vulnerability Document**
```json
{
  "type": "VULNERABILITIES",
  "mimeType": "application/json",
  "content": {
    "advisories": [
      {
        "uuid": "...",
        "severity": "HIGH",
        "cvss_score": 7.5,
        "description": "...",
        "references": [...]
      }
    ]
  }
}
```

### 5.6 Artifact Storage/Caching

**Phase 1: Generate on-demand**
- No persistent storage
- Generate CLE/license/advisory JSON on request
- Cache in Redis (24h TTL)
- Invalidate on package update

**Phase 2: Persistent storage (if needed)**
- Store artifacts in S3 for immutability
- Content-addressable URLs (include checksum)
- CDN for distribution

### 5.7 Data Model Changes

**Option 1: No schema changes (recommended for MVP)**
- Generate UUIDs on-the-fly from PURLs
- Generate collections on-the-fly
- Cache everything in Redis

**Option 2: Minimal schema changes**
```ruby
add_column :versions, :tea_collection_version, :integer, default: 1
add_column :versions, :tea_collection_updated_at, :datetime
```

Track collection versioning for future enhancement.

---

## 6. TEA Spec Feedback (for ECMA TC54-TG1)

### 6.1 Make Products Optional

**Current issue:**
- Spec emphasizes Product/ProductRelease hierarchy
- Primary use case (C1) is PURL-based lookup
- PURLs identify components, not products
- Package registries don't have products

**Proposed change:**
```
OPTIONAL: Products and Product Releases

Implementations MAY implement the Product hierarchy for commercial
software or bundled distributions.

Implementations serving package registries (npm, PyPI, Maven, etc.)
MAY implement only Component and Component Release endpoints.

Component-only implementations are conformant with this specification.
```

**Rationale:**
- Serves primary use case without artificial abstraction
- Aligns with package ecosystem reality
- Reduces implementation complexity
- Doesn't prevent product support for vendors who need it

### 6.2 Add PURL-First Discovery Endpoint

**Proposed addition:**
```
GET /tea/v1/lookup?purl={purl}

Returns:
  - 303 redirect to /componentRelease/{uuid} if version specified
  - 303 redirect to /component/{uuid} if no version
  - Or JSON response with component/release data
```

**Rationale:**
- Simplifies primary use case
- User has PURL, wants artifacts - this is the direct path
- Currently user must: parse PURL → generate UUID somehow → query endpoint
- Standard lookup mechanism improves interoperability

### 6.3 Specify UUID Generation from PURLs

**Current issue:**
- Spec uses UUIDs but doesn't specify how to generate from PURLs
- Different implementations might generate different UUIDs for same PURL
- No standard way to deterministically derive UUID

**Proposed addition:**
```
UUID Generation from PURLs:

Implementations SHOULD use UUID v5 (RFC 4122) for deterministic
UUID generation from PURLs:

  component_uuid = UUIDv5(DNS_NAMESPACE, purl_without_version)
  component_release_uuid = UUIDv5(DNS_NAMESPACE, full_purl)

Example:
  PURL: pkg:npm/react@18.2.0
  Component UUID: UUIDv5(DNS_NAMESPACE, "pkg:npm/react")
  Component Release UUID: UUIDv5(DNS_NAMESPACE, "pkg:npm/react@18.2.0")

This enables:
  - Consistent UUIDs across implementations
  - Decentralized UUID generation
  - No coordination required between servers
```

### 6.4 Clarify Implementation Patterns

**Proposed informative section:**
```
Two Implementation Patterns:

1. Vendor-Published TEA:
   - Software vendor publishes artifacts authoritatively
   - Artifacts signed by vendor
   - Products may contain multiple components
   - Example: Commercial software with product releases

2. Registry-Aggregated TEA:
   - Package registry aggregates component metadata
   - Generates artifacts from registry data
   - Component-centric (no products)
   - Example: npm, PyPI, Maven Central mirrors
```

**Rationale:**
- Clarifies different use cases
- Sets expectations for artifact authority
- Explains when products make sense vs. don't

### 6.5 Formalize CLE Support

**Current state:**
- CLE mentioned in README
- Not formally integrated into spec

**Proposed:**
- Add CLE as artifact type: `LIFECYCLE` or use `OTHER`
- Specify mime type: `application/json`
- Reference CLE spec (ECMA TC54-TG3)
- Show example CLE artifact in collection

---

## 7. Implementation Phases

### Phase 1: CLE Generation (Standalone)

**Endpoints:**
```
GET /cle/{ecosystem}/{name}.json
```

**Deliverables:**
- CleGenerator service class
- CLE JSON schema
- Generate from package/version status
- Serve as JSON endpoint
- Add cle_url to existing package API

**Benefits:**
- Immediate value
- Simple implementation
- Tests CLE generation at scale
- Can evolve to full TEA later

### Phase 2: Component TEA Endpoints

**Endpoints:**
```
GET /tea/v1/lookup?purl={purl}
GET /tea/v1/component/{uuid}
GET /tea/v1/component/{uuid}/releases
GET /tea/v1/componentRelease/{uuid}
```

**Deliverables:**
- PURL → UUID conversion
- Component/ComponentRelease controllers
- TEA JSON responses
- Pagination for releases list

### Phase 3: Collections & Artifacts

**Endpoints:**
```
GET /tea/v1/componentRelease/{uuid}/collection/latest
GET /tea/v1/artifact/{uuid}
```

**Deliverables:**
- TeaCollectionGenerator
- Artifact generation (CLE, license, advisories)
- Artifact caching (Redis)
- Checksum calculation

### Phase 4: Documentation & Feedback

**Deliverables:**
- OpenAPI specification for TEA endpoints
- Usage examples
- Integration guide
- Formal feedback to ECMA TC54-TG1
- Blog post on implementation

---

## 8. Technical Considerations

### 8.1 PURL Resolution

**Current:** `PackageManager::Base.purl(package)`

**Need:** Reverse - PURL to Package/Version

```ruby
class PurlResolver
  def self.resolve(purl_string)
    purl = PackageURL.parse(purl_string)

    ecosystem = purl_type_to_ecosystem(purl.type)
    registry = Registry.find_by(ecosystem: ecosystem, default: true)
    package = registry.packages.find_by(name: purl.name)

    if purl.version
      version = package.versions.find_by(number: purl.version)
      { package: package, version: version }
    else
      { package: package }
    end
  end

  private

  def self.purl_type_to_ecosystem(type)
    # npm → npm, maven → maven, etc.
    # Most are 1:1, some need mapping
    case type
    when 'golang' then 'go'
    else type
    end
  end
end
```

### 8.2 Caching Strategy

**Cache keys:**
```ruby
"tea:component:#{uuid}"              # Component metadata
"tea:component:#{uuid}:releases"     # Releases list (paginated)
"tea:component_release:#{uuid}"      # Component release metadata
"tea:collection:#{uuid}:v#{version}" # Collection (versioned)
"tea:artifact:cle:#{package_id}"     # CLE document
```

**TTLs:**
- Component/Release metadata: 24h (refresh on package update)
- Collections: 24h (or indefinite if implementing immutability)
- Artifacts: 24h (invalidate on data change)

**Invalidation:**
- On package sync: invalidate component cache
- On version update: invalidate component release cache
- On status change: invalidate CLE artifact cache

### 8.3 Performance

**Concerns:**
- UUID lookup vs. integer ID lookup
- PURL parsing overhead
- Collection generation on every request

**Optimizations:**
- Index UUIDs if storing in DB
- Cache PURL parsing results
- Cache generated collections
- Lazy-load artifacts (don't generate until requested)

### 8.4 Multi-Ecosystem Complexity

**Challenge:** 35+ ecosystems with different data quality

**CLE generation quality:**
- ✅ npm: Excellent (good status tracking, deprecation messages)
- ✅ PyPI: Good (yanked packages tracked)
- ✅ RubyGems: Good (yanked gems)
- ⚠️ Maven: Moderate (some artifacts removed, not always tracked)
- ⚠️ Cargo: Moderate (yanked crates)

**Result:** CLE completeness varies by ecosystem, but core events (released, endOfDistribution) work everywhere.

---

## 9. Example TEA Response

**Query:**
```
GET /tea/v1/lookup?purl=pkg:npm/react@18.2.0
```

**Response:** (303 redirect to componentRelease, or direct JSON)

```json
{
  "uuid": "a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "component": "f1e2d3c4-5b6a-7f8e-9d0c-1a2b3c4d5e6f",
  "componentName": "react",
  "version": "18.2.0",
  "createdDate": "2024-03-20T15:30:00Z",
  "releaseDate": "2022-06-14T18:00:00Z",
  "preRelease": false,
  "identifiers": [
    {
      "idType": "PURL",
      "idValue": "pkg:npm/react@18.2.0"
    }
  ],
  "distributions": [
    {
      "distributionType": "npm-tarball",
      "description": "npm package tarball",
      "url": "https://registry.npmjs.org/react/-/react-18.2.0.tgz",
      "checksums": [
        {
          "algType": "SHA_256",
          "algValue": "abc123..."
        }
      ]
    }
  ],
  "collection": {
    "uuid": "a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
    "version": 1,
    "date": "2024-03-20T15:30:00Z",
    "belongsTo": "COMPONENT_RELEASE",
    "artifacts": [
      {
        "uuid": "cle-123",
        "name": "Common Lifecycle Enumeration",
        "type": "OTHER",
        "formats": [
          {
            "mimeType": "application/json",
            "description": "CLE lifecycle events for react",
            "url": "https://packages.ecosyste.ms/tea/v1/artifact/cle-123",
            "checksums": [
              {
                "algType": "SHA_256",
                "algValue": "def456..."
              }
            ]
          }
        ]
      },
      {
        "uuid": "license-123",
        "name": "License",
        "type": "LICENSE",
        "formats": [
          {
            "mimeType": "application/json",
            "description": "MIT License",
            "url": "https://packages.ecosyste.ms/tea/v1/artifact/license-123"
          }
        ]
      }
    ]
  }
}
```

**CLE Artifact Content** (GET /tea/v1/artifact/cle-123):

```json
{
  "$schema": "https://packages.ecosyste.ms/cle/schema/1.0.0.json",
  "identifier": "pkg:npm/react",
  "updatedAt": "2024-03-20T15:30:00Z",
  "events": [
    {
      "id": 100,
      "type": "released",
      "effective": "2022-06-14T18:00:00Z",
      "published": "2024-03-20T15:30:00Z",
      "versions": [{"range": "vers:npm/18.2.0"}],
      "metadata": {
        "license": "MIT"
      }
    },
    {
      "id": 99,
      "type": "released",
      "effective": "2022-03-29T12:00:00Z",
      "published": "2024-03-20T15:30:00Z",
      "versions": [{"range": "vers:npm/18.0.0"}]
    }
  ]
}
```

---

## 10. Conclusion

### Key Takeaways

1. **PURL lookup is the real use case** - TEA's Product hierarchy doesn't align
2. **Component-level TEA is natural** - Perfect 1:1 mapping with Package/Version
3. **CLE generation is straightforward** - Excellent first artifact type
4. **TEA is in beta** - Opportunity to provide feedback on spec issues

### Recommendation

Implement **Component-Centric TEA with PURL-First Discovery:**

**Phase 1:** CLE generation (immediate value)
**Phase 2:** Component endpoints (PURL lookup works)
**Phase 3:** Collections & artifacts (complete pipeline)
**Phase 4:** Documentation & spec feedback

**Benefits:**
- ✅ Serves primary use case (PURL → artifacts)
- ✅ Natural fit with Ecosyste.ms architecture
- ✅ Provides valuable lifecycle transparency
- ✅ No Product abstraction overhead
- ✅ Contributes feedback to TEA standardization
- ✅ Foundation for future SBOM/VEX generation

### Feedback for TEA Spec

**To ECMA TC54-TG1:**

The Product/Component distinction works for commercial vendors but creates unnecessary complexity for package registry use cases. Consider:

1. Make Products optional
2. Add PURL-first discovery endpoint
3. Specify UUID generation from PURLs
4. Clarify vendor-published vs. registry-aggregated patterns
5. Formally integrate CLE artifact type

This would make TEA more applicable to the broader software ecosystem while maintaining its value for commercial software distribution.

---

**End of Analysis**

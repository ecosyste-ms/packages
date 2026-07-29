# CISA 2026 SBOM minimum elements and Packages API alignment

CISA published version 2.1 of [Minimum Elements for a Software Bill of Materials](https://www.cisa.gov/sites/default/files/2026-07/2026_cisa_sbom_minimum_elements_508c.pdf) on July 29, 2026. It replaces the 2021 NTIA document and defines 17 data fields plus six practices and processes.

The Packages API already supplies useful component identity and package registry data. It does not yet supply a complete CISA-aligned enrichment record. The main gaps are exact version lookup, artifact-level hashes, component producer data, preserved license expressions, dependency resolution, and explicit reporting of unknown values.

## Data fields

| CISA element | Current API | Alignment and gaps |
| --- | --- | --- |
| SBOM Author | Not supplied | This belongs to the system generating or amending the SBOM. It is outside the normal responsibility of a package lookup API. |
| SBOM Author Signature | Not supplied | Any service that writes enriched data into an SBOM must account for the original signature. It can preserve enrichment as a separate annotation or create and sign a new SBOM version. |
| SBOM Data Format Name | Not supplied | Required if an ecosyste.ms service exports an SBOM. It is not required for a JSON component lookup response. |
| SBOM Data Format Version | Not supplied | Required alongside the format name when exporting SPDX or CycloneDX. Deprecated format versions should not be emitted. |
| SBOM Generation Context | Not supplied | The SBOM generator should state whether the data came from source, build, or post-build analysis. Registry enrichment alone cannot establish this. |
| SBOM Timestamp | Not supplied | Package and version records have timestamps, but they describe API records rather than the SBOM document. |
| SBOM Tool Name | Not supplied | An SBOM enrichment tool should record its own name when it amends a document. |
| SBOM Tool Version | Not supplied | An SBOM enrichment tool should record its version, or explicitly report that it is unknown. |
| SBOM Version | Not supplied | The SBOM author should update this when enrichment changes the document. |
| Component Name | `Package#name` | The primary name is present. Alternate names may appear inside `metadata` or `repo_metadata`, but there is no stable names collection that distinguishes primary and alternate names. |
| Component Version | `Version#number`, version PURL | The version resource has the right data. Package PURL lookup currently ignores the requested version and returns package records. |
| Component Identifiers | Package and version PURL | PURL satisfies CISA's requirement for at least one common identifier. Other identifiers known to the service, such as commit IDs, SWHIDs, or OmniBOR IDs, are not returned through one stable field. |
| Component Producer | No dedicated field | Namespace, registry maintainers, package authors, and repository owners are available as clues. None can be treated as the producer in every registry. The API should avoid silently choosing one. |
| Component License | Raw `licenses`; package-level `normalized_licenses` | Version records do not have normalized licenses. Package normalization reduces an SPDX expression to a list of IDs and loses `AND`, `OR`, and `WITH` relationships, including exceptions. Proprietary conditions and unknown values are not represented consistently. |
| Component Hash Algorithm | Prefix in `Version#integrity` | The algorithm and value share one string. Existing names such as `sha256` do not use the CISA-requested [IANA spelling](https://www.iana.org/assignments/hash-function-text-names/hash-function-text-names.xhtml), such as `sha-256`. |
| Component Hash Value | `Version#integrity` | Coverage varies by registry. Encoding varies between hex and base64. One value cannot describe versions that publish several wheels, jars, platform packages, container manifests, or other artifacts. |
| Component Dependency Relationship | Version `dependencies` | The API returns declared package names, requirements, kinds, and optional status. These records are manifest declarations rather than resolved version-to-version edges. They do not prove complete transitive coverage. |

Relevant implementation points include:

- Package responses expose package metadata, repository metadata, PURL, advisories, maintainers, and links in [`app/views/api/v1/packages/_package.json.jbuilder`](../app/views/api/v1/packages/_package.json.jbuilder).
- Version responses expose `number`, raw licenses, one `integrity` value, PURL, and declared dependencies in [`app/views/api/v1/versions/_version.json.jbuilder`](../app/views/api/v1/versions/_version.json.jbuilder).
- PURL package lookup parses a version but does not use it when building the package query in [`app/models/package.rb`](../app/models/package.rb).
- License normalization flattens compound expressions in [`app/models/package.rb`](../app/models/package.rb).
- Missing hashes can be calculated through digest.ecosyste.ms in [`app/models/version.rb`](../app/models/version.rb), but the result still occupies one version-level string.

## Practices and processes

The API provides machine-processable JSON, an OpenAPI description, stable package and version URLs, bulk PURL lookup, update timestamps, update filters, and live events. These support automated enrichment and prompt delivery.

Several CISA practices need more work:

- Accommodation of updates: records have `updated_at` and related sync timestamps, but clients cannot see which enrichment field changed or the source used for that field.
- Coverage: the API does not state which registries, versions, artifacts, licenses, hashes, or dependency edges were checked for a result. An absent field cannot be read as proof that the component or relationship does not exist.
- Explicitly identifying unknown information: `null`, blank strings, absent keys, and empty arrays have overlapping meanings. Responses do not distinguish unknown, withheld, not applicable, unsupported, or failed collection.
- Frequency: version creation and update events can trigger re-enrichment, but there is no versioned enrichment record that lets a consumer identify the exact data revision previously applied to an SBOM.
- Machine-processable data: the API is machine-readable, but it does not emit SPDX or CycloneDX. That is acceptable while it remains an enrichment source. Any SBOM export feature should support both widely used formats and declare their versions.

## Recommended API work

### Version-aware batch enrichment

A dedicated batch endpoint should accept versioned PURLs and return one result for every input. Results should preserve input order and report `matched`, `missing`, or `ambiguous` status. A match should include the exact version resource rather than the package's latest version.

The response should use a compact SBOM enrichment projection. The existing bulk package lookup returns the full package representation, including repository metadata and package-wide advisories, which can make a request for many components unnecessarily large.

The projection should include:

```json
{
  "input": {
    "purl": "pkg:gem/nokogiri@1.19.4"
  },
  "match_status": "matched",
  "component": {
    "name": "nokogiri",
    "version": "1.19.4",
    "producer": {
      "status": "unknown",
      "value": null
    },
    "identifiers": [
      {
        "type": "purl",
        "value": "pkg:gem/nokogiri@1.19.4"
      }
    ],
    "license_expression": "MIT",
    "artifacts": []
  }
}
```

### Artifact records and structured hashes

Hashes should belong to artifacts rather than directly to a version. An artifact record should carry:

- filename and download URL
- platform, architecture, ABI, runtime, and other build qualifiers when known
- hash algorithm using an IANA name
- a hexadecimal hash value
- the registry or calculation service that supplied the value
- the time the value was observed or verified

The current `integrity` field can remain for compatibility. New clients should receive structured hashes. Hash lookup results should identify an artifact and then link to its package version.

### Stable component fields

The enrichment response should add:

- `producer`, with a source and explicit unknown status
- `license_expression`, preserving SPDX operators and exceptions
- `license_ids` and `license_exceptions` as derived fields
- `identifiers`, containing every identifier known for the component
- field-level source URLs and observation timestamps
- a status vocabulary such as `known`, `unknown`, `withheld`, `not_applicable`, and `unsupported`

A producer should only be set when registry data or authoritative project metadata identifies one. A maintainer, repository owner, package namespace, or package author should not become the producer through an unqualified fallback.

### Dependency evidence

Dependency output should state whether each relationship is declared or resolved. It should include a target PURL where possible, keep version requirements separate from resolved versions, and parse environment conditions separately from dependency scope.

Registry manifests can supply useful declared dependency hints. A complete installed dependency graph usually requires lockfile, build, container, or binary analysis. The API should state that limit rather than claim transitive coverage.

### Security and provenance additions

Version-scoped advisories would be more useful for SBOM consumers than embedding every advisory associated with a package. A compact response could include applicable advisory identifiers, affected status, fixed versions, and VEX or CSAF references.

Artifact attestations, trusted publishing records, external SBOM URLs, deprecation status, and end-of-support data would add useful evidence beyond the minimum elements. Artifact attestations do not satisfy the separate SBOM Author Signature field.

The response should also distinguish the component's software license from the license and attribution for ecosyste.ms data. The project README states that API data is licensed under CC BY-SA 4.0.

## Existing issues and pull requests

Hash and artifact work is already tracked:

- [#29 Record integrity hash on versions](https://github.com/ecosyste-ms/packages/issues/29)
- [#337 Add support for builds/binaries](https://github.com/ecosyste-ms/packages/issues/337)
- [#1630 Record per-version artifact hashes for more ecosystems](https://github.com/ecosyste-ms/packages/issues/1630)
- [#1659 Add an API endpoint to look up versions by integrity hash](https://github.com/ecosyste-ms/packages/pull/1659)
- [#1684 Record sumdb h1 hashes for Go module versions](https://github.com/ecosyste-ms/packages/issues/1684)
- [#1687 CRAN historical hash coverage](https://github.com/ecosyste-ms/packages/issues/1687)
- [#1688 Bioconductor historical hash coverage](https://github.com/ecosyste-ms/packages/issues/1688)
- [#1667 File-level path and hash lookup](https://github.com/ecosyste-ms/packages/issues/1667)

The hash lookup in pull request #1659 is useful, but its single `integrity` lookup should allow a later transition to artifact records. Populating the lookup index does not address missing hash coverage or versions with several artifacts.

Version-aware PURL lookup is tracked in:

- [#512 Lookup by package URL should include the requested version](https://github.com/ecosyste-ms/packages/issues/512)
- [#1184 New version-aware and batch PURL endpoints](https://github.com/ecosyste-ms/packages/issues/1184)
- [#1622 Add Arch Linux support and fix distro namespace PURL lookups](https://github.com/ecosyste-ms/packages/pull/1622)

License work is tracked in:

- [#960 Add normalized licenses to version responses](https://github.com/ecosyste-ms/packages/issues/960)
- [#1424 Normalized licenses do not match package manager data](https://github.com/ecosyste-ms/packages/issues/1424)
- [#1705 Preserve the GNU Classpath Exception for tyrus-standalone-client](https://github.com/ecosyste-ms/packages/issues/1705)

Additional component identifiers are tracked in:

- [#1205 Add OmniBOR artifact IDs and lookup](https://github.com/ecosyste-ms/packages/issues/1205)
- [#1206 Add SWHIDs and lookup](https://github.com/ecosyste-ms/packages/issues/1206)

Dependency accuracy and coverage are tracked in:

- [#1188 Inconsistent dependency package names and requirements](https://github.com/ecosyste-ms/packages/issues/1188)
- [#1189 Inconsistent dependency kind fields](https://github.com/ecosyste-ms/packages/issues/1189)
- [#1287 Missing intermediate dependency versions](https://github.com/ecosyste-ms/packages/issues/1287)
- [#1693 Dependency package backfill can link to the wrong registry](https://github.com/ecosyste-ms/packages/issues/1693)

Provenance work is tracked in:

- [#418 Record npm provenance details](https://github.com/ecosyste-ms/packages/issues/418)
- [#1276 Record attestations](https://github.com/ecosyste-ms/packages/issues/1276)

Open pull requests that also improve relevant data coverage include:

- [#1653 Refresh existing version metadata on forced sync](https://github.com/ecosyste-ms/packages/pull/1653)
- [#1623 Add Chocolatey support](https://github.com/ecosyste-ms/packages/pull/1623), including package hashes and dependencies
- [#1624 Add Snap support](https://github.com/ecosyste-ms/packages/pull/1624), including artifact hashes and base dependencies

No open issue directly covers component producer selection, explicit unknown versus withheld values, field-level provenance and coverage, IANA-normalized structured hash output, or the signature and version handling required when an existing SBOM is amended.

## Action list

### Create

- [ ] Create `Add component producer to enrichment responses` in this repository. CISA now requires one producer for each component or an explicit unknown-provenance value. The implementation needs registry-specific evidence rules and must not treat a maintainer, namespace, author, or repository owner as the producer without qualification.
- [ ] Create `Report enrichment field status, source, and coverage` in this repository. Component fields need to distinguish `known`, `unknown`, `withheld`, `not_applicable`, `unsupported`, and collection failures. Each value should include its source and observation time so an SBOM author can judge whether the record is suitable for reuse.
- [ ] Create `Add version-scoped advisory enrichment` in this repository. Package responses currently embed every advisory associated with the package. SBOM consumers need a compact result for the requested version, including affected status, fixed versions, advisory identifiers, and VEX or CSAF references where available.
- [ ] Create `Record amendment metadata when enriching an SBOM` in the SBOM service repository. The service needs to preserve or replace the original signature correctly, update the SBOM version and timestamp, and record its tool name, tool version, format version, and generation context. These fields should not be added to ordinary Packages API component responses.

### Update

- [ ] Update [#1184](https://github.com/ecosyste-ms/packages/issues/1184) with the proposed version-aware batch enrichment response. Add one result per input, preserved order, missing and ambiguous statuses, a compact field projection, and field provenance. Link [#512](https://github.com/ecosyste-ms/packages/issues/512) as the older version-lookup case and close it as superseded when #1184 is implemented.
- [ ] Update [#1630](https://github.com/ecosyste-ms/packages/issues/1630) and [#337](https://github.com/ecosyste-ms/packages/issues/337) around one shared artifact model. The final CISA text calls for a hash of the component artifact, including a separate value and algorithm. Artifact records are needed for wheels, jars, platform gems, containers, and other versions with several files or builds.
- [ ] Update pull request [#1659](https://github.com/ecosyste-ms/packages/pull/1659) to state how its lookup response can move from a version-level `integrity` string to artifact records. It should also document algorithm aliases, encodings, and the fact that a missing lookup result may mean missing hash coverage rather than an unknown artifact.
- [ ] Update [#960](https://github.com/ecosyste-ms/packages/issues/960) so the requested version license output preserves the complete SPDX expression, operators, and exceptions. Link the accuracy reports in [#1424](https://github.com/ecosyste-ms/packages/issues/1424) and [#1705](https://github.com/ecosyste-ms/packages/issues/1705), since a normalized list of license IDs cannot carry all of the CISA Component License information.
- [ ] Update [#1205](https://github.com/ecosyste-ms/packages/issues/1205) and [#1206](https://github.com/ecosyste-ms/packages/issues/1206) to use a common `identifiers` response field alongside PURL. Each entry should state its identifier type, value, source, and artifact or component scope. CISA asks authors to include every known software identifier.
- [ ] Update [#1693](https://github.com/ecosyste-ms/packages/issues/1693), [#1188](https://github.com/ecosyste-ms/packages/issues/1188), [#1189](https://github.com/ecosyste-ms/packages/issues/1189), and [#1287](https://github.com/ecosyste-ms/packages/issues/1287) with their effect on SBOM dependency relationships. These bugs prevent the API from claiming accurate relationship targets or transitive coverage. The response also needs to distinguish declared requirements from resolved component edges.
- [ ] Update [#1684](https://github.com/ecosyste-ms/packages/issues/1684) to record that a Go `h1` directory hash has different artifact semantics from a hash of the downloaded module archive. Store its type and source explicitly instead of presenting it as interchangeable with an archive hash.
- [ ] Update [#1687](https://github.com/ecosyste-ms/packages/issues/1687) and [#1688](https://github.com/ecosyste-ms/packages/issues/1688) with the explicit-unknown requirement. Until their historical backfills are complete, enrichment responses should report that hash collection was not covered rather than returning an unexplained null value.
- [ ] Update [#1276](https://github.com/ecosyste-ms/packages/issues/1276) and [#418](https://github.com/ecosyste-ms/packages/issues/418) to distinguish package or artifact attestations from an SBOM Author Signature. Attestations add useful validation evidence but do not prove that the enriched SBOM document was signed after amendment.
- [ ] Update [#29](https://github.com/ecosyste-ms/packages/issues/29) to point to #1630 and close it as superseded if it no longer tracks separate work. Keeping two open hash umbrella issues makes coverage and ownership harder to follow.

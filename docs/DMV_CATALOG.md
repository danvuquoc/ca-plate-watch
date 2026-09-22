# DMV catalog provenance

Catalog version: **2026-09-21.1**. Inspected the live [DMV personalized plate form](https://www.dmv.ca.gov/wasapp/ipp2/initPers.do), **ipp2 version 84**, on September 21, 2026. The selection page is `startPers.do` after acknowledgement.

The catalog was read from the form's vehicle options, design cards (`selectPlate` handlers), and embedded validation/request scripts. These are lookup parameters, not a public API contract. Reverify this page when updating the catalog; do not infer wire values from display names or eligibility in the paper application.

## Vehicles and designs

| Vehicle | Request value | Online designs |
|---|---|---|
| Automobile | AUTO | All below |
| Commercial | COMM | All below |
| Trailer | TRAI | Environmental only |
| Motorcycle | MOTO | Environmental only |

`showPlateTypeSelect` explicitly hides every design except `R` for TRAI and MOTO, with a notice to apply by mail for other designs. The Environmental input remains the seven-character form for both vehicles.

| Design / exact plateName | plateType | plateLength |
|---|---|---|
| Environmental | R | 7 |
| Breast Cancer Awareness | Q | 6 |
| California Museums | J | 6 |
| California 1960s Legacy | Z | 7 |
| Pet Lover's | I | 6 |
| California Agriculture | D | 6 |
| California Memorial | G | 6 |
| California Coastal Commission | W | 7 |
| Lake Tahoe Conservancy | H | 7 |
| Yosemite Foundation | Y | 7 |
| California Arts Council | A | 6 |
| Veterans' Organization | V | 6 |
| Kids | K | 7 |

## Request and input rules

- `plateNameLow` is the lowercase exact name above. Image filenames use different aliases and must not be used as request names.
- `checkPers.do` receives URL-encoded form fields. The page serializes both character groups: `plateChar0` through `plateChar13`. Seven-character designs use indices 0–6; index 7 becomes available with a half-space except on Kids plates. Six-character designs use indices 8–13. Unused positions and full spaces are empty field values, preserving their indices.
- `/` is a half-space. Adjacent half-spaces are rejected. The additional eighth position follows the live form's behavior; six-character and Kids forms do not gain a position.
- Kids uses `.` at the chosen symbol position and `kidsPlate=heart|star|hand|plus`. The app displays these as ♥, ★, ✋, and + and requires exactly one symbol with 2–6 letters/numbers, within seven total positions.
- Veterans uses `vetDecalCd` and `vetDecalDesc`, taken from the form's `allOptions` list. All 73 nonempty choices are bundled in `VeteranDecal`. A decal does not change duplicate identity: text + vehicle + design.
- Centering and image-preview fields do not identify an availability lookup and are not submitted by the client. The app does not order or reserve plates.
- Only explicit known availability codes produce results. HTML pages, challenges, validation errors, and unknown codes remain errors and preserve the last confirmed status.

## Verification

Offline tests independently assert the 13 code/name/length mappings and the 28 eligible vehicle/design combinations, six/eight-position layouts, symbol/decal fields, and ineligible combinations. The opt-in live test makes seven sequential lookups: Automobile/Environmental, Commercial/Breast Cancer Awareness, Trailer/Environmental, Motorcycle/Environmental, Kids, Veterans, and Legacy with a half-space.

On September 21, 2026, all seven native lookups returned explicit `NOT_AVAILABLE` results. This verifies request acceptance for those examples, not future DMV uptime or every possible plate configuration. The native acknowledgement step returned a System Unavailable HTML page during inspection, while the subsequent availability endpoint still accepted the lookups. Browser acknowledgement allowed inspection of the live catalog. No plate was reserved or ordered.

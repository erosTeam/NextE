# 2026-07-15 Reader Thumbnail Geometry Verification Failure

## Incident

The Reader thumbnail refactor changed thumbnail geometry across local and online reading without first proving the visual result on the requested devices. It introduced an incorrect fixed shape and was presented as tested even though the checks did not cover the user-visible geometry.

## Mistakes

- Replaced source-proportional thumbnail rendering with fixed dimensions that distorted or cropped local thumbnails.
- Let the same geometry change affect online thumbnails without comparing the existing online path before and after the refactor.
- Treated build and logic-test success as acceptance evidence for aspect ratio, strip size, spacing, and reading-direction alignment.
- Did not validate local and online sources, short and long lists, and LTR and RTL modes before reporting completion.
- Removed the strip's outer spacing without preserving the requested scrollable head and tail spacing inside the list.

## Causes

- Thumbnail source selection and thumbnail presentation geometry were changed in one pass without preserving the established UI contract.
- The validation plan checked code execution but did not measure the rendered list and item bounds.
- The distinction between container padding and first/last item spacing was not encoded in the acceptance criteria.

## Consequences

- Local and online Reader thumbnails displayed with the wrong proportions.
- Portrait-heavy galleries became harder to scan, and normal landscape thumbnails produced excessive gaps.
- Short-list alignment and edge spacing required repeated correction.
- The user had to identify visual regressions that device validation should have caught.

## Required Handling For Similar Cases

- Preserve each image's decoded or supplied aspect ratio; use a bounded height and derive width from source geometry.
- Keep local-image reuse and online sprite rendering on the same presentation-geometry contract without forcing either source into a fixed aspect ratio.
- Validate LTR and RTL modes, a short list and a scrollable long list, and both local and online image sources before reporting completion.
- For a full-width horizontal strip, put head and tail spacing on the logical first and last list items. Do not use permanent horizontal container padding.
- Capture screenshots and layout dumps on every explicitly requested device. Record the list bounds and the logical first and last item bounds; build and unit tests are supporting gates, not visual acceptance.

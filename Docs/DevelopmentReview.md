# Development review

This review follows the original commits before history was reorganized. It separates the three manual development commits (`d3193aa`, `32cd423`, `793ad43`) from the later saved experiments, documentation, and FOV repair. The findings below come from reading their source and diffs; historical app builds were not rerun for this review.

## What changed, and when

| Original commit | Contribution | Issues present at that point and later resolution |
| --- | --- | --- |
| `d3193aa` | Cube objects, lighting, mouse capture, yaw/pitch camera movement, and an initial mapped player. | Normal matrices used the inverse alone instead of the inverse transpose. The player shader used camera view rotation rather than its world pose, and sent its unmapped position/normal to lighting. Renaming `Camera.update` left the smoke tests calling a removed method; their old uniform and sphere expectations also became stale. |
| `32cd423` | A four-sided cone, object yaw/pitch, and camera-world placement for the player/FOV. | The active `player_vertex` now computed the mapped world position and rigidly mapped normals before lighting; this repaired the earlier shader's space mismatch. The inverse-only model normal matrix remained wrong for rotated models. The cone still had fixed dimensions and did not derive its near/far rectangles from the projection. An unused `player_vertexa` retained incorrect view-space lighting varyings. |
| `793ad43` | Two side-by-side viewports and improved lit shading. | Both viewports still received the same camera. `draw` passed half the target width while the offscreen caller passed the full width, so offscreen rendering placed the second viewport beyond its attachment. The unused alternate vertex function was removed. |
| `48b2381` | Checkpoint of subsequent experiments; derives a mapped second camera and its world-space lighting eye, and uses `w = 0` for movement directions. | The cone refactor introduced the recorded app compile failures: an unhandled throwing call, renderer access to a private `make`, and `boundingBox` called on `MTKMesh` after changing its type from `MDLMesh`. The new `make` also declared an `MTKMesh` return while only assigning a property. These errors were introduced after the three manual commits. |
| `1e5bc9b`, `cd8ecd6` | Project guidance and a checkpoint of an existing instruction copy. | Documentation only. They preserved and described the broken experiment; they neither caused nor repaired runtime behavior. |
| `ca77928` | Configurable rectangular FOV outline using the projection's vertical angle, aspect, near, and far. | Repairs cone setup, inverse-transpose normals, and full-target viewport sizing; adds scissor rectangles, current uniform checks, and scene/FOV GPU checks. Its commit records a successful isolated build and Metal validation run. |

## Findings that need precise interpretation

- **Uniform names were inconsistent, but their memory layout was not thereby mismatched.** In `793ad43`, Swift's `inverseMatrix` and `inverseViewMatrix` occupied the same positions and used the same matrix types as Metal's `entrancePortalInverseMatrix` and `viewInverseMatrix`. Names do not affect a byte upload. The stale 208-byte comment and tests were inaccurate after fields were added; they were not evidence that Swift and Metal had different layouts.
- **The negative camera yaw used for movement was intentional.** The view matrix maps world coordinates into the camera; moving along the camera's local axes requires the inverse rotation. The early direction used `w = 1` while multiplying only by rotation, so changing it to `w = 0` clarified the contract without changing that result.
- **Mouse capture already had several correct cleanup paths.** Escape, responder loss, window focus loss, and deinitialization released capture. `viewDidMoveToWindow` cleared input but did not explicitly release capture on detachment. The current cleanup fixes and tests that remaining lifecycle case; it does not imply that all earlier cleanup was missing.
- **A mapped camera is not traversal.** None of these commits establishes body crossing, wall/rim collision, aperture clipping, or portal-surface compositing. Their absence is a scope boundary, not a regression introduced by the FOV repair.

## Current cleanup

The final design preserves the scene and configurable FOV while making their relationships explicit. `ObjectPlacement` derives model and rigid-frame matrices from position, scale, yaw, and pitch. `ObjectID` names scene objects; the renderer rejects duplicate IDs, missing portal objects, and invalid placements. `Transforms.portalMapping` supplies one forward transfer and its inverse. The CPU applies that mapping once to the camera and mapped debug objects, then the shared vertex shader uses each complete world model. The final-model inverse transpose transforms normals into the same space as the light and active viewport's eye.

Mesh builders share one packed vertex layout. Swift and Metal uniform fields now use matching names and omit the three matrices previously used for extra mapping in the shader, reducing the uniform stride from 496 to 304 bytes. Scene placements and mouse sensitivity live with the other editable configuration values. Input cleanup explicitly handles retained view detachment and SwiftUI dismantling, clears held keys and deltas, and supports reattachment.

## Reorganized history

The replacement sequence starts from `5fc53ac` and groups the work by responsibility:

1. Camera and input controls, explicit capture lifecycle, the needed renderer call sites, camera/input checks, and control documentation.
2. Lit scene objects, placement and rigid frames, shared mesh layout and portal mapping, both camera previews, and the configurable FOV. Rendering, shaders, uniforms, and their geometry/lighting checks stay together because they share one coordinate and GPU data contract.
3. Current README, project guidance, removal of the obsolete instruction copy, and this historical review.

The final source includes the later mapped-camera and FOV work as well as the manual experiments. A local backup branch retains the original history and verified final state; no other branch or tag is rewritten. The final tracked tree is compared with that saved state after rebuilding history.

## Verification evidence

The `48b2381` and `cd8ecd6` commit bodies record app build failures before GPU checks could run. The `ca77928` commit body records `Scripts/check.sh` passing with an isolated temporary build directory and Metal API validation, including custom FOV geometry, invalid parameters, projection depth, aspect scaling, portal transforms, camera movement, uniform offsets, and GPU output at square, wide, tall, and odd-width sizes. This is recorded historical evidence. The current cleanup was also checked separately with the same isolated build command and Metal validation; its expanded checks passed before the history rewrite.

The current automated suite adds placement/normal/mapping checks, invalid-scene rejection, and deterministic GPU comparisons against independent geometry and lighting calculations. Input checks use native view/window lifecycle callbacks with inert injected cursor operations to cover Escape, focus/responder loss, detachment, actual hidden-window close/reopen, reattachment, and SwiftUI dismantling, including repeated cleanup and events after teardown. Confirming actual system cursor visibility and mouse association after those interactions still requires an interactive macOS session. Report that manual result separately from automated checks.

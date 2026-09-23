# Project instructions — MetslStarter 3D

## Scope and current state

This is the macOS Swift/Metal 3D portal experiment in `portal-demo-3d`, built with `MetslStarter.xcodeproj` and the `MetslStarter` scheme. The sibling `../metsl-starter` is the separate flat 2D prototype. Reuse its lessons, but do not copy its XY-only movement, fixed rendering depths, square canvas, or triangle visibility mask into this perspective scene.

The current code experiments with entrance/exit objects, a mapped player/FOV mesh, and two camera viewports. A mapped view is not proof that traversal, aperture clipping, collision, or reverse portal views are implemented. Inspect the code before describing a feature as complete. The portal guidance below applies as those systems are developed; it is not an instruction to implement everything in one task.

Keep work within the user's request. Preserve the current scene, controls, and viewport arrangement unless that request requires changing them. Explain changes briefly: where they live, what space their values use, and why the transform order is correct.

## Commit workflow

- Checkpoint the project in Git before editing code, configuration, or documentation. Read-only inspection and checks may run first.
- A clean working tree means the current HEAD is the checkpoint; do not create an empty commit.
- If dirty, review and commit the intended existing project work before new edits. Preserve user changes. Never reset or discard experiments to obtain a clean tree.
- A checkpoint may preserve an already broken experiment; run the relevant checks and record the actual failures in its commit body. Do not present it as a passing baseline.
- Stage explicit paths, never `git add .` or `git add -A`. Do not use `--no-verify`.
- Use Conventional Commit subjects and describe verification in commit bodies. Separate checkpoints from completed changes.
- Commit completed work after its relevant checks pass unless the user requests uncommitted changes. For documentation-only work, verify the document and whitespace; report existing code failures separately. Do not push unless requested.

## Organization

Use the existing files before introducing abstractions. Extract small types when a responsibility is actually needed:

| Responsibility | Location / guidance |
| --- | --- |
| Editable positions, dimensions, colors, lights, speeds, projection settings | `Sources/Scene/SceneConfiguration.swift`. Move new tunable values here instead of scattering literals through drawing code. |
| Translation, rotation, projection, point/direction conversions | `Sources/Scene/Transforms.swift`. Keep convention-sensitive math together. |
| Camera pose, view matrix, movement | `Sources/Scene/Camera.swift`. Distinguish a local movement offset from the final world-space camera position. |
| Native events, held keys, accumulated mouse deltas, focus/cursor lifecycle | `Sources/Input/KeyboardMetalView.swift`. Mesh builders never read input. |
| Object identity, mesh reference, placement | `Sources/Rendering/RenderObject.swift`. Use IDs rather than array positions; reject duplicate IDs when adding scene construction helpers. |
| Unit geometry, vertex layout, indices, local bounds | `Sources/Rendering/*Mesh.swift`. Keep Model I/O construction separate from Metal mesh use. |
| Scene update orchestration, resource setup, per-view draw encoding | `Sources/Rendering/Renderer.swift`. Keep math and input handling out of draw loops where practical. |
| CPU/GPU data contract | `Sources/Rendering/ShaderUniforms.swift` and `Sources/Shaders/Shaders.metal`, changed together. |
| MTKView setup and renderer lifetime | `Sources/Views/MetalView.swift`; window setup belongs in `Sources/App/MetslStarterApp.swift`. |

When placement becomes mutable, group position, scale, and orientation in one value such as `ObjectPlacement`. Derive its model matrix; avoid storing an independently mutable matrix and transform fields that can disagree. A shared `PlayerState` should drive the body, camera, and FOV representation once traversal is added. Derived views/clones should follow this source state rather than accumulate transforms from their previous frame.

Introduce portal frame/link and crossing helpers in `Sources/Scene/` when implementing those features. Keep `Renderer` responsible for using their results. Share immutable GPU meshes across clones; changing shared vertex buffers affects every instance, so use independent geometry when deformation must be unique.

## Coordinate and transform contract

- Preserve row vectors and the existing +Z-forward camera convention: `localPosition * model * view * projection`. SIMD's column storage does not change multiplication order.
- Use world units for physical 3D dimensions and radians for angles. Z is spatial depth here, not a fixed layer number as in the 2D prototype.
- The current object model order is `scale * rotateY(yaw) * rotateX(pitch) * translation`. Rotations do not commute. Preserve that order unless intentionally migrating it with tests.
- Scale and rotate about the mesh's defined local pivot, then translate. To rotate around another pivot, explicitly move to/from that pivot; do not rotate its world position accidentally.
- A rigid frame is rotation plus translation, excluding visual scale. `worldToLocal = inverse(localToWorld)` changes the coordinate system; it does not move the world or automatically zero every point.
- Use `SIMD4(position, 1)` for points and `SIMD4(direction, 0)` for directions, velocity, and movement axes. Invert only nonsingular transforms; reject zero-scale inputs if inversion is required.
- Name values by space, for example `eyeWorld`, `pointInExit`, and `cameraWorld`. Both operands in a distance, dot product, or intersection test must use the same coordinate system.
- Camera world pose is the inverse of its view matrix. A camera's stored movement offset need not equal its world position when a base transform is present. Obtain the world eye from the camera-world transform.
- Preserve perspective and Metal NDC depth 0...1. With the current conventional depth setup, clear depth to 1 and compare with `.less`; require `aspect > 0` and `0 < near < far`.
- A yaw/pitch pair cannot represent arbitrary rolled portal exits. When adding unrestricted 3D traversal, use a normalized quaternion or orthonormal basis for the full pose. Adapt SIMD quaternion matrices to the row-vector convention explicitly and test transformed basis vectors.

## Portal mapping: one definition, both directions

Define portal-local X/Y as the opening plane, Z = 0 as its surface, and an explicit front normal (prefer +Z). Keep opening half-width/half-height separate from the rigid frame and from the decorative mesh thickness.

For row-vector rigid frames `A` (entrance) and `B` (exit):

```text
transferAB = inverse(A) * connection * B
transferBA = inverse(transferAB)
mappedPoint = pointWorld * transferAB           // w = 1
mappedDirection = directionWorld * transferAB   // w = 0
mappedCameraWorld = cameraWorld * transferAB
mappedView = inverse(mappedCameraWorld)
```

The current experiment aligns frames directly, so `connection` is identity. Do not add a half-turn just because a portal tutorial uses one. If implementing a front-to-front traversal convention with both local fronts defined as +Z, use a local Y half-turn as the connection and update rendering/traversal tests together. A portal's placement rotation and the connection rotation have different jobs.

- Share the same directed mapping between the virtual camera, object clones, traversal, and any movement-control basis. Apply it exactly once to each world pose. Camera-relative debug meshes must first be placed in the source camera's world frame.
- Reverse viewing needs the reverse mapping. The 2D demo's 180-degree arrangement hid this because the forward and reverse planar transforms coincided. Do not assume that equality for arbitrary 3D portal arrangements.
- Track each rendered portal view/clone's entrance and exit explicitly. Clipping against both openings cannot correct a clone placed using the wrong direction. If both portals are visible, one globally selected clone transform is insufficient.
- Map full orientation and velocity, preserving speed under rigid transforms. Keep visual scale unchanged. Scaled portals require a separate explicit design for body size, speed, aperture fit, and projection.

## Traversal and body dimensions

Keep crossing detection in scene/physics code, separate from per-fragment visibility. Test the movement segment between the previous and proposed player center; testing only the proposed point can miss a portal between frames.

In the entrance's local coordinates:

```text
start = previousWorld * worldToEntrance
end = proposedWorld * worldToEntrance
require an allowed sign change across z = 0
t = start.z / (start.z - end.z)
hit = start + t * (end - start)
require the center hit inside the finite opening
```

- Define whether traversal is one-sided or two-sided. Handle parallel movement, starting on the plane, exact-plane arrivals, and near-zero denominators explicitly.
- Choose the earliest finite-opening center crossing first, then check body clearance at its entrance and exit. If the body does not fit, do not automatically teleport through a farther candidate in that step. Map an accepted crossing's proposed endpoint as well as orientation so lateral offset and movement remaining after the crossing are preserved; do not snap to the exit center.
- Compute one crossing result for the player and apply it consistently to the body, camera, velocity, and control frame. Start the next step from the mapped position. Use a small, documented exit-side clearance when necessary to prevent numerical recrossing.
- Initially bound traversal to one crossing per update and document that limit. If long steps or multiple crossings are required, process the remaining movement with a bounded loop or substeps.
- Derive dimensions from local geometry/collider metadata and placement scale. Scale alone is not a radius or width. Preserve needed bounds from `MDLMesh` before conversion, or return explicit bounds alongside `MTKMesh`.
- For a spherical collider, an enclosing radius is `localRadius * max(abs(scale.x), abs(scale.y), abs(scale.z))`. Check both X and Y clearance at both openings. Capsules/boxes need their extent projected onto the aperture axes; a conservative sphere is acceptable only when documented.
- Passing an aperture-fit test is not collision handling. Rejecting teleportation alone lets ordinary motion continue through a wall. Wall/rim contact, sliding, and partial-body clipping are separate features.

## Input and camera behavior

- Sample input once per update. Consume accumulated mouse delta once, then derive both camera views from that state; rendering another viewport must not consume input again or advance movement twice.
- Held movement and keyboard rotation use elapsed seconds; normalize nonzero movement to keep diagonal speed consistent and clamp long pauses. Mouse delta already measures accumulated movement: apply sensitivity without multiplying it by delta time again.
- Preserve the intended grounded or free-flight movement model. When traversal rotates the control frame, holding a key should continue smoothly through the exit. Do not implement arbitrary 3D mappings with a hardcoded sign flip or one planar angle.
- Keep camera-look changes and portal mapping coherent; a subsequent mouse update must not overwrite the mapped orientation. Document how world-up, pitch limits, and roll behave when non-upright portals are introduced.
- Clear held input and pending mouse deltas on focus loss/detachment. Restore cursor visibility and association on Escape, loss of capture, and teardown. Resizing or rendering should not unexpectedly change the heading.

## Metal, visibility, and multiple views

- Construct meshes, pipelines, and depth states outside the frame loop. Propagate setup errors rather than force-unwrapping optional scene objects.
- The current mesh layout is packed position `.float3` at byte 0, normal `.float3` at byte 12, UV `.float2` at byte 24, stride 32, in vertex buffer 0. Uniforms use buffer 1 in both stages. Different meshes may share a pipeline only when their vertex layouts match. Swift `SIMD3<Float>` storage is not automatically a packed 12-byte field.
- Keep Swift/Metal uniform fields in identical order and compatible types/alignment. Use `MemoryLayout.stride` for uploads and check offsets when fields change; do not trust old size comments. A `float3x3` has padded columns.
- Pass world-space position as a varying when clipping or lighting needs it. Fragment `[[position]].xy` is a drawable-pixel position, not a world point; dividing by resolution does not convert it to portal coordinates. Reconstructing from depth requires the matching inverse projection/view and viewport conversion.
- Transform normals with the inverse transpose of the relevant linear transform and normalize them. For row normals, use `normal * transpose(inverse(linearTransform))`. Apply additional rigid portal rotation consistently. Keep lights, normals, eye, and fragment positions in one space; specular lighting must use the active viewport's world-space eye.
- Distinguish full render-target pixel dimensions from each viewport's origin and size. Fit every viewport inside the attachment and derive perspective aspect from that viewport. Use matching scissor/depth handling when needed. Test onscreen and offscreen paths against the same size contract.
- AppKit bounds/input use points; drawables, texture sizes, and Metal viewports use pixels. Account for Retina scale and viewport origin when converting pointer positions. Picking in 3D requires an unprojected ray plus a surface/depth query.
- A second camera preview or FOV cone is a debugging aid, not a portal surface render. Actual portal visibility needs aperture masking/compositing and an exit-plane clipping strategy that removes geometry between the virtual eye and the exit. Implement those deliberately; do not reuse the flat cone shader as complete 3D occlusion.
- Draw opaque geometry with depth writes. If adding translucent FOV/debug geometry, enable the appropriate alpha blending, preserve depth testing, and normally disable its depth writes. Sorting overlapping transparent 3D objects is only an approximation. Match MSAA sample counts across pipelines and attachments.
- Keep recursion, multiple portal pairs, physics engines, and complex transparency outside scope until requested. Start with one directed rendered view, then verify its reverse independently.

## Verification

Run `./Scripts/check.sh` before committing code changes. It builds the app and attempts the headless Metal smoke checks with API validation. Use an isolated build directory for this sibling to avoid sharing `MetslStarter-build` with the 2D project:

```sh
BUILD_DIR="$(mktemp -d /tmp/portal-demo-3d-check.XXXXXX)" ./Scripts/check.sh
git diff --check
```

Keep products outside Desktop/iCloud-synced source directories to avoid signing metadata problems. Toolchain/GPU access may require execution outside the tool sandbox. Documentation-only changes need content/path review and `git diff --check` rather than a new GPU test.

Add focused checks as behavior changes:

- Transform/inverse round trips, basis-vector rotation, pivot behavior, and projection near/far depth.
- Independently translated/rotated entrance and exit frames, including pitch/roll and a non-180-degree pair; forward and reverse camera/object mapping must agree and round-trip.
- Crossing from permitted sides, high-speed steps, exact-plane arrivals, missed openings, unequal aperture sizes, and live collider resizing. Rejected fit and physical collision must be tested separately.
- Preserved heading/velocity/control basis across traversal and return; key holds, diagonal speed, mouse-delta consumption, and focus cleanup.
- GPU output for each viewport, correct active-camera lighting, clipping, depth, resized aspect ratios, Retina scaling, and Swift/Metal layout. An app build alone does not verify portal rendering.

Use deterministic fixtures independent of the user's editable scene when possible. Do not weaken checks merely to make experiments pass. State exactly which checks ran and which were blocked.

Verification updated on 2026-09-22: `Scripts/check.sh` passes the app build and Metal API validation checks for custom frustum geometry, source-aspect resizing, translated/pitched/rolled portal round trips, placement order, 304-byte uniforms, rotated/nonuniformly scaled normals, active-camera lighting, and two-view rendering at square, wide, tall, and odd-width target sizes. Hidden-window input tests cover Escape, focus loss, retained detachment, SwiftUI teardown, closing, and reopening with inert cursor callbacks. Actual system cursor visibility/association remains a manual check. The README describes the current 3D scene; these checks do not establish traversal, aperture clipping, collision, or portal compositing.

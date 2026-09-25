# MetslStarter 3D

A macOS Swift/Metal experiment with entrance and exit objects, a mapped player and camera field-of-view outline, and an optional mapped-camera preview. The main viewport draws the scene from the source camera. Its entrance quad displays the image rendered from the camera's pose mapped from the entrance to the exit.

The entrance samples the corresponding screen position in the mapped image, so it shows the matching section through its opening instead of squeezing the whole image onto the quad. The optional right preview and FOV outline are debugging views. Exit-plane clipping, player traversal, collision, and recursive portals are not implemented.

## Run and controls

1. Open `MetslStarter.xcodeproj`.
2. Select the **MetslStarter** scheme and **My Mac**.
3. Press **Command-R**.

Click the scene to capture the mouse for looking around. **W/S** moves forward/backward and **A/D** moves left/right. **Escape** releases the mouse and clears held input. Closing and reopening the window resets the camera.

In `Sources/Scene/SceneConfiguration.swift`, `showsMappedPreview = false` makes the main view fill the window. Set it to `true` and rebuild/run to restore the side-by-side preview. The entrance texture still updates in both modes; the flag controls only the window layout and its matching render dimensions.

The project uses SwiftUI, AppKit, MetalKit, Model I/O, and SIMD, with no external packages.

## A scene for inspecting the connection

The entrance is centered at `[0, 0, 3]`. The exit is at `[4, 0, 6]`, turned 60 degrees around Y. Both openings are 2 units wide and 3 units tall. They stand on a shared floor at `Y = -1.5`. This spacing leaves room to move around each opening, and the angled exit makes the change in viewing direction easy to see.

Blue rims identify the portals; neutral objects give the view recognizable shapes at different distances. Teal remains reserved for the mapped player and FOV. The landmarks have specific jobs:

| Landmark | What to look for |
| --- | --- |
| Near block and farther tall pillar beyond the exit | Move sideways: the near block should shift more across the opening than the distant pillar. This relative movement is parallax. |
| Sphere beyond the exit | Recognize the destination from its curved shape and compare its appearance through the entrance with a direct view. |
| Thin pillar beside the exit opening | Check how a narrow object enters and leaves the image at the aperture's edge, especially from oblique angles. |
| Foreground block beside the entrance | Move until it overlaps the entrance; normal depth testing should let it hide that part of the quad. |
| Rear block behind the entrance | Where the quad overlaps it, the quad's depth should hide it. Outside the quad, the ordinary source scene remains visible. |
| Low block on the near side of the exit | This deliberately sits between the virtual eye and the exit plane. It is a probe for future exit-plane clipping: it can currently appear in the captured image when it should be excluded from a completed portal view. |

The floor is a unit cube scaled to `18 × 0.2 × 18`. Its center is placed half its thickness below `floorHeight`, so its **top**, rather than its middle, meets the portals' lower edges. Thin boxes form a one-unit grid just above that top surface; their height separates their visible faces from the floor and avoids coplanar flicker. The floor, grid strips, rims, and box landmarks all reuse one immutable cube mesh. Each instance has its own placement, so no geometry is rebuilt each frame.

All dimensions and placements live in `SceneConfiguration.swift`. Landmarks around the exit are specified in **exit-local coordinates**: X goes across the opening, Y goes up, and positive Z goes beyond it. During scene construction, `localPosition * exit.rigidFrame` converts each offset to a world position once. These are ordinary world objects, not mapped copies of the player. The rigid frame excludes the portal's visual scale, so changing the opening size does not stretch the landmark offsets.

To explore the scene, first strafe left and right while facing the entrance, then approach one edge and look through it at an angle. Walk around to compare the exit landmarks directly, and look down at the grid to judge distance and orientation. Enable `showsMappedPreview` to compare the complete captured image with the section shown by the entrance. Resize to a tall or wide window and repeat. These are manual inspection routes; walking through a portal does not teleport the camera, and the floor and objects do not provide collision.

## Custom field of view and length

`ConeMesh.make` returns an `MTKMesh` and takes the same four values as a perspective projection:

```swift
let coneMesh = try ConeMesh.make(
    device: device,
    fieldOfView: 70 * .pi / 180,
    aspect: Float(viewportWidth) / Float(viewportHeight),
    near: 0.1,
    far: 100
)
```

With two viewports, use the width and height of the camera's viewport, rather than the full window.

| Parameter | Meaning |
| --- | --- |
| `fieldOfView` | Full vertical viewing angle, in radians. Multiply degrees by `.pi / 180`. |
| `aspect` | Viewport width divided by height; determines the horizontal angle. |
| `near` | Distance from the eye to the near plane, in world units. |
| `far` | Distance from the eye to the far plane, in world units. |

The visible length is `far - near`. For a desired length of 20 starting at `near = 0.1`, set `far = 20.1`. All parameters must be finite, with `0 < fieldOfView < .pi`, `aspect > 0`, and `0 < near < far`; invalid values throw an error.

Despite its name, this mesh is a rectangular viewing **frustum**: a pyramid cut off at its near and far planes. It has eight corners and twelve line edges, so both plane boundaries are visible without filled faces hiding the scene. Its local origin is the camera's eye and it extends along **+Z**. At either plane's distance `z`, the corners follow:

```text
halfHeight = z * tan(fieldOfView / 2)
halfWidth  = halfHeight * aspect
corners    = (±halfWidth, ±halfHeight, z)
```

This makes the edges match the camera's projection angles exactly. An extra rotation, translation, or arbitrary scale would offset or distort that match.

The observing camera can still clip or occlude parts of this outline. With `far: 100`, the outline extends the full 100 units from the source eye; it is not shortened for display.

For the running scene, edit `fieldOfViewRadians`, `nearPlane`, and `farPlane` in `Sources/Scene/SceneConfiguration.swift`. Both the camera projection and the outline read those values. The renderer builds the mesh once with `aspect: 1`, then scales its local X coordinates by the source viewport's current aspect before placement. Resizing changes that scale and the projection without rebuilding or modifying the GPU mesh.

## Placement and portal mapping

`ObjectPlacement` groups an object's position, scale, yaw, and pitch. Edit the entrance, exit, and player placements in `SceneConfiguration.swift`, for example:

```swift
static let exitPlacement = ObjectPlacement(
    position: [4, 0, 6],
    scale: [2, 3, 0.1],
    yaw: .pi / 3,
    pitch: 0
)
```

Positions and dimensions use world units; angles use radians. The model matrix is derived as `scale * rotateY(yaw) * rotateX(pitch) * translation`. The `rigidFrame` uses only the rotation and translation, so decorative scale does not stretch a portal mapping. There is no separate stored matrix that can disagree with the editable placement. `RenderObject` pairs that placement with a mesh and an `ObjectID`; duplicate IDs and invalid placements are rejected when the renderer is created.

Scene object placements use world space. The player and FOV placements use source-camera space. The renderer first expands the outline to the source viewport's aspect, then places it in the source camera's world frame, then applies the portal mapping once:

```text
pointWorld = pointLocal * aspectScale * sourceCameraWorld
transferAB = inverse(entranceFrame) * exitFrame
pointMapped = pointWorld * transferAB
transferBA = inverse(transferAB)
```

These are row-vector transforms, so they apply from left to right. `sourceCameraWorld` is the inverse of the source camera's view matrix. `Transforms.portalMapping` creates both directed transfers from the portal frames. This scene aligns those frames directly, with no additional half-turn. The same `transferAB` maps the camera, player, and FOV. The mapped camera's view matrix is the inverse of its mapped world frame. `transferBA` is available for reverse mapping, but a reverse portal view is not currently drawn.

The CPU computes complete world model matrices once per frame, before rendering either camera. The `scene_vertex` shader then applies only `model * view * projection`; it does not apply the portal mapping again. Lighting receives the resulting world position and a normal transformed by the final model's inverse transpose. `lit_fragment` shades solid objects and `fov_fragment` gives the outline a constant color.

The source view draws the mapped outline using the **source** viewport's aspect; the mapped capture omits it so it does not cover the portal image. Each camera render uses its own world-space eye for lighting. The mapped image uses the source viewport's dimensions and projection aspect; when enabled, the right viewport displays that complete image.

## How the entrance image and preview work

A texture is a GPU image. Each frame now has two render passes:

1. Render the scene from the mapped camera into a color texture, with a separate depth texture so nearer surfaces hide farther ones.
2. Draw the main scene with the captured color texture on the entrance quad. If `showsMappedPreview` is enabled, draw the same image in a separate right viewport.

The depth texture is used while making the image. The capture retains the filled entrance object and omits the filled exit object, textured quad, and FOV outline. The portal rims and ordinary landmarks remain visible. In the source view, the quad replaces the filled entrance object whenever a quad is present, so the cube does not cover the image. These object filters do not clip geometry against the exit plane or implement recursive portal views.

The quad uses `entrancePlacement` and lies in its local XY plane at `z = 0`. Its triangles determine **where** the portal image can be drawn. For every fragment within those triangles, the surface shader divides the fragment's pixel position by the mapped texture dimensions to choose **which pixel of the image** to read. For example, a fragment halfway across and halfway down the main viewport samples the center of the mapped image.

This screen-space sampling works because the main viewport starts at pixel `(0, 0)`, the mapped texture has exactly that viewport's dimensions, and both cameras use the same projection. It uses the fragment's pixel coordinates, not the quad's mesh UVs or clip-space coordinates. The image is opaque and unlit because it already contains the captured scene's lighting. Normal depth testing and depth writes let foreground objects cover it and hide objects behind it. This supplies the entrance's image, but the missing exit-plane clipping can still let geometry on the wrong side of the exit appear in that image.

`Renderer.encodeFrame` receives the full render-target size in pixels. With the preview hidden, the source viewport and cached textures use the full width and height. With it enabled, their width is `floor(fullWidth / 2)` and the right preview receives the remaining width, including an extra pixel for odd target widths. The textures always match the source viewport and are reused until their required size changes. Resizing updates the textures, projection, and FOV aspect together.

`Renderer.swift` owns the textures and encodes the passes. Separate quad and preview shaders in `Shaders.metal` read the same image from texture slot 0. The quad normalizes pixel positions using the matching texture size; the right preview uses a `viewportRect` in fragment buffer 2 to subtract its nonzero origin and normalize by its own size. The existing 352-byte scene uniforms in buffer 1 are unchanged.

## Adjusting the lighting

The lighting controls live in `SceneConfiguration.swift`. The main light is a white point light at `lightPositionWorld = [-3, 5, -1, 1]`; its position stays fixed in the world as the camera moves. It has no distance falloff.

| Control | What it changes |
| --- | --- |
| `lightPositionWorld`, `lightColor` | Where the main light sits, and a shared color tint for all illumination. Move the main light to change which faces catch it. |
| `ambientIntensity` (`0.38`) | The constant illumination that keeps the darkest faces visible. |
| `diffuseIntensity` (`0.85`) | How strongly faces brighten when they face the main light. |
| `fillLightDirectionWorld` (`[2, 3, 5, 0]`), `fillIntensity` (`0.22`) | A weaker light that reveals faces turned away from the main light. This is a world-space direction **toward** the fill light, rather than a position; it adds diffuse light only. |
| `specularIntensity` (`0.045`), `specularShininess` (`20`) | The strength and concentration of the highlight. Higher shininess makes the highlight smaller and sharper. |

The diffuse lighting stays attached to the world; the highlight depends on the active viewport's eye. The FOV outline remains unlit. There are no shadow maps, so objects do not cast shadows onto one another. Colors and lighting strengths are artistic display values written directly to `.bgra8Unorm`, with no explicit sRGB transfer or calibrated linear-light workflow.

## Start editing here

| Change | File |
| --- | --- |
| Preview flag, FOV, near/far distances, portal/landmark placements, floor/grid/rim dimensions, colors, lights, camera speed/sensitivity | `Sources/Scene/SceneConfiguration.swift` |
| FOV corners, line edges, mesh parameters | `Sources/Rendering/ConeMesh.swift` |
| Entrance quad geometry and UV coordinates | `Sources/Rendering/QuadMesh.swift` |
| Shared packed vertex descriptor for all meshes | `Sources/Rendering/MeshVertexLayout.swift` |
| Scene objects, mapping, offscreen textures, render passes, viewport setup | `Sources/Rendering/Renderer.swift` |
| Object identity, placement, model matrix, rigid frame | `Sources/Rendering/RenderObject.swift` |
| Camera state and movement | `Sources/Scene/Camera.swift` |
| Portal mapping, normal matrices, projection, translation, rotation, scale | `Sources/Scene/Transforms.swift` |
| Keyboard and mouse capture | `Sources/Input/KeyboardMetalView.swift` |
| Vertex transforms, lighting, unlit FOV color, quad/preview texture sampling | `Sources/Shaders/Shaders.metal` |
| CPU uniform layout, kept in sync with Metal | `Sources/Rendering/ShaderUniforms.swift` |
| MTKView setup and renderer lifetime | `Sources/Views/MetalView.swift` |

The transform convention is `position * model * view * projection`, with +Z forward and Metal depth 0...1. Depth clears to 1 and compares with `.less`. Mesh attributes use buffer 0; uniforms use buffer 1 in both shader stages. `MeshVertexLayout` supplies the shared layout: position at byte 0, normal at byte 12, UV at byte 24, and a 32-byte stride.

Swift and Metal uniform names, order, and types match, including `lightPositionWorld` and the active camera's `eyeWorld`. With complete world models computed on the CPU, uniforms no longer need separate camera/portal mapping matrices. Their current stride is 352 bytes, including the padded normal matrix and lighting controls; the checks verify the offsets.

## Verify

Use an isolated build directory for this 3D project, separate from the sibling 2D experiment:

```sh
BUILD_DIR="$(mktemp -d /tmp/portal-demo-3d-check.XXXXXX)" ./Scripts/check.sh
git diff --check
```

The script builds the Debug app, compiles the files in `Tests/`, and attempts offscreen GPU rendering with Metal API validation enabled. A successful app build alone does not verify the rendered output. A Metal GPU and access to the Xcode toolchain are required for the full check.

Checks cover custom frustum corners and edges, invalid parameters, near/far projection depth, aspect scaling, placement pivots and order, forward/reverse portal transforms, inverse-transpose normals, and uniform offsets. Deterministic renderer fixtures check transformed solid and mapped objects against independent geometry and lighting calculations, including each viewport's world-space eye. Scene and outline rendering also run at square, wide, tall, and odd-width sizes. Invalid scenes test missing portals, duplicate IDs, and singular scales.

Texture-preview checks compare the right view's pixels with the captured image, including orientation and resampling at odd widths. They verify depth occlusion in the capture, omission of the exit, textured quad, and FOV from that capture, texture dimensions and usage, resource reuse, resize reallocation, and stable repeated frames. These GPU fixtures use single-sample targets; they do not verify MSAA.

Entrance-surface checks verify unlit, screen-aligned image sampling on frontal and tilted quads with moved/rotated cameras. Their expected samples distinguish this behavior from squeezing the full image into mesh UVs. They also check replacement of the filled entrance, foreground occlusion, and depth rejection of geometry behind the quad. An independent floor fixture verifies a horizontal surface's lighting, raised-object depth occlusion, and floor visibility from both camera views.

Both preview flag settings are tested at square, wide, tall, and odd-width sizes. Full-window output is compared pixel for pixel with an equivalent split source view, including its mapped capture and FOV aspect. Checks cover the rightmost scene pixels, resize callbacks, target reuse, and minimum widths. The app build and full Metal API validation suite passed after the diagnostic scene and floor update. These automated checks do not establish exit-plane clipping, traversal, collision, or recursion, and do not replace manual inspection of the running app.

The lighting checks verify each control independently, diffuse/fill lighting that stays fixed as the camera moves, highlights that respond to the active eye, and finite output for coincident or opposing light/eye directions. They also verify the synchronized 352-byte uniform layout and the outline's exact unlit color.

Input checks cover held keys, camera movement/look, consuming mouse deltas once, and native view/window lifecycle callbacks for Escape, focus loss, detachment, window close/reopen, reattachment, and SwiftUI dismantling. They inject inert cursor callbacks, so they can verify release balance without changing the user's cursor. Actual cursor visibility and mouse association after those interactions remain a separate manual macOS check; the automated checks do not prove those operating-system effects.

Keep generated products outside synced Desktop/Documents source directories to avoid signing metadata problems. Running from Xcode uses its normal DerivedData location.

For the original manual commits, later fixes, and the reason for reorganizing their history, see [Development review](Docs/DevelopmentReview.md).

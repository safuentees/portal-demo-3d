# MetslStarter 3D

A macOS Swift/Metal experiment with entrance and exit objects, a mapped player and camera field-of-view outline, and two side-by-side perspective viewports. The left viewport uses the source camera; the right uses its pose mapped from the entrance to the exit.

The second viewport and FOV outline are debugging views. Player traversal, collision, aperture masking, and a composited portal surface are not implemented by this camera mapping.

## Run and controls

1. Open `MetslStarter.xcodeproj`.
2. Select the **MetslStarter** scheme and **My Mac**.
3. Press **Command-R**.

Click the scene to capture the mouse for looking around. **W/S** moves forward/backward and **A/D** moves left/right. **Escape** releases the mouse and clears held input. Closing and reopening the window resets the camera.

The project uses SwiftUI, AppKit, MetalKit, Model I/O, and SIMD, with no external packages.

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
    position: [1, 0, 3],
    scale: [1, 1.5, 0.1],
    yaw: .pi / 2,
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

The CPU computes complete world model matrices once per frame, before drawing either viewport. The `scene_vertex` shader then applies only `model * view * projection`; it does not apply the portal mapping again. Lighting receives the resulting world position and a normal transformed by the final model's inverse transpose. `lit_fragment` shades solid objects and `fov_fragment` gives the outline a constant color.

Both observing viewports draw the same mapped outline using the **source** viewport's aspect. Each viewport uses its own aspect for its projection and its own world-space eye for lighting. `Renderer.encodeFrame` receives the full render-target size in pixels and splits it into the two viewports internally; onscreen and offscreen rendering use the same contract.

## Start editing here

| Change | File |
| --- | --- |
| FOV, near/far distances, placements, colors, lights, camera speed/sensitivity | `Sources/Scene/SceneConfiguration.swift` |
| FOV corners, line edges, mesh parameters | `Sources/Rendering/ConeMesh.swift` |
| Shared packed vertex descriptor for all meshes | `Sources/Rendering/MeshVertexLayout.swift` |
| Scene objects, mapping, viewport setup, drawing | `Sources/Rendering/Renderer.swift` |
| Object identity, placement, model matrix, rigid frame | `Sources/Rendering/RenderObject.swift` |
| Camera state and movement | `Sources/Scene/Camera.swift` |
| Portal mapping, normal matrices, projection, translation, rotation, scale | `Sources/Scene/Transforms.swift` |
| Keyboard and mouse capture | `Sources/Input/KeyboardMetalView.swift` |
| Vertex transforms, lighting, unlit FOV color | `Sources/Shaders/Shaders.metal` |
| CPU uniform layout, kept in sync with Metal | `Sources/Rendering/ShaderUniforms.swift` |
| MTKView setup and renderer lifetime | `Sources/Views/MetalView.swift` |

The transform convention is `position * model * view * projection`, with +Z forward and Metal depth 0...1. Depth clears to 1 and compares with `.less`. Mesh attributes use buffer 0; uniforms use buffer 1 in both shader stages. `MeshVertexLayout` supplies the shared layout: position at byte 0, normal at byte 12, UV at byte 24, and a 32-byte stride.

Swift and Metal uniform names, order, and types match, including `lightPositionWorld` and the active camera's `eyeWorld`. With complete world models computed on the CPU, uniforms no longer need separate camera/portal mapping matrices. Their current stride is 304 bytes, including the padded normal matrix; the checks verify the offsets.

## Verify

Use an isolated build directory for this 3D project, separate from the sibling 2D experiment:

```sh
BUILD_DIR="$(mktemp -d /tmp/portal-demo-3d-check.XXXXXX)" ./Scripts/check.sh
git diff --check
```

The script builds the Debug app, compiles the files in `Tests/`, and attempts offscreen GPU rendering with Metal API validation enabled. A successful app build alone does not verify the rendered output. A Metal GPU and access to the Xcode toolchain are required for the full check.

Checks cover custom frustum corners and edges, invalid parameters, near/far projection depth, aspect scaling, placement pivots and order, forward/reverse portal transforms, inverse-transpose normals, and uniform offsets. Deterministic renderer fixtures check transformed solid and mapped objects against independent geometry and lighting calculations, including each viewport's world-space eye. Scene and outline rendering also run at square, wide, tall, and odd-width sizes. Invalid scenes test missing portals, duplicate IDs, and singular scales.

Input checks cover held keys, camera movement/look, consuming mouse deltas once, and native view/window lifecycle callbacks for Escape, focus loss, detachment, window close/reopen, reattachment, and SwiftUI dismantling. They inject inert cursor callbacks, so they can verify release balance without changing the user's cursor. Actual cursor visibility and mouse association after those interactions remain a separate manual macOS check; the automated checks do not prove those operating-system effects.

Keep generated products outside synced Desktop/Documents source directories to avoid signing metadata problems. Running from Xcode uses its normal DerivedData location.

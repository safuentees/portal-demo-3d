import MetalKit
import simd

/// Exercises the actual offscreen scene pass and its sampled right-hand preview.
enum TexturePassChecks {
    @MainActor
    static func run(view: MTKView, library: MTLLibrary, device: MTLDevice, queue: MTLCommandQueue) throws {
        let quad = try QuadMesh.make(device: device)
        // Equal rigid frames make the mapping identity, while unequal visual scales
        // keep a tiny entrance and an opaque exit that would otherwise hide the scene.
        let objects = [
            RenderObject(id: .entrance, mesh: quad,
                placement: ObjectPlacement(position: [0, 0, 2], scale: [0.01, 0.01, 1])),
            RenderObject(id: .exit, mesh: quad,
                placement: ObjectPlacement(position: [0, 0, 2], scale: [20, 20, 1])),
            RenderObject(id: .entrance_quad, mesh: quad,
                placement: ObjectPlacement(position: [0, 0, 1], scale: [20, 20, 1])),
            RenderObject(id: .exit_quad, mesh: quad,
                placement: ObjectPlacement(position: [0, 0, 2], scale: [20, 20, 1])),
            RenderObject(id: .sphere, mesh: quad,
                placement: ObjectPlacement(position: [-0.38, 0.48, 3], scale: [0.35, 0.28, 1], yaw: .pi)),
            RenderObject(id: .player, mesh: quad,
                placement: ObjectPlacement(position: [0.36, -0.38, 3], scale: [0.27, 0.45, 1], yaw: .pi)),
            // Draw the large background LAST: correct foreground colors require depth.
            RenderObject(id: .cube, mesh: quad,
                placement: ObjectPlacement(position: [0, 0, 5], scale: [20, 20, 1], yaw: .pi))
        ]
        let renderer = try Renderer(view: view, library: library, objects: objects, showsMappedPreview: true)
        var previousTargets: [PortalDirection: Renderer.RenderTargets] = [:]
        for (width, height) in [(512, 512), (800, 400), (400, 800), (801, 401), (512, 512)] {
            let frame = try SmokeTests.render(renderer, device: device, queue: queue, width: width, height: height)
            guard let color = renderer.entranceToExitTextures?.color, let depth = renderer.entranceToExitTextures?.depth else {
                throw SmokeTests.Failure(description: "The mapped scene did not allocate its render targets.")
            }
            let textureWidth = width / 2
            let targets = renderer.mappedTextures
            try SmokeTests.expect(targets.count == PortalDirection.allCases.count,
                                  "Each portal direction must have a complete target pair.")
            var allTextures: [MTLTexture] = []
            for direction in PortalDirection.allCases {
                guard let pair = targets[direction] else {
                    throw SmokeTests.Failure(description: "Missing targets for \(direction).")
                }
                try SmokeTests.expect(pair.color.width == textureWidth && pair.color.height == height
                    && pair.depth.width == textureWidth && pair.depth.height == height,
                    "Both directions' targets must match the source viewport's pixel dimensions.")
                try SmokeTests.expect(pair.color.pixelFormat == .bgra8Unorm && pair.depth.pixelFormat == .depth32Float
                    && pair.color.sampleCount == 1 && pair.depth.sampleCount == 1
                    && pair.color.storageMode == .private && pair.depth.storageMode == .private,
                    "Both directions must use private, single-sample color/depth targets.")
                try SmokeTests.expect(pair.color.usage == [.renderTarget, .shaderRead]
                    && pair.depth.usage == .renderTarget,
                    "Both directions' color targets must support sampling and depth targets rendering.")
                if let previous = previousTargets[direction] {
                    try SmokeTests.expect(pair.color !== previous.color && pair.depth !== previous.depth,
                        "A viewport size change must replace both directions' color and depth targets.")
                }
                allTextures += [pair.color, pair.depth]
            }
            try SmokeTests.expect(Set(allTextures.map { ObjectIdentifier($0) }).count == allTextures.count,
                                  "Portal directions must not share color or depth textures.")
            try SmokeTests.expect(color === targets[.entranceToExit]?.color
                && depth === targets[.entranceToExit]?.depth,
                "The entrance-to-exit accessor must refer to its direction's target pair.")
            let texturePixels = try read(color, device: device, queue: queue)
            guard let reverse = renderer.exitToEntranceTextures else {
                throw SmokeTests.Failure(description: "The reverse targets are missing.")
            }
            let reversePixels = try read(reverse.color, device: device, queue: queue)
            let reverseCenter = ((height / 2) * textureWidth + textureWidth / 2) * 4
            let slabColor = SmokeTests.lightingBytes(pointWorld: worldPoint(pixelX: textureWidth / 2,
                pixelY: height / 2, width: textureWidth, height: height, depth: 2), normalWorld: [0, 0, 1],
                eyeWorld: .zero, materialColor: SceneConfiguration.portalColor)
            try SmokeTests.expect((0..<4).allSatisfy { abs(Int(reversePixels[reverseCenter + $0]) - slabColor[$0]) <= 3 },
                                  "The reverse capture must retain its source exit slab even when an exit surface exists.")
            try checkMarker(texturePixels, width: textureWidth, height: height,
                position: [-0.38, 0.48, 3], material: SceneConfiguration.sceneObjectColor)
            try checkMarker(texturePixels, width: textureWidth, height: height,
                position: [0.36, -0.38, 3], material: SceneConfiguration.mappedPlayerColor)
            try checkPreview(frame, width: width, height: height, texture: texturePixels, textureWidth: textureWidth)

            // The source quad samples the corresponding screen pixel, not the
            // whole camera image squeezed into the quad's mesh UV rectangle.
            let sourceCenter = ((height / 2) * width + textureWidth / 2) * 4
            let sourceExpected = sample(texturePixels, width: textureWidth, height: height,
                uv: [(Float(textureWidth / 2) + 0.5) / Float(textureWidth),
                     (Float(height / 2) + 0.5) / Float(height)])
            try SmokeTests.expect((0..<4).allSatisfy { abs(Float(frame[sourceCenter + $0]) - sourceExpected[$0]) <= 2 },
                                  "The source quad must display the captured image without lighting it again.")

            renderer.mtkView(view, drawableSizeWillChange: CGSize(width: width, height: height))
            let second = try SmokeTests.render(renderer, device: device, queue: queue, width: width, height: height)
            try checkTargetReuse(renderer, expected: targets,
                                 reason: "Unchanged callbacks and frames must reuse all four textures.")
            try SmokeTests.expect(frame == second, "The mapped texture preview changed at rest.")
            previousTargets = targets
        }
        // A one-pixel split target produces an invalid zero-width source viewport.
        renderer.mtkView(view, drawableSizeWillChange: CGSize(width: 1, height: 64))
        try checkTargetReuse(renderer, expected: previousTargets,
                             reason: "An invalid resize must preserve every existing target.")
        try checkPreviewModes(view: view, library: library, device: device, queue: queue,
                              objects: objects + [RenderObject(id: .fov(.entranceToExit), mesh: quad,
                                // In front of the source quad, so its debug-only
                                // visibility can be checked independently of the capture.
                                placement: ObjectPlacement(position: [0, 0.12, 0.5], scale: [0.08, 0.04, 1])),
                                RenderObject(id: .fov(.exitToEntrance), mesh: quad,
                                    placement: ObjectPlacement(position: [0, -0.12, 0.5], scale: [0.08, 0.04, 1]))])
        try checkEntranceSurface(view: view, library: library, device: device, queue: queue, mesh: quad)
        try checkReverseCapture(view: view, library: library, device: device, queue: queue)
        print("PASS: mapped color/depth pass, excluded preview surfaces, orientation, sampling, resize, and resource reuse")
    }

    static func checkTargetReuse(
        _ renderer: Renderer, expected: [PortalDirection: Renderer.RenderTargets], reason: String
    ) throws {
        try SmokeTests.expect(renderer.mappedTextures.count == expected.count && expected.allSatisfy { direction, pair in
            guard let current = renderer.mappedTextures[direction] else { return false }
            return current.color === pair.color && current.depth === pair.depth
        }, reason)
    }

    @MainActor
    static func checkReverseCapture(
        view: MTKView, library: MTLLibrary, device: MTLDevice, queue: MTLCommandQueue
    ) throws {
        let slab = try CubeMesh.make(device: device)
        let mesh = try SmokeTests.makeFixtureQuad(device: device)
        let entrance = RenderObject(id: .entrance, mesh: slab,
            placement: ObjectPlacement(position: [0.2, -0.1, 3], scale: [6, 6, 0.2], yaw: 0.15, pitch: -0.08))
        let exit = RenderObject(id: .exit, mesh: slab,
            placement: ObjectPlacement(position: [8, 0.7, 5], scale: [3, 4, 0.1], yaw: 0.9, pitch: 0.2))
        let cameraLocal = Transforms.translation([0.4, -0.3, -3])
        let sourceWorld = cameraLocal * exit.rigidFrame
        // Construct the expected reverse eye directly in A's frame, independently of transferBA.
        let reverseWorld = cameraLocal * entrance.rigidFrame
        let landmarks = [
            RenderObject(id: .sphere, mesh: mesh,
                placement: ObjectPlacement(position: [-0.3, -0.3, 4.8], scale: [0.7, 0.65, 0.55], yaw: -0.35, pitch: 0.25)),
            RenderObject(id: .cube, mesh: mesh,
                placement: ObjectPlacement(position: [1.7, 0.6, 5.8], scale: [0.7, 0.65, 0.55], yaw: -0.35, pitch: 0.25))
        ]
        // Place both boundary IDs over the destination too: any missed capture
        // exclusion would hide these landmarks behind a full-size quad.
        let quad = try QuadMesh.make(device: device)
        let renderer = try Renderer(view: view, library: library,
            objects: [entrance, exit,
                RenderObject(id: .entrance_quad, mesh: quad, placement: entrance.placement),
                RenderObject(id: .entranceBoundary(0), mesh: quad, placement: entrance.placement),
                RenderObject(id: .exitBoundary(0), mesh: quad, placement: entrance.placement)] + landmarks,
            camera: Camera(viewMatrix: simd_inverse(sourceWorld)), showsMappedPreview: false)
        let width = 512, height = 384
        _ = try SmokeTests.render(renderer, device: device, queue: queue, width: width, height: height)
        guard let forward = renderer.entranceToExitTextures, let reverse = renderer.exitToEntranceTextures else {
            throw SmokeTests.Failure(description: "Both directed captures must exist after rendering.")
        }
        let pixels = try read(reverse.color, device: device, queue: queue)
        let forwardPixels = try read(forward.color, device: device, queue: queue)
        try SmokeTests.expect(pixels != forwardPixels, "Reverse capture must not duplicate the forward camera image.")
        let projection = Transforms.perspective(aspect: Float(width) / Float(height),
            fieldOfView: SceneConfiguration.fieldOfViewRadians,
            near: SceneConfiguration.nearPlane, far: SceneConfiguration.farPlane)
        let viewProjection = simd_inverse(reverseWorld) * projection
        let inverseViewProjection = simd_inverse(viewProjection)
        let eye = SmokeTests.xyz(SIMD4<Float>(0, 0, 0, 1) * reverseWorld)
        let forwardWorld = sourceWorld * simd_inverse(entrance.rigidFrame) * exit.rigidFrame
        let wrongEyes = [sourceWorld, forwardWorld].map { SmokeTests.xyz(SIMD4<Float>(0, 0, 0, 1) * $0) }
        var wrongEyeDifferences = [0, 0]
        for landmark in landmarks {
            let model = landmark.modelMatrix
            let plane = SmokeTests.xyz(SIMD4<Float>(0, 0, 0, 1) * model)
            let tangentA = SmokeTests.xyz(SIMD4<Float>(1, 0, 0.3, 0) * model)
            let tangentB = SmokeTests.xyz(SIMD4<Float>(0, 1, 0.2, 0) * model)
            let normal = simd_normalize(simd_cross(tangentB, tangentA))
            for localY: Float in [-0.4, 0, 0.4] {
                for localX: Float in [-0.4, 0, 0.4] {
                    let target = SIMD4<Float>(localX, localY, 0.3 * localX + 0.2 * localY, 1) * model
                    let clip = target * viewProjection
                    let x = Int(floor((clip.x / clip.w + 1) * 0.5 * Float(width)))
                    let y = Int(floor((1 - clip.y / clip.w) * 0.5 * Float(height)))
                    try SmokeTests.expect((0..<width).contains(x) && (0..<height).contains(y),
                                          "The reverse landmark sample left the viewport.")
                    let far = SIMD4<Float>((Float(x) + 0.5) / Float(width) * 2 - 1,
                        1 - (Float(y) + 0.5) / Float(height) * 2, 1, 1) * inverseViewProjection
                    let ray = SmokeTests.xyz(far / far.w) - eye
                    let point = eye + ray * (simd_dot(plane - eye, normal) / simd_dot(ray, normal))
                    let expected = SmokeTests.lightingBytes(pointWorld: point, normalWorld: normal,
                        eyeWorld: eye, materialColor: SceneConfiguration.sceneObjectColor)
                    let index = (y * width + x) * 4
                    try SmokeTests.expect((0..<4).allSatisfy { abs(Int(pixels[index + $0]) - expected[$0]) <= 3 },
                        "Reverse landmark placement/filtering/lighting failed at \(x),\(y): "
                        + "got \(Array(pixels[index..<(index + 4)])), expected \(expected).")
                    for (index, wrongEye) in wrongEyes.enumerated() {
                        let wrong = SmokeTests.lightingBytes(pointWorld: point, normalWorld: normal,
                            eyeWorld: wrongEye, materialColor: SceneConfiguration.sceneObjectColor)
                        wrongEyeDifferences[index] = max(wrongEyeDifferences[index],
                            zip(expected, wrong).map { abs($0.0 - $0.1) }.max() ?? 0)
                    }
                }
            }
        }
        try SmokeTests.expect(wrongEyeDifferences.allSatisfy { $0 > 6 },
                              "Reverse fixture must distinguish its lighting eye from both other cameras.")
        print("PASS: reverse capture, independent rotated frames, destination omission, and reverse-camera lighting")
    }

    @MainActor
    static func checkPreviewModes(
        view: MTKView, library: MTLLibrary, device: MTLDevice, queue: MTLCommandQueue, objects: [RenderObject]
    ) throws {
        let hidden = try Renderer(view: view, library: library, objects: objects, showsMappedPreview: false)
        let enabled = try Renderer(view: view, library: library, objects: objects, showsMappedPreview: true)
        let withoutFOV = try Renderer(view: view, library: library,
            objects: objects.filter { if case .fov = $0.id { return false }; return true }, showsMappedPreview: false)
        var previousColor: MTLTexture?
        var previousDepth: MTLTexture?
        for (width, height) in [(512, 512), (800, 400), (400, 800), (801, 401)] {
            // A full W-pixel view and the source half of a 2W-pixel split have
            // identical projection, FOV geometry, capture, and source rasterization.
            hidden.mtkView(view, drawableSizeWillChange: CGSize(width: width, height: height))
            enabled.mtkView(view, drawableSizeWillChange: CGSize(width: width * 2, height: height))
            guard let hiddenColor = hidden.entranceToExitTextures?.color, let hiddenDepth = hidden.entranceToExitTextures?.depth,
                  let enabledColor = enabled.entranceToExitTextures?.color, let enabledDepth = enabled.entranceToExitTextures?.depth else {
                throw SmokeTests.Failure(description: "Resize callbacks did not prepare both preview modes.")
            }
            try SmokeTests.expect([hiddenColor, hiddenDepth, enabledColor, enabledDepth].allSatisfy {
                $0.width == width && $0.height == height
            }, "Resize callbacks must size capture targets to each mode's source viewport.")
            if let previousColor, let previousDepth {
                try SmokeTests.expect(hiddenColor !== previousColor && hiddenDepth !== previousDepth,
                                      "Resizing the full view must replace both capture targets.")
            }
            let fullFrame = try SmokeTests.render(hidden, device: device, queue: queue, width: width, height: height)
            let splitFrame = try SmokeTests.render(enabled, device: device, queue: queue, width: width * 2, height: height)
            try SmokeTests.expect(hidden.entranceToExitTextures?.color === hiddenColor && hidden.entranceToExitTextures?.depth === hiddenDepth
                && enabled.entranceToExitTextures?.color === enabledColor && enabled.entranceToExitTextures?.depth === enabledDepth,
                "Encoding must reuse the dimensions prepared by each resize callback.")
            let fullCapture = try read(hiddenColor, device: device, queue: queue)
            let splitCapture = try read(enabledColor, device: device, queue: queue)
            try SmokeTests.expect(fullCapture == splitCapture,
                                  "Hiding the preview changed the mapped projection or captured scene.")
            _ = try SmokeTests.render(withoutFOV, device: device, queue: queue, width: width, height: height)
            for direction in PortalDirection.allCases {
                guard let full = hidden.mappedTextures[direction], let split = enabled.mappedTextures[direction],
                      let clean = withoutFOV.mappedTextures[direction] else {
                    throw SmokeTests.Failure(description: "The capture comparison did not allocate both directions.")
                }
                let capture = try read(full.color, device: device, queue: queue)
                let splitCapture = try read(split.color, device: device, queue: queue)
                let cleanCapture = try read(clean.color, device: device, queue: queue)
                try SmokeTests.expect(capture == splitCapture && capture == cleanCapture,
                    "Both FOVs must remain absent from both captures in either preview mode.")
            }
            for y in 0..<height {
                let fullStart = y * width * 4
                let splitStart = y * width * 8
                try SmokeTests.expect(fullFrame[fullStart..<(fullStart + width * 4)]
                    == splitFrame[splitStart..<(splitStart + width * 4)],
                    "The full-width scene differs from an equivalent split source view at row \(y).")
            }
            try checkPreview(splitFrame, width: width * 2, height: height, texture: fullCapture, textureWidth: width)
            for fov in [SceneConfiguration.entranceToExitFOVColor, SceneConfiguration.exitToEntranceFOVColor] {
                let fovBytes = [fov.z, fov.y, fov.x, fov.w].map { Int(($0 * 255).rounded()) }
                let count = stride(from: 0, to: fullFrame.count, by: 4).filter { index in
                    (0..<4).allSatisfy { abs(Int(fullFrame[index + $0]) - fovBytes[$0]) <= 1 }
                }.count
                try SmokeTests.expect(count > 20,
                    "Each directional FOV color must be visible in the source view.")
            }

            // Test the far right independently: it must remain scene geometry with
            // the entrance texture, rather than an empty strip or a preview panel.
            for y in [height / 4, height / 2, height * 3 / 4] {
                for x in [width / 2, width - 3, width - 1] {
                    let expected = sample(fullCapture, width: width, height: height,
                        uv: [(Float(x) + 0.5) / Float(width), (Float(y) + 0.5) / Float(height)])
                    let pixel = (y * width + x) * 4
                    try SmokeTests.expect((0..<4).allSatisfy { abs(Float(fullFrame[pixel + $0]) - expected[$0]) <= 2 },
                        "The hidden-preview source did not render its textured quad at \(x),\(y).")
                }
            }
            let repeated = try SmokeTests.render(hidden, device: device, queue: queue, width: width, height: height)
            try SmokeTests.expect(fullFrame == repeated && hidden.entranceToExitTextures?.color === hiddenColor
                && hidden.entranceToExitTextures?.depth === hiddenDepth, "The full view must stay stable and reuse its targets.")
            previousColor = hiddenColor
            previousDepth = hiddenDepth
        }
        hidden.mtkView(view, drawableSizeWillChange: CGSize(width: 1, height: 64))
        _ = try SmokeTests.render(hidden, device: device, queue: queue, width: 1, height: 64)
        guard let narrowColor = hidden.entranceToExitTextures?.color, let narrowDepth = hidden.entranceToExitTextures?.depth,
              let command = queue.makeCommandBuffer() else {
            throw SmokeTests.Failure(description: "The one-pixel full view did not allocate its targets.")
        }
        try SmokeTests.expect(narrowColor.width == 1 && narrowDepth.width == 1,
                              "A one-pixel full-width view must remain valid.")
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = narrowColor
        pass.depthAttachment.texture = narrowDepth
        try SmokeTests.expect(!enabled.encodeFrame(commandBuffer: command, renderPass: pass,
            drawableSize: CGSize(width: 1, height: 64)), "A one-pixel attachment cannot fit two preview viewports.")
        print("PASS: preview modes, screen-aligned sampling, source-only FOV, callback sizing, resizing, reuse, and minimum width")
    }

    @MainActor
    static func checkEntranceSurface(
        view: MTKView, library: MTLLibrary, device: MTLDevice, queue: MTLCommandQueue, mesh: MTKMesh
    ) throws {
        let portalMesh = try CubeMesh.make(device: device)
        let cameras = [matrix_identity_float4x4,
            Transforms.rotateY(-0.08) * Transforms.rotateX(0.04) * Transforms.translation([-0.2, 0.15, -0.2])]
        for (fixture, cameraWorld) in cameras.enumerated() {
            let placement = ObjectPlacement(position: [0, 0, 3], scale: [2, 2.4, 0.15],
                yaw: fixture == 0 ? 0 : 0.3, pitch: fixture == 0 ? 0 : -0.18)
            let surface = RenderObject(id: .entrance_quad, mesh: mesh, placement: placement)
            let foreground = RenderObject(id: .cube, mesh: mesh,
                placement: ObjectPlacement(position: [0.3, -0.25, 2], scale: [0.5, 0.6, 1], yaw: .pi))
            let background = RenderObject(id: .sphere, mesh: mesh,
                placement: ObjectPlacement(position: [0, 0, 5], scale: [8, 7, 1], yaw: .pi))
            let objects = [
                // The solid cube's front is nearer than the coincident surface.
                // Its removal from the source pass is required for the texture to show.
                RenderObject(id: .entrance, mesh: portalMesh, placement: placement),
                RenderObject(id: .exit, mesh: portalMesh,
                    placement: ObjectPlacement(position: [8, 0, 3], scale: [2, 2.4, 0.15])),
                // An asymmetric camera-relative mark makes incorrect UV mapping visible.
                RenderObject(id: .player, mesh: mesh,
                    placement: ObjectPlacement(position: [-0.6, 0.5, 4], scale: [0.7, 0.5, 1], yaw: .pi)),
                RenderObject(id: .fov(.entranceToExit), mesh: mesh,
                    placement: ObjectPlacement(position: [0.5, -0.4, 4.5], scale: [0.4, 0.8, 1])),
                foreground, surface, background
            ]
            let renderer = try Renderer(view: view, library: library, objects: objects,
                                        camera: Camera(viewMatrix: simd_inverse(cameraWorld)), showsMappedPreview: true)
            let width = fixture == 0 ? 800 : 801, height = 400
            let viewportWidth = width / 2
            let frame = try SmokeTests.render(renderer, device: device, queue: queue, width: width, height: height)
            guard let texture = renderer.entranceToExitTextures?.color else {
                throw SmokeTests.Failure(description: "The entrance surface has no camera texture.")
            }
            let texturePixels = try read(texture, device: device, queue: queue)
            try checkPreview(frame, width: width, height: height, texture: texturePixels, textureWidth: viewportWidth)
            let inverseModels = [surface, foreground, background].map { simd_inverse($0.modelMatrix) }
            let eyeWorld = SIMD4<Float>(0, 0, 0, 1) * cameraWorld
            let eyesLocal = inverseModels.map { eyeWorld * $0 }
            let slope = tan(SceneConfiguration.fieldOfViewRadians / 2)
            let clear = SceneConfiguration.backgroundColor
            let clearBytes = SIMD4<Float>(Float(clear.blue), Float(clear.green), Float(clear.red), Float(clear.alpha)) * 255
            var checked = [0, 0, 0, 0]
            var meshUVDifferences = 0
            for y in stride(from: 1, to: height - 1, by: 2) {
                for x in stride(from: 1, to: viewportWidth - 1, by: 2) {
                    let ndcX = (Float(x) + 0.5) / Float(viewportWidth) * 2 - 1
                    let ndcY = 1 - (Float(y) + 0.5) / Float(height) * 2
                    let rayWorld = SIMD4<Float>(ndcX * Float(viewportWidth) / Float(height) * slope, ndcY * slope, 1, 0)
                        * cameraWorld
                    var nearest: (surface: Int, distance: Float, local: SIMD4<Float>)?
                    var nearBoundary = false
                    for index in inverseModels.indices {
                        let direction = rayWorld * inverseModels[index]
                        if abs(direction.z) < 0.000001 { continue }
                        let distance = -eyesLocal[index].z / direction.z
                        let local = eyesLocal[index] + distance * direction
                        if distance <= 0 { continue }
                        // Exclude the one-pixel raster boundary; retain dense interior
                        // samples of the textured face, occluder, and surrounding scene.
                        if abs(local.x) < 0.51 && abs(local.y) < 0.51
                            && (abs(abs(local.x) - 0.5) < 0.01 || abs(abs(local.y) - 0.5) < 0.01) {
                            nearBoundary = true
                        }
                        if abs(local.x) < 0.5 && abs(local.y) < 0.5
                            && distance < (nearest?.distance ?? .infinity) {
                            nearest = (index, distance, local)
                        }
                    }
                    if nearBoundary { continue }
                    let expected: SIMD4<Float>
                    if let nearest {
                        checked[nearest.surface] += 1
                        if nearest.surface == 0 {
                            expected = sample(texturePixels, width: viewportWidth, height: height,
                                uv: [(Float(x) + 0.5) / Float(viewportWidth), (Float(y) + 0.5) / Float(height)])
                            let meshUVColor = sample(texturePixels, width: viewportWidth, height: height,
                                uv: [nearest.local.x + 0.5, 0.5 - nearest.local.y])
                            if (0..<3).contains(where: { abs(expected[$0] - meshUVColor[$0]) > 8 }) {
                                meshUVDifferences += 1
                            }
                        } else {
                            let point = SmokeTests.xyz(eyeWorld + nearest.distance * rayWorld)
                            let bytes = SmokeTests.lightingBytes(pointWorld: point, normalWorld: [0, 0, -1],
                                eyeWorld: SmokeTests.xyz(eyeWorld), materialColor: SceneConfiguration.sceneObjectColor)
                            expected = SIMD4(Float(bytes[0]), Float(bytes[1]), Float(bytes[2]), Float(bytes[3]))
                        }
                    } else {
                        checked[3] += 1
                        expected = clearBytes
                    }
                    let pixel = (y * width + x) * 4
                    try SmokeTests.expect((0..<4).allSatisfy { abs(Float(frame[pixel + $0]) - expected[$0]) <= 3 },
                        "Entrance surface fixture \(fixture), hit \(nearest?.surface ?? 3), pixel \(x),\(y): "
                        + "got \(Array(frame[pixel..<(pixel + 4)])), expected \(expected).")
                }
            }
            try SmokeTests.expect(checked[0] > 1000 && checked[1] > 100 && checked[2] > 1000,
                "The entrance fixture must exercise textured area, foreground occlusion, and outside/background depth.")
            try SmokeTests.expect(meshUVDifferences > 100,
                "The entrance fixture must distinguish screen-space sampling from squeezing the image into mesh UVs.")
        }
        print("PASS: entrance screen-space alignment, perspective placement, unlit sampling, bounds, and foreground/background depth")
    }

    /// Expected linear clamp-to-edge texture sampling, expressed in byte values.
    static func sample(_ pixels: [UInt8], width: Int, height: Int, uv: SIMD2<Float>) -> SIMD4<Float> {
        let texel = uv * SIMD2(Float(width), Float(height)) - SIMD2(repeating: 0.5)
        let left = Int(floor(texel.x)), top = Int(floor(texel.y))
        let fraction = texel - SIMD2(Float(left), Float(top))
        func at(_ x: Int, _ y: Int) -> SIMD4<Float> {
            let index = (min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)) * 4
            return SIMD4(Float(pixels[index]), Float(pixels[index + 1]), Float(pixels[index + 2]), Float(pixels[index + 3]))
        }
        let upper = at(left, top) * (1 - fraction.x) + at(left + 1, top) * fraction.x
        let lower = at(left, top + 1) * (1 - fraction.x) + at(left + 1, top + 1) * fraction.x
        return upper * (1 - fraction.y) + lower * fraction.y
    }

    static func worldPoint(pixelX: Int, pixelY: Int, width: Int, height: Int, depth: Float) -> SIMD3<Float> {
        let slope = tan(SceneConfiguration.fieldOfViewRadians / 2)
        let ndcX = (Float(pixelX) + 0.5) / Float(width) * 2 - 1
        let ndcY = 1 - (Float(pixelY) + 0.5) / Float(height) * 2
        return [ndcX * Float(width) / Float(height) * slope * depth, ndcY * slope * depth, depth]
    }

    static func checkMarker(
        _ pixels: [UInt8], width: Int, height: Int, position: SIMD3<Float>, material: SIMD4<Float>
    ) throws {
        let slope = tan(SceneConfiguration.fieldOfViewRadians / 2)
        let ndcX = position.x / (position.z * slope * Float(width) / Float(height))
        let ndcY = position.y / (position.z * slope)
        let x = Int(floor((ndcX + 1) * 0.5 * Float(width)))
        let y = Int(floor((1 - ndcY) * 0.5 * Float(height)))
        try SmokeTests.expect((0..<width).contains(x) && (0..<height).contains(y),
                              "The mapped texture marker left the test viewport.")
        let point = worldPoint(pixelX: x, pixelY: y, width: width, height: height, depth: position.z)
        let expected = SmokeTests.lightingBytes(pointWorld: point, normalWorld: [0, 0, -1],
                                              eyeWorld: .zero, materialColor: material)
        let index = (y * width + x) * 4
        try SmokeTests.expect((0..<4).allSatisfy { abs(Int(pixels[index + $0]) - expected[$0]) <= 3 },
            "Mapped marker color/depth failed at \(x),\(y): got \(Array(pixels[index..<(index + 4)])), expected \(expected).")
    }

    static func checkPreview(
        _ frame: [UInt8], width: Int, height: Int, texture: [UInt8], textureWidth: Int
    ) throws {
        let previewWidth = width - textureWidth
        for y in 0..<height {
            for x in 0..<previewWidth {
                // UV at the output pixel center; texel centers lie at n + 0.5.
                // Height is unchanged, so only odd-width previews interpolate in X.
                let texelX = (Float(x) + 0.5) * Float(textureWidth) / Float(previewWidth) - 0.5
                let left = Int(floor(texelX))
                let fraction = texelX - Float(left)
                let x0 = min(max(left, 0), textureWidth - 1)
                let x1 = min(max(left + 1, 0), textureWidth - 1)
                let source0 = (y * textureWidth + x0) * 4
                let source1 = (y * textureWidth + x1) * 4
                let destination = (y * width + textureWidth + x) * 4
                for channel in 0..<4 {
                    let expected = Float(texture[source0 + channel]) * (1 - fraction)
                        + Float(texture[source1 + channel]) * fraction
                    try SmokeTests.expect(abs(Float(frame[destination + channel]) - expected) <= 2,
                        "Texture preview orientation/filtering mismatch at \(x),\(y), channel \(channel).")
                }
            }
        }
    }

    static func read(_ texture: MTLTexture, device: MTLDevice, queue: MTLCommandQueue) throws -> [UInt8] {
        let bytesPerRow = ((texture.width * 4 + 255) / 256) * 256
        guard let buffer = device.makeBuffer(length: bytesPerRow * texture.height, options: .storageModeShared),
              let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
            throw SmokeTests.Failure(description: "Could not read the mapped texture.")
        }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
            destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: bytesPerRow * texture.height)
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        try SmokeTests.expect(command.status == .completed, "Mapped texture readback did not complete.")
        let bytes = buffer.contents().assumingMemoryBound(to: UInt8.self)
        var result: [UInt8] = []
        result.reserveCapacity(texture.width * texture.height * 4)
        for y in 0..<texture.height {
            result.append(contentsOf: UnsafeBufferPointer(start: bytes + y * bytesPerRow, count: texture.width * 4))
        }
        return result
    }
}

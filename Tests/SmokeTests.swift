import AppKit
import MetalKit
import simd

/// Runs the actual renderer against GPU textures without opening an app window.
@main
struct SmokeTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    @MainActor
    static func main() throws {
        try checkMath()
        try InputChecks.run()
        guard CommandLine.arguments.count == 2 else {
            throw Failure(description: "Pass the built default.metallib path.")
        }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw Failure(description: "A Metal GPU is required for the render checks.")
        }
        let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
        try checkFrustumMesh(device: device)
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        let renderer = try Renderer(view: view, library: library)
        try checkRendererFixtures(view: view, library: library, device: device, queue: queue)

        for (width, height) in [(512, 512), (800, 400), (400, 800), (801, 401)] {
            let first = try render(renderer, device: device, queue: queue, width: width, height: height)
            try checkScenePixels(first, width: width, height: height)
            let second = try render(renderer, device: device, queue: queue, width: width, height: height)
            try expect(first == second, "The resting scene changed between frames.")
            try checkFrustumRendering(device: device, queue: queue, library: library, width: width, height: height)
            print("PASS: \(width)x\(height) — both scene views, stable frame, exact frustum outline")
        }
        print("PASS: custom frustum parameters, portal mapping, camera movement, uniform layout, and GPU rendering")
    }

    static func checkMath() throws {
        let projection = Transforms.perspective(aspect: 1, fieldOfView: .pi / 2, near: 0.1, far: 100)
        for (z, expectedDepth): (Float, Float) in [(0.1, 0), (100, 1)] {
            let clip = SIMD4<Float>(0, 0, z, 1) * projection
            try expect(abs(clip.z / clip.w - expectedDepth) < 0.0001,
                       "Projection must map near/far to Metal depth 0/1.")
        }
        let translated = SIMD4<Float>(0, 0, 0, 1) * Transforms.translation([1, 2, 3])
        try expect(translated == SIMD4<Float>(1, 2, 3, 1), "Row-vector translation is incorrect.")

        var straight = Camera()
        var diagonal = Camera()
        straight.updateMovement(direction: [0, 0, 1], deltaTime: 0.05)
        diagonal.updateMovement(direction: [1, 0, 1], deltaTime: 0.05)
        try expect(abs(simd_length(straight.position) - simd_length(diagonal.position)) < 0.0001,
                   "Diagonal movement must not be faster.")
        let eye = SIMD4<Float>(straight.position.x, straight.position.y, straight.position.z, 1)
        try expect(simd_length((eye * straight.viewMatrix) - SIMD4<Float>(0, 0, 0, 1)) < 0.0001,
                   "The view transform must invert the camera position.")
        var paused = Camera()
        paused.updateMovement(direction: [0, 0, 1], deltaTime: 100)
        try expect(abs(paused.position.z - SceneConfiguration.cameraSpeed * 0.1) < 0.0001,
                   "A debugger pause must not cause a camera jump.")
        let placement = ObjectPlacement(position: [3, -2, 5], scale: [2, 0.7, 1.4], yaw: 0.6, pitch: -0.4)
        try expect(simd_length(SIMD4<Float>(0, 0, 0, 1) * placement.modelMatrix
            - SIMD4<Float>(placement.position, 1)) < 0.0001,
            "Scaling and rotation must preserve the local pivot before translation.")
        let localPoint = SIMD4<Float>(0.3, -0.4, 0.8, 1)
        let expectedPoint = localPoint * Transforms.scaling(placement.scale)
            * Transforms.rotateY(placement.yaw) * Transforms.rotateX(placement.pitch)
            * Transforms.translation(placement.position)
        try expect(simd_length(localPoint * placement.modelMatrix - expectedPoint) < 0.0001,
                   "Placement must apply scale, yaw, pitch, then translation in row-vector order.")
        let localTangentA = SIMD4<Float>(1, 0, 0.3, 0)
        let localTangentB = SIMD4<Float>(0, 1, 0.2, 0)
        let worldTangentA = localTangentA * placement.modelMatrix
        let worldTangentB = localTangentB * placement.modelMatrix
        let normal = SIMD3<Float>(0.3, 0.2, -1) * Transforms.normalMatrix(for: placement.modelMatrix)
        try expect(abs(simd_dot(normal, SIMD3(worldTangentA.x, worldTangentA.y, worldTangentA.z))) < 0.0001
            && abs(simd_dot(normal, SIMD3(worldTangentB.x, worldTangentB.y, worldTangentB.z))) < 0.0001,
            "Normals must stay perpendicular to nonuniformly scaled, rotated surface tangents.")
        let direction = SIMD4<Float>(0.2, 0.3, 0.8, 0)
        try expect(abs(simd_length(direction * placement.rigidFrame) - simd_length(direction)) < 0.0001,
                   "Portal rigid frames must exclude visual scale.")
        try expect(MemoryLayout<ShaderUniforms>.stride == 304, "Swift/Metal uniform stride changed.")
        let offsets: [(PartialKeyPath<ShaderUniforms>, Int)] = [
            (\.modelMatrix, 0), (\.viewMatrix, 64), (\.projectionMatrix, 128),
            (\.normalMatrix, 192), (\.color, 240), (\.lightColor, 256),
            (\.lightPositionWorld, 272), (\.eyeWorld, 288)
        ]
        for (field, offset) in offsets {
            try expect(MemoryLayout<ShaderUniforms>.offset(of: field) == offset,
                       "Swift/Metal uniform field offset changed: \(field).")
        }
    }

    static func checkFrustumMesh(device: MTLDevice) throws {
        let cameraWorld = Transforms.rotateZ(0.2) * Transforms.rotateY(-0.35)
            * Transforms.translation([-3, 2, -0.7])
        let camera = Camera(viewMatrix: simd_inverse(cameraWorld))
        let entrance = Transforms.rotateY(0.6) * Transforms.rotateX(-0.3)
            * Transforms.translation([2, -1, 4])
        let exit = Transforms.rotateZ(-0.4) * Transforms.rotateY(-0.8)
            * Transforms.translation([-5, 3, 7])
        let mapping = Transforms.portalMapping(entranceFrame: entrance, exitFrame: exit)
        let transfer = mapping.transferAB
        let reverse = mapping.transferBA
        let framePoint = SIMD4<Float>(0.4, -0.6, 0.8, 1)
        try expect(simd_length(framePoint * entrance * transfer - framePoint * exit) < 0.0001,
                   "The public portal mapping must preserve local coordinates between frames.")
        let mappedView = simd_inverse(camera.inverseViewMatrix * transfer)
        try expect(simd_length(SIMD4<Float>(camera.worldPosition, 1) * camera.viewMatrix
            - SIMD4<Float>(0, 0, 0, 1)) < 0.0001, "Camera world eye must include its base transform.")
        let direction = SIMD4<Float>(0.2, -0.6, 0.8, 0)
        try expect(abs(simd_length(direction * transfer) - simd_length(direction)) < 0.0001,
                   "A rigid portal mapping must preserve direction length.")
        try expect(simd_length(direction * transfer * reverse - direction) < 0.0001,
                   "Portal direction mapping must round-trip.")

        for (fov, aspect, near, far): (Float, Float, Float, Float) in [
            (.pi / 3, 1.7, 0.3, 17), (.pi / 2.4, 0.6, 1.2, 9)
        ] {
            let mesh = try ConeMesh.make(device: device, fieldOfView: fov, aspect: aspect, near: near, far: far)
            try expect(mesh.vertexCount == 8 && mesh.vertexBuffers.count == 1,
                       "The frustum must contain eight packed corners.")
            let layout = mesh.vertexDescriptor.layouts[0] as! MDLVertexBufferLayout
            try expect(layout.stride == 32, "Frustum vertices must match the 32-byte pipeline layout.")
            let buffer = mesh.vertexBuffers[0]
            let bytes = buffer.buffer.contents().advanced(by: buffer.offset)
            let unitAspectMesh = try ConeMesh.make(device: device, fieldOfView: fov, aspect: 1, near: near, far: far)
            let unitBuffer = unitAspectMesh.vertexBuffers[0]
            let unitBytes = unitBuffer.buffer.contents().advanced(by: unitBuffer.offset)
            let projection = Transforms.perspective(aspect: aspect, fieldOfView: fov, near: near, far: far)
            var cornerTags: [Int] = []
            for index in 0..<mesh.vertexCount {
                let vertex = bytes.advanced(by: index * layout.stride).assumingMemoryBound(to: Float.self)
                let point = SIMD4<Float>(vertex[0], vertex[1], vertex[2], 1)
                let unitVertex = unitBytes.advanced(by: index * layout.stride).assumingMemoryBound(to: Float.self)
                let resizedPoint = SIMD4<Float>(unitVertex[0], unitVertex[1], unitVertex[2], 1)
                    * Transforms.scaling([aspect, 1, 1])
                try expect(simd_length(resizedPoint - point) < 0.0001,
                           "Resizing by X aspect scale must match a mesh built for that aspect.")
                let isNear = abs(point.z - near) < 0.0001
                try expect(isNear || abs(point.z - far) < 0.0001, "A corner missed its requested near/far plane.")
                let clip = point * projection
                let ndc = clip / clip.w
                try expect(abs(abs(ndc.x) - 1) < 0.0001 && abs(abs(ndc.y) - 1) < 0.0001,
                           "A frustum corner missed the projection's field-of-view edges.")
                try expect(abs(ndc.z - (isNear ? 0 : 1)) < 0.0001, "Frustum depth must reach Metal NDC 0/1.")
                cornerTags.append((point.x > 0 ? 1 : 0) | (point.y > 0 ? 2 : 0) | (isNear ? 0 : 4))

                let pointWorld = point * camera.inverseViewMatrix
                let mappedClip = pointWorld * transfer * mappedView * projection
                try expect(simd_length(mappedClip / mappedClip.w - ndc) < 0.0002,
                           "The mapped FOV and mapped camera must produce identical projected corners.")
                try expect(simd_length(pointWorld * transfer * reverse - pointWorld) < 0.0002,
                           "Portal position mapping must round-trip, including pitched and rolled frames.")
            }
            try expect(Set(cornerTags).count == 8, "The frustum must include every near/far corner exactly once.")
            try expect(mesh.submeshes.count == 1, "The frustum must use one edge submesh.")
            let edges = mesh.submeshes[0]
            try expect(edges.primitiveType == .line && edges.indexType == .uint16 && edges.indexCount == 24,
                       "The frustum must have twelve line edges.")
            let indices = edges.indexBuffer.buffer.contents().advanced(by: edges.indexBuffer.offset)
                .assumingMemoryBound(to: UInt16.self)
            var uniqueEdges = Set<Int>()
            for index in stride(from: 0, to: edges.indexCount, by: 2) {
                let a = Int(indices[index]), b = Int(indices[index + 1])
                try expect(a < mesh.vertexCount && b < mesh.vertexCount, "Frustum edge index is out of bounds.")
                try expect([1, 2, 4].contains(cornerTags[a] ^ cornerTags[b]),
                           "The outline must contain physical edges, without face diagonals.")
                uniqueEdges.insert(min(a, b) * mesh.vertexCount + max(a, b))
            }
            try expect(uniqueEdges.count == 12, "The frustum contains duplicate or missing edges.")
        }

        let invalid: [(Float, Float, Float, Float)] = [
            (0, 1, 0.1, 10), (.pi, 1, 0.1, 10), (.nan, 1, 0.1, 10),
            (1, 0, 0.1, 10), (1, -1, 0.1, 10), (1, .infinity, 0.1, 10),
            (1, 1, 0, 10), (1, 1, -1, 10), (1, 1, 2, 2),
            (1, 1, 3, 2), (1, 1, .nan, 10), (1, 1, 0.1, .infinity)
        ]
        for (fov, aspect, near, far) in invalid {
            var rejected = false
            do {
                _ = try ConeMesh.make(device: device, fieldOfView: fov, aspect: aspect, near: near, far: far)
            } catch {
                rejected = true
            }
            try expect(rejected, "Invalid frustum parameters were accepted: \(fov), \(aspect), \(near), \(far).")
        }
    }

    @MainActor
    static func checkRendererFixtures(
        view: MTKView, library: MTLLibrary, device: MTLDevice, queue: MTLCommandQueue
    ) throws {
        let mesh = try makeFixtureQuad(device: device)
        let cameraWorld = Transforms.rotateY(-0.08) * Transforms.rotateX(0.04)
            * Transforms.translation([0.4, -0.3, -1])
        let camera = Camera(viewMatrix: simd_inverse(cameraWorld))
        let mappingYaw: Float = 0.15
        let expectedTransfer = Transforms.rotateY(mappingYaw) * Transforms.translation([1.5, 0.2, 0])
        let entrance = RenderObject(id: .entrance, mesh: mesh,
            placement: ObjectPlacement(position: [0, 0, -20], scale: [0.1, 0.2, 0.3]))
        let exitPoint = SIMD4<Float>(0, 0, -20, 1) * expectedTransfer
        let exit = RenderObject(id: .exit, mesh: mesh,
            placement: ObjectPlacement(position: xyz(exitPoint), scale: [0.3, 0.1, 0.2], yaw: mappingYaw))
        let placement = ObjectPlacement(position: [0.4, -0.2, 4], scale: [2.2, 1.7, 0.55], yaw: -0.12, pitch: 0.1)
        let sphere = RenderObject(id: .sphere, mesh: mesh, placement: placement)
        let invalidScenes = [
            [sphere], [entrance, exit, sphere, sphere],
            [entrance, exit, RenderObject(id: .sphere, mesh: mesh,
                placement: ObjectPlacement(scale: [1, 0, 1]))]
        ]
        for objects in invalidScenes {
            var rejected = false
            do {
                _ = try Renderer(view: view, library: library, objects: objects, camera: camera)
            } catch {
                rejected = true
            }
            try expect(rejected, "Renderer accepted missing portals, duplicate IDs, or a singular placement.")
        }

        let width = 960, height = 320, viewportWidth = width / 2
        let projection = Transforms.perspective(aspect: Float(viewportWidth) / Float(height),
            fieldOfView: SceneConfiguration.fieldOfViewRadians,
            near: SceneConfiguration.nearPlane, far: SceneConfiguration.farPlane)
        let cameraWorlds = [cameraWorld, cameraWorld * expectedTransfer]
        // This clipped draw still selects the unlit pipeline. The following
        // sphere/player must explicitly restore the lit pipeline.
        let outline = RenderObject(id: .fov, mesh: mesh,
            placement: ObjectPlacement(position: [0, 0, -100]))
        for id: ObjectID in [.sphere, .player] {
            let object = RenderObject(id: id, mesh: mesh, placement: placement)
            let renderer = try Renderer(view: view, library: library,
                objects: [entrance, exit, outline, object], camera: camera)
            let pixels = try render(renderer, device: device, queue: queue, width: width, height: height)
            let finalModel = id == .player ? placement.modelMatrix * cameraWorld * expectedTransfer : placement.modelMatrix
            let planePoint = xyz(SIMD4<Float>(0, 0, 0, 1) * finalModel)
            let tangentA = xyz(SIMD4<Float>(1, 0, 0.3, 0) * finalModel)
            let tangentB = xyz(SIMD4<Float>(0, 1, 0.2, 0) * finalModel)
            // Derive the expected normal geometrically, independently of normalMatrix().
            let normalWorld = simd_normalize(simd_cross(tangentB, tangentA))
            var wrongEyeDifference = 0
            var projectedCenters: [SIMD2<Float>] = []
            for viewport in 0..<2 {
                let viewMatrix = simd_inverse(cameraWorlds[viewport])
                let inverseViewProjection = simd_inverse(viewMatrix * projection)
                let eyeWorld = xyz(SIMD4<Float>(0, 0, 0, 1) * cameraWorlds[viewport])
                let centerClip = SIMD4<Float>(planePoint, 1) * viewMatrix * projection
                projectedCenters.append(SIMD2(centerClip.x, centerClip.y) / centerClip.w)
                for localY: Float in [-0.4, 0, 0.4] {
                    for localX: Float in [-0.4, 0, 0.4] {
                        let targetWorld = SIMD4<Float>(localX, localY, 0.3 * localX + 0.2 * localY, 1) * finalModel
                        let clip = targetWorld * viewMatrix * projection
                        let ndc = clip / clip.w
                        let pixelX = Int(floor((ndc.x + 1) * 0.5 * Float(viewportWidth)))
                        let pixelY = Int(floor((1 - ndc.y) * 0.5 * Float(height)))
                        try expect((0..<viewportWidth).contains(pixelX) && (0..<height).contains(pixelY),
                                   "The deterministic lighting sample left its viewport.")
                        let sampleX = (Float(pixelX) + 0.5) / Float(viewportWidth) * 2 - 1
                        let sampleY = 1 - (Float(pixelY) + 0.5) / Float(height) * 2
                        let nearClip = SIMD4<Float>(sampleX, sampleY, 0, 1) * inverseViewProjection
                        let farClip = SIMD4<Float>(sampleX, sampleY, 1, 1) * inverseViewProjection
                        let rayStart = xyz(nearClip / nearClip.w)
                        let rayDirection = xyz(farClip / farClip.w) - rayStart
                        let distance = simd_dot(planePoint - rayStart, normalWorld) / simd_dot(rayDirection, normalWorld)
                        let pointWorld = rayStart + rayDirection * distance
                        let expected = lightingBytes(pointWorld: pointWorld, normalWorld: normalWorld, eyeWorld: eyeWorld)
                        let index = (pixelY * width + viewport * viewportWidth + pixelX) * 4
                        try expect((0..<4).allSatisfy { abs(Int(pixels[index + $0]) - expected[$0]) <= 3 },
                            "Renderer \(id) lighting/placement mismatch in viewport \(viewport) at \(pixelX),\(pixelY): "
                            + "got \(Array(pixels[index..<(index + 4)])), expected \(expected).")
                        if viewport == 1 {
                            let wrongEye = xyz(SIMD4<Float>(0, 0, 0, 1) * cameraWorld)
                            let wrong = lightingBytes(pointWorld: pointWorld, normalWorld: normalWorld, eyeWorld: wrongEye)
                            wrongEyeDifference = max(wrongEyeDifference, zip(expected, wrong).map { abs($0.0 - $0.1) }.max() ?? 0)
                        }
                    }
                }
            }
            try expect(simd_length(projectedCenters[0] - projectedCenters[1]) > 0.1,
                       "The lighting fixture must distinguish the source and mapped camera views.")
            if id == .sphere {
                try expect(wrongEyeDifference > 6, "The fixture must expose using the wrong camera eye for specular lighting.")
            }
        }
        print("PASS: actual renderer placement, mapped player, active camera lighting, and transformed normals")
    }

    static func makeFixtureQuad(device: MTLDevice) throws -> MTKMesh {
        let normal = simd_normalize(SIMD3<Float>(0.3, 0.2, -1))
        var vertices: [Float] = []
        for corner: SIMD2<Float> in [[-1, -1], [1, -1], [1, 1], [-1, 1]] {
            vertices += [corner.x, corner.y, 0.3 * corner.x + 0.2 * corner.y,
                         normal.x, normal.y, normal.z, 0, 0]
        }
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        let allocator = MTKMeshBufferAllocator(device: device)
        let vertexBuffer = allocator.newBuffer(with: vertices.withUnsafeBytes { Data($0) }, type: .vertex)
        let indexBuffer = allocator.newBuffer(with: indices.withUnsafeBytes { Data($0) }, type: .index)
        let submesh = MDLSubmesh(indexBuffer: indexBuffer, indexCount: indices.count,
            indexType: .uInt16, geometryType: .triangles, material: nil)
        let model = MDLMesh(vertexBuffer: vertexBuffer, vertexCount: 4,
            descriptor: MeshVertexLayout.makeDescriptor(), submeshes: [submesh])
        return try MTKMesh(mesh: model, device: device)
    }

    static func xyz(_ value: SIMD4<Float>) -> SIMD3<Float> {
        SIMD3(value.x, value.y, value.z)
    }

    static func lightingBytes(pointWorld: SIMD3<Float>, normalWorld: SIMD3<Float>, eyeWorld: SIMD3<Float>) -> [Int] {
        let lightDirection = simd_normalize(xyz(SceneConfiguration.lightPositionWorld) - pointWorld)
        let viewDirection = simd_normalize(eyeWorld - pointWorld)
        let halfDirection = simd_normalize(lightDirection + viewDirection)
        let diffuse = max(simd_dot(normalWorld, lightDirection), 0)
        let specular: Float = diffuse > 0 ? 0.12 * pow(max(simd_dot(normalWorld, halfDirection), 0), 32) : 0
        let color = (0.35 + diffuse) * xyz(SceneConfiguration.lightColor) * xyz(SceneConfiguration.sceneColor)
            + specular * xyz(SceneConfiguration.lightColor)
        return [color.z, color.y, color.x, SceneConfiguration.sceneColor.w]
            .map { Int((min(max($0, 0), 1) * 255).rounded()) }
    }

    static func render(
        _ renderer: Renderer, device: MTLDevice, queue: MTLCommandQueue, width: Int, height: Int
    ) throws -> [UInt8] {
        try render(device: device, queue: queue, width: width, height: height,
                   clearColor: SceneConfiguration.backgroundColor) { command, pass in
            try expect(renderer.encodeFrame(
                commandBuffer: command, renderPass: pass, drawableSize: CGSize(width: width, height: height)
            ), "The renderer did not encode a frame.")
        }
    }

    static func render(
        device: MTLDevice, queue: MTLCommandQueue, width: Int, height: Int, clearColor: MTLClearColor,
        encode: (MTLCommandBuffer, MTLRenderPassDescriptor) throws -> Void
    ) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        guard let color = device.makeTexture(descriptor: descriptor) else {
            throw Failure(description: "Could not allocate the color target.")
        }
        descriptor.pixelFormat = .depth32Float
        guard let depth = device.makeTexture(descriptor: descriptor) else {
            throw Failure(description: "Could not allocate the depth target.")
        }
        let bytesPerRow = ((width * 4 + 255) / 256) * 256
        guard let readback = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
              let command = queue.makeCommandBuffer() else {
            throw Failure(description: "Could not allocate the readback buffer or command buffer.")
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = clearColor
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        try encode(command, pass)
        guard let blit = command.makeBlitCommandEncoder() else {
            throw Failure(description: "Could not create the readback encoder.")
        }
        blit.copy(
            from: color, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: readback, destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: bytesPerRow * height
        )
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        try expect(command.status == .completed, "GPU work did not complete.")

        let bytes = readback.contents().assumingMemoryBound(to: UInt8.self)
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height {
            pixels.append(contentsOf: UnsafeBufferPointer(start: bytes + y * bytesPerRow, count: width * 4))
        }
        return pixels
    }

    static func checkScenePixels(_ pixels: [UInt8], width: Int, height: Int) throws {
        let background = SceneConfiguration.backgroundColor
        let clear = [background.blue, background.green, background.red, background.alpha]
            .map { Int(($0 * 255).rounded()) }
        for viewport in 0..<2 {
            var count = 0
            for y in 0..<height {
                for x in (viewport * width / 2)..<((viewport + 1) * width / 2) {
                    let index = (y * width + x) * 4
                    try expect(pixels[index + 3] == 255, "The opaque scene produced invalid alpha.")
                    if (0..<3).contains(where: { abs(Int(pixels[index + $0]) - clear[$0]) > 1 }) {
                        count += 1
                    }
                }
            }
            try expect(count > width * height / 1000, "Scene geometry is missing from viewport \(viewport).")
        }
    }

    /// An isolated fixture gives the actual GPU buffers and shaders a known silhouette.
    static func checkFrustumRendering(
        device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary, width: Int, height: Int
    ) throws {
        let viewportWidths = [width / 2, width - width / 2]
        let fieldOfView: Float = .pi / 3
        let meshes = try viewportWidths.map { viewportWidth in
            try ConeMesh.make(device: device, fieldOfView: fieldOfView,
                aspect: Float(viewportWidth) / Float(height), near: 0.35, far: 7)
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "scene_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "fov_fragment")
        descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(meshes[0].vertexDescriptor)
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw Failure(description: "Could not create the frustum fixture's depth state.")
        }
        let colors: [SIMD4<Float>] = [[0.2, 0.9, 0.35, 1], [1, 0.4, 0.1, 1]]
        let clear = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        let pixels = try render(device: device, queue: queue, width: width, height: height,
                                clearColor: clear) { command, pass in
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
                throw Failure(description: "Could not encode the frustum fixture.")
            }
            defer { encoder.endEncoding() }
            encoder.setRenderPipelineState(pipeline)
            encoder.setDepthStencilState(depth)
            for viewport in 0..<2 {
                let viewportWidth = viewportWidths[viewport]
                let originX = viewport == 0 ? 0 : viewportWidths[0]
                let mesh = meshes[viewport]
                let buffer = mesh.vertexBuffers[0]
                encoder.setVertexBuffer(buffer.buffer, offset: buffer.offset, index: 0)
                // Doubling the projection's half-height puts the outline at NDC +/-0.5.
                let projection = Transforms.perspective(aspect: Float(viewportWidth) / Float(height),
                    fieldOfView: 2 * atan(2 * tan(fieldOfView / 2)), near: 0.1, far: 10)
                encoder.setViewport(MTLViewport(originX: Double(originX), originY: 0,
                    width: Double(viewportWidth), height: Double(height), znear: 0, zfar: 1))
                encoder.setScissorRect(MTLScissorRect(x: originX, y: 0,
                    width: viewportWidth, height: height))
                var uniforms = ShaderUniforms(
                    modelMatrix: matrix_identity_float4x4, viewMatrix: matrix_identity_float4x4,
                    projectionMatrix: projection, normalMatrix: matrix_identity_float3x3,
                    color: colors[viewport], lightColor: SIMD4(repeating: 1),
                    lightPositionWorld: [0, 0, 0, 1], eyeWorld: [0, 0, 0, 1])
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 1)
                for submesh in mesh.submeshes {
                    encoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount,
                        indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer,
                        indexBufferOffset: submesh.indexBuffer.offset)
                }
            }
        }
        for viewport in 0..<2 {
            let viewportWidth = viewportWidths[viewport]
            let originX = viewport == 0 ? 0 : viewportWidths[0]
            let color = colors[viewport]
            let expected = [color.z, color.y, color.x, color.w].map { Int(($0 * 255).rounded()) }
            var minX = viewportWidth, minY = height, maxX = -1, maxY = -1, count = 0
            for y in 0..<height {
                for x in 0..<viewportWidth {
                    let index = (y * width + originX + x) * 4
                    let isClear = (0..<3).allSatisfy { pixels[index + $0] == 0 }
                    if isClear { continue }
                    try expect((0..<4).allSatisfy { abs(Int(pixels[index + $0]) - expected[$0]) <= 1 },
                               "Unexpected frustum color or viewport spill at \(x),\(y).")
                    try expect(abs(Float(x) - Float(viewportWidth) * 0.25) <= 2
                        || abs(Float(x) - Float(viewportWidth) * 0.75) <= 2
                        || abs(Float(y) - Float(height) * 0.25) <= 2
                        || abs(Float(y) - Float(height) * 0.75) <= 2,
                        "The frustum outline contains an unexpected interior edge or filled face.")
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                    count += 1
                }
            }
            try expect(abs(Float(minX) - Float(viewportWidth) * 0.25) <= 2
                && abs(Float(maxX) - Float(viewportWidth) * 0.75) <= 2
                && abs(Float(minY) - Float(height) * 0.25) <= 2
                && abs(Float(maxY) - Float(height) * 0.75) <= 2,
                "The frustum outline does not match viewport \(viewport)'s projected bounds.")
            try expect(Float(count) > Float(viewportWidth + height) * 0.9
                && Float(count) < Float(viewportWidth + height) * 1.2,
                "The frustum outline has missing edges or unexpected coverage.")
        }
    }
}

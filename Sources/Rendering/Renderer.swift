import MetalKit
import QuartzCore
import simd

final class Renderer: NSObject, MTKViewDelegate {
    private enum SetupError: LocalizedError {
        case missingDevice, missingCommandQueue, missingLibrary
        case missingShaders, invalidVertexDescriptor, missingDepthState
        case duplicateObjectID, missingPortals, invalidPlacement

        var errorDescription: String? {
            switch self {
            case .missingDevice: return "No Metal device is available."
            case .missingCommandQueue: return "Metal could not create a command queue."
            case .missingLibrary: return "default.metallib is missing. Check Shaders.metal target membership."
            case .missingShaders: return "A scene vertex or fragment function is missing."
            case .invalidVertexDescriptor: return "The mesh vertex layout could not be converted to Metal."
            case .missingDepthState: return "Metal could not create the depth state."
            case .duplicateObjectID: return "Scene object IDs must be unique."
            case .missingPortals: return "The scene needs an entrance and an exit."
            case .invalidPlacement: return "Object placements must be finite with nonzero, invertible scale."
            }
        }
    }

    private let commandQueue: MTLCommandQueue
    private let objects: [RenderObject]
    private let pipelineState: MTLRenderPipelineState
    private let fovPipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let portalMapping: PortalMapping
    private var camera: Camera

    private var lastFrameTime: CFTimeInterval?

    // Supplied resources/scene/camera let smoke checks use deterministic fixtures.
    init(
        view: MTKView,
        library suppliedLibrary: MTLLibrary? = nil,
        objects suppliedObjects: [RenderObject]? = nil,
        camera: Camera = Camera()
    ) throws {
        guard let device = view.device else { throw SetupError.missingDevice }
        guard let queue = device.makeCommandQueue() else { throw SetupError.missingCommandQueue }
        commandQueue = queue
        self.camera = camera

        if let suppliedObjects {
            objects = suppliedObjects
        } else {
            let cubeMesh = try CubeMesh.make(device: device)
            // Build once at aspect 1; resize by scaling camera-local X, never GPU buffers.
            let coneMesh = try ConeMesh.make(
                device: device, fieldOfView: SceneConfiguration.fieldOfViewRadians,
                aspect: 1, near: SceneConfiguration.nearPlane, far: SceneConfiguration.farPlane
            )
            objects = [
                RenderObject(id: .entrance, mesh: cubeMesh, placement: SceneConfiguration.entrancePlacement),
                RenderObject(id: .exit, mesh: cubeMesh, placement: SceneConfiguration.exitPlacement),
                RenderObject(id: .player, mesh: cubeMesh, placement: SceneConfiguration.playerPlacement),
                RenderObject(id: .fov, mesh: coneMesh)
            ]
        }
        guard Set(objects.map(\.id)).count == objects.count else { throw SetupError.duplicateObjectID }
        guard objects.allSatisfy({
            $0.placement.isValid && simd_determinant($0.modelMatrix).isFinite
                && simd_determinant($0.modelMatrix) != 0
        }) else { throw SetupError.invalidPlacement }
        // Resolve required objects before creating any render encoder. The scene is immutable.
        guard let entrance = objects.first(where: { $0.id == .entrance }),
              let exit = objects.first(where: { $0.id == .exit }) else { throw SetupError.missingPortals }
        portalMapping = Transforms.portalMapping(entranceFrame: entrance.rigidFrame, exitFrame: exit.rigidFrame)

        // Xcode compiles Sources/Shaders/Shaders.metal into default.metallib.
        guard let library = suppliedLibrary ?? device.makeDefaultLibrary() else {
            throw SetupError.missingLibrary
        }
        guard let vertex = library.makeFunction(name: "scene_vertex"),
              let fragment = library.makeFunction(name: "lit_fragment"),
              let fovFragment = library.makeFunction(name: "fov_fragment") else {
            throw SetupError.missingShaders
        }

        guard let vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(MeshVertexLayout.makeDescriptor()) else {
            throw SetupError.invalidVertexDescriptor
        }

        vertexDescriptor.layouts[0].stepFunction = .perVertex
        vertexDescriptor.layouts[0].stepRate = 1

        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.label = "Lit scene"
        pipeline.vertexFunction = vertex
        pipeline.fragmentFunction = fragment
        pipeline.vertexDescriptor = vertexDescriptor
        pipeline.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipeline.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipeline.rasterSampleCount = view.sampleCount
        pipelineState = try device.makeRenderPipelineState(descriptor: pipeline)

        pipeline.label = "Mapped FOV outline"
        pipeline.fragmentFunction = fovFragment
        fovPipelineState = try device.makeRenderPipelineState(descriptor: pipeline)

        let depth = MTLDepthStencilDescriptor()
        depth.label = "Depth test"
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor: depth) else {
            throw SetupError.missingDepthState
        }
        depthState = state
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // The projection is rebuilt using drawableSize every frame.
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let deltaTime = Float(now - (lastFrameTime ?? now))
        lastFrameTime = now

        if let keyboardView = view as? KeyboardMetalView {
            let movementDirection = keyboardView.movementDirection
            let mouseDelta = keyboardView.consumeMouseDelta()
            camera.updateMovement(direction: movementDirection, deltaTime: deltaTime)
            camera.updateDirection(mouseDelta)
        }

        guard view.drawableSize.width > 0, view.drawableSize.height > 0,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        commandBuffer.label = "Portal scene frame"
        guard encodeFrame(
            commandBuffer: commandBuffer,
            renderPass: pass,
            drawableSize: view.drawableSize
        ) else { return }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Encode the scene into a view drawable or offscreen texture.
    /// drawableSize is the FULL attachment size in pixels, not one viewport's size.
    @discardableResult
    func encodeFrame(
        commandBuffer: MTLCommandBuffer,
        renderPass: MTLRenderPassDescriptor,
        drawableSize: CGSize
    ) -> Bool {
        guard drawableSize.width.isFinite, drawableSize.height.isFinite,
              drawableSize.width >= 2, drawableSize.height >= 1,
              let target = renderPass.colorAttachments[0].texture,
              drawableSize.width == CGFloat(target.width),
              drawableSize.height == CGFloat(target.height),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            return false
        }
        defer { encoder.endEncoding() }

        let leftWidth = floor(drawableSize.width / 2)
        let rightWidth = drawableSize.width - leftWidth
        let sourceAspect = Float(leftWidth / drawableSize.height)
        let viewports = [MTLViewport(
            originX: 0,
            originY: 0,
            width: leftWidth,
            height: drawableSize.height,
            znear: 0,
            zfar: 1
        ), MTLViewport(
            originX: leftWidth,
            originY: 0,
            width: rightWidth,
            height: drawableSize.height,
            znear: 0,
            zfar: 1
        )]

        let sourceCameraWorld = camera.inverseViewMatrix
        let mappedCameraWorld = sourceCameraWorld * portalMapping.transferAB
        let mappedViewMatrix = simd_inverse(mappedCameraWorld)

        // Every draw gets one complete local-to-world model. Both previews observe
        // these same world objects; no second mapping is performed in the shader.
        let worldModels = objects.map { object -> simd_float4x4 in
            switch object.id {
            case .fov:
                return Transforms.scaling([sourceAspect, 1, 1]) * object.modelMatrix
                    * sourceCameraWorld * portalMapping.transferAB
            case .player:
                return object.modelMatrix * sourceCameraWorld * portalMapping.transferAB
            default:
                return object.modelMatrix
            }
        }
        let normalMatrices = worldModels.map { Transforms.normalMatrix(for: $0) }
        encoder.setDepthStencilState(depthState)

        for i in viewports.indices {
            let viewport = viewports[i]
            encoder.setViewport(viewport)
            encoder.setScissorRect(MTLScissorRect(
                x: Int(viewport.originX), y: 0,
                width: Int(viewport.width), height: Int(viewport.height)
            ))

            // Viewport 0: normal camera
            // Viewport 1: mapped-camera preview (does not move the player).
            let activeViewMatrix: simd_float4x4
            let activeCameraWorld: simd_float4x4

            if i == 0 {
                activeViewMatrix = camera.viewMatrix
                activeCameraWorld = sourceCameraWorld
            } else {
                activeViewMatrix = mappedViewMatrix
                activeCameraWorld = mappedCameraWorld
            }

            let cameraPoint =
                SIMD4<Float>(0, 0, 0, 1)
                * activeCameraWorld

            let eyeWorld = SIMD4<Float>(
                cameraPoint.x / cameraPoint.w,
                cameraPoint.y / cameraPoint.w,
                cameraPoint.z / cameraPoint.w,
                1
            )

            let projectionMatrix = Transforms.perspective(
                aspect: Float(viewport.width / viewport.height),
                fieldOfView: SceneConfiguration.fieldOfViewRadians,
                near: SceneConfiguration.nearPlane,
                far: SceneConfiguration.farPlane
            )

            for (objectIndex, object) in objects.enumerated() {
                // Explicit for EVERY object, including spheres after an FOV draw.
                encoder.setRenderPipelineState(object.id == .fov ? fovPipelineState : pipelineState)
                let color: SIMD4<Float>
                switch object.id {
                case .entrance, .exit: color = SceneConfiguration.portalColor
                case .player: color = SceneConfiguration.mappedPlayerColor
                case .fov: color = SceneConfiguration.mappedFOVColor
                case .sphere, .cube: color = SceneConfiguration.sceneObjectColor
                }
                var uniforms = ShaderUniforms(
                    modelMatrix: worldModels[objectIndex],
                    viewMatrix: activeViewMatrix,
                    projectionMatrix: projectionMatrix,
                    normalMatrix: normalMatrices[objectIndex],
                    color: color,
                    lightColor: SceneConfiguration.lightColor,
                    lightPositionWorld: SceneConfiguration.lightPositionWorld,
                    eyeWorld: eyeWorld
                )

                for (index, buffer) in object.mesh.vertexBuffers.enumerated() {
                    encoder.setVertexBuffer(
                        buffer.buffer,
                        offset: buffer.offset,
                        index: index
                    )
                }

                encoder.setVertexBytes(
                    &uniforms,
                    length: MemoryLayout<ShaderUniforms>.stride,
                    index: 1
                )

                encoder.setFragmentBytes(
                    &uniforms,
                    length: MemoryLayout<ShaderUniforms>.stride,
                    index: 1
                )

                for submesh in object.mesh.submeshes {
                    encoder.drawIndexedPrimitives(
                        type: submesh.primitiveType,
                        indexCount: submesh.indexCount,
                        indexType: submesh.indexType,
                        indexBuffer: submesh.indexBuffer.buffer,
                        indexBufferOffset: submesh.indexBuffer.offset
                    )
                }
            }
        }
        return true
    }
}

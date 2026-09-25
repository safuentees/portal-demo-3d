import MetalKit
import QuartzCore
import simd

final class Renderer: NSObject, MTKViewDelegate {
    private enum SetupError: LocalizedError {
        case missingDevice, missingCommandQueue, missingLibrary
        case missingShaders, invalidVertexDescriptor, missingDepthState
        case duplicateObjectID, missingPortals, invalidPlacement, invalidFloorCheckerSize

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
            case .invalidFloorCheckerSize: return "Floor checker size must be finite and positive."
            }
        }
    }

    private let device: MTLDevice
    private let colorPixelFormat: MTLPixelFormat
    private let depthPixelFormat: MTLPixelFormat
    private let commandQueue: MTLCommandQueue
    private let objects: [RenderObject]
    private let hasEntranceSurface: Bool
    private let pipelineState: MTLRenderPipelineState
    private let fovPipelineState: MTLRenderPipelineState
    private let floorPipelineState: MTLRenderPipelineState
    private let textureScenePipelineState: MTLRenderPipelineState
    private let textureFOVPipelineState: MTLRenderPipelineState
    private let textureFloorPipelineState: MTLRenderPipelineState
    private let texturePreviewPipelineState: MTLRenderPipelineState
    private let textureSurfacePipelineState: MTLRenderPipelineState

    private let depthState: MTLDepthStencilState
    private let previewDepthState: MTLDepthStencilState
    private let portalMapping: PortalMapping
    private let showsMappedPreview: Bool
    private var camera: Camera

    private var lastFrameTime: CFTimeInterval?

    // GPU images, reused between frames and replaced together when the size changes.
    // Read-only outside Renderer so offscreen checks can inspect the actual result.
    private(set) var mappedColorTexture: MTLTexture?
    private(set) var mappedDepthTexture: MTLTexture?

    // Supplied resources/scene/camera let smoke checks use deterministic fixtures.
    init(
        view: MTKView,
        library suppliedLibrary: MTLLibrary? = nil,
        objects suppliedObjects: [RenderObject]? = nil,
        camera: Camera = Camera(),
        showsMappedPreview: Bool = SceneConfiguration.showsMappedPreview,
        showsDiagnosticObjects: Bool = SceneConfiguration.showsDiagnosticObjects
    ) throws {
        guard let device = view.device else { throw SetupError.missingDevice }
        self.device = device
        colorPixelFormat = view.colorPixelFormat
        depthPixelFormat = view.depthStencilPixelFormat
        guard SceneConfiguration.floorCheckerSize.isFinite, SceneConfiguration.floorCheckerSize > 0 else {
            throw SetupError.invalidFloorCheckerSize
        }
        guard let queue = device.makeCommandQueue() else { throw SetupError.missingCommandQueue }
        commandQueue = queue
        self.camera = camera
        self.showsMappedPreview = showsMappedPreview

        if let suppliedObjects {
            objects = suppliedObjects
        } else {
            let cubeMesh = try CubeMesh.make(device: device)
            let quadMesh = try QuadMesh.make(device: device)

            var scene = [
                RenderObject(id: .entrance, mesh: cubeMesh, placement: SceneConfiguration.entrancePlacement),
                RenderObject(id: .exit, mesh: cubeMesh, placement: SceneConfiguration.exitPlacement),
                RenderObject(id: .player, mesh: cubeMesh, placement: SceneConfiguration.playerPlacement),
                // Unit XY quad: the same scale/frame puts it in the entrance opening.
                RenderObject(id: .quad, mesh: quadMesh, placement: SceneConfiguration.entrancePlacement),
                RenderObject(id: .floor, mesh: quadMesh, placement: SceneConfiguration.floorPlacement),
                RenderObject(id: .nearBlock, mesh: cubeMesh, placement: SceneConfiguration.exitBlockPlacement),
                RenderObject(id: .sphere, mesh: try SphereMesh.make(device: device),
                             placement: SceneConfiguration.exitSpherePlacement)
            ]
            for (index, placement) in SceneConfiguration.portalBoundaryPlacements(for: SceneConfiguration.entrancePlacement).enumerated() {
                scene.append(RenderObject(id: .entranceBoundary(index), mesh: quadMesh, placement: placement))
            }
            if showsDiagnosticObjects {
                // Build once at aspect 1; resize by scaling camera-local X.
                let coneMesh = try ConeMesh.make(
                    device: device, fieldOfView: SceneConfiguration.fieldOfViewRadians,
                    aspect: 1, near: SceneConfiguration.nearPlane, far: SceneConfiguration.farPlane
                )
                scene += [
                    RenderObject(id: .fov, mesh: coneMesh),
                    RenderObject(id: .foregroundBlock, mesh: cubeMesh, placement: SceneConfiguration.foregroundBlockPlacement),
                    RenderObject(id: .cube, mesh: cubeMesh, placement: SceneConfiguration.rearBlockPlacement)
                ]
                scene += SceneConfiguration.diagnosticExitPlacements.map {
                    RenderObject(id: $0.id, mesh: cubeMesh, placement: $0.placement)
                }
            }
            objects = scene
        }
        hasEntranceSurface = objects.contains { $0.id == .quad }
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
              let fovFragment = library.makeFunction(name: "fov_fragment"),
              let floorFragment = library.makeFunction(name: "floor_fragment"),
              let previewVertex = library.makeFunction(name: "texture_preview_vertex"),
              let previewFragment = library.makeFunction(name: "texture_preview_fragment"),
              let surfaceVertex = library.makeFunction(name: "texture_surface_vertex"),
              let surfaceFragment = library.makeFunction(name: "texture_surface_fragment") else {
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

        pipeline.label = "Filtered checker ground"
        pipeline.fragmentFunction = floorFragment
        floorPipelineState = try device.makeRenderPipelineState(descriptor: pipeline)

        // The sampled camera image is single-sample, even if the window uses MSAA.
        if view.sampleCount == 1 {
            textureScenePipelineState = pipelineState
            textureFOVPipelineState = fovPipelineState
            textureFloorPipelineState = floorPipelineState
        } else {
            pipeline.rasterSampleCount = 1
            pipeline.label = "Lit scene into camera texture"
            pipeline.fragmentFunction = fragment
            textureScenePipelineState = try device.makeRenderPipelineState(descriptor: pipeline)
            pipeline.label = "FOV into camera texture"
            pipeline.fragmentFunction = fovFragment
            textureFOVPipelineState = try device.makeRenderPipelineState(descriptor: pipeline)
            pipeline.label = "Filtered checker ground into camera texture"
            pipeline.fragmentFunction = floorFragment
            textureFloorPipelineState = try device.makeRenderPipelineState(descriptor: pipeline)
        }

        let previewPipeline = MTLRenderPipelineDescriptor()
        previewPipeline.label = "Camera texture preview"
        previewPipeline.vertexFunction = previewVertex
        previewPipeline.fragmentFunction = previewFragment
        previewPipeline.colorAttachments[0].pixelFormat = view.colorPixelFormat
        previewPipeline.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        previewPipeline.rasterSampleCount = view.sampleCount
        texturePreviewPipelineState = try device.makeRenderPipelineState(descriptor: previewPipeline)

        let surfacePipeline = MTLRenderPipelineDescriptor()
        surfacePipeline.label = "Mapped image on entrance quad"
        surfacePipeline.vertexFunction = surfaceVertex
        surfacePipeline.fragmentFunction = surfaceFragment
        surfacePipeline.vertexDescriptor = vertexDescriptor
        surfacePipeline.colorAttachments[0].pixelFormat = view.colorPixelFormat
        surfacePipeline.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        surfacePipeline.rasterSampleCount = view.sampleCount
        textureSurfacePipelineState = try device.makeRenderPipelineState(descriptor: surfacePipeline)

        let depth = MTLDepthStencilDescriptor()
        depth.label = "Depth test"
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor: depth) else {
            throw SetupError.missingDepthState
        }
        depthState = state
        let previewDepth = MTLDepthStencilDescriptor()
        previewDepth.label = "Texture preview without depth writes"
        previewDepth.depthCompareFunction = .always
        previewDepth.isDepthWriteEnabled = false
        guard let previewState = device.makeDepthStencilState(descriptor: previewDepth) else {
            throw SetupError.missingDepthState
        }
        previewDepthState = previewState
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1 else { return }
        _ = updateMappedTargets(width: sourceViewportWidth(for: Int(size.width)), height: Int(size.height))
    }

    /// Shared by resize and drawing so the capture always matches the main view.
    private func sourceViewportWidth(for drawableWidth: Int) -> Int {
        showsMappedPreview ? drawableWidth / 2 : drawableWidth
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

    /// Allocate only on first use or resize, never once per ordinary frame.
    /// encodeFrame also calls this so onscreen and headless paths use the same sizing.
    private func updateMappedTargets(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        if let color = mappedColorTexture, let depth = mappedDepthTexture,
           color.width == width, color.height == height,
           depth.width == width, depth.height == height {
            return true
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: colorPixelFormat, width: width, height: height, mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let color = device.makeTexture(descriptor: descriptor) else { return false }
        descriptor.pixelFormat = depthPixelFormat
        descriptor.usage = .renderTarget
        guard let depth = device.makeTexture(descriptor: descriptor) else { return false }
        color.label = "Mapped camera color"
        depth.label = "Mapped camera depth"
        mappedColorTexture = color
        mappedDepthTexture = depth
        return true
    }

    /// drawableSize is the FULL attachment size in pixels, not one viewport's size.
    /// Pass 1 records the mapped camera for the entrance surface. Pass 2 draws the
    /// source scene and optional preview. Neither pass changes the camera or input.
    @discardableResult
    func encodeFrame(
        commandBuffer: MTLCommandBuffer,
        renderPass: MTLRenderPassDescriptor,
        drawableSize: CGSize
    ) -> Bool {
        guard drawableSize.width.isFinite, drawableSize.height.isFinite,
              drawableSize.width >= 1, drawableSize.height >= 1,
              let target = renderPass.colorAttachments[0].texture,
              drawableSize.width == CGFloat(target.width),
              drawableSize.height == CGFloat(target.height) else {
            return false
        }
        let sourceWidth = sourceViewportWidth(for: target.width)
        let height = target.height
        guard updateMappedTargets(width: sourceWidth, height: height),
              let mappedColorTexture, let mappedDepthTexture else { return false }

        let sourceViewport = MTLViewport(originX: 0, originY: 0,
            width: Double(sourceWidth), height: Double(height), znear: 0, zfar: 1)
        let sourceAspect = Float(sourceWidth) / Float(height)
        let projection = Transforms.perspective(
            aspect: sourceAspect, fieldOfView: SceneConfiguration.fieldOfViewRadians,
            near: SceneConfiguration.nearPlane, far: SceneConfiguration.farPlane
        )
        let sourceCameraWorld = camera.inverseViewMatrix
        let mappedCameraWorld = sourceCameraWorld * portalMapping.transferAB

        // Place each object once. Both scene passes receive these same world poses.
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

        // First pass: the mapped camera draws into its own color/depth attachments.
        let cameraPass = MTLRenderPassDescriptor()
        cameraPass.colorAttachments[0].texture = mappedColorTexture
        cameraPass.colorAttachments[0].loadAction = .clear
        cameraPass.colorAttachments[0].clearColor = SceneConfiguration.backgroundColor
        cameraPass.colorAttachments[0].storeAction = .store
        cameraPass.depthAttachment.texture = mappedDepthTexture
        cameraPass.depthAttachment.loadAction = .clear
        cameraPass.depthAttachment.clearDepth = 1
        cameraPass.depthAttachment.storeAction = .dontCare
        do {
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: cameraPass) else { return false }
            encoder.label = "Record mapped camera"
            // This scope ends the first encoder BEFORE the window encoder is created.
            defer { encoder.endEncoding() }
            encodeScene(encoder: encoder, viewport: sourceViewport,
                viewMatrix: simd_inverse(mappedCameraWorld), cameraWorld: mappedCameraWorld,
                projection: projection, worldModels: worldModels, normalMatrices: normalMatrices,
                intoCameraTexture: true)
        }

        // Second pass: the source fills the window unless a right preview is enabled.
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return false }
        encoder.label = "Source scene and optional camera preview"
        defer { encoder.endEncoding() }
        encodeScene(encoder: encoder, viewport: sourceViewport,
            viewMatrix: camera.viewMatrix, cameraWorld: sourceCameraWorld,
            projection: projection, worldModels: worldModels, normalMatrices: normalMatrices,
            intoCameraTexture: false)

        if showsMappedPreview {
            let previewWidth = target.width - sourceWidth
            let previewViewport = MTLViewport(originX: Double(sourceWidth), originY: 0,
                width: Double(previewWidth), height: Double(height), znear: 0, zfar: 1)
            setViewport(previewViewport, on: encoder)
            encoder.setRenderPipelineState(texturePreviewPipelineState)
            encoder.setDepthStencilState(previewDepthState)
            encoder.setFragmentTexture(mappedColorTexture, index: 0)
            // Buffer 2 is a separate 16-byte preview contract; scene uniforms stay at 1.
            var viewportRect = SIMD4<Float>(Float(sourceWidth), 0, Float(previewWidth), Float(height))
            encoder.setFragmentBytes(&viewportRect, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        return true
    }

    private func setViewport(_ viewport: MTLViewport, on encoder: MTLRenderCommandEncoder) {
        encoder.setViewport(viewport)
        encoder.setScissorRect(MTLScissorRect(
            x: Int(viewport.originX), y: Int(viewport.originY),
            width: Int(viewport.width), height: Int(viewport.height)
        ))
    }

    /// The shared object loop handles one camera, regardless of its render target.
    private func encodeScene(
        encoder: MTLRenderCommandEncoder, viewport: MTLViewport,
        viewMatrix: simd_float4x4, cameraWorld: simd_float4x4, projection: simd_float4x4,
        worldModels: [simd_float4x4], normalMatrices: [simd_float3x3], intoCameraTexture: Bool
    ) {
        setViewport(viewport, on: encoder)
        encoder.setDepthStencilState(depthState)
        let cameraPoint = SIMD4<Float>(0, 0, 0, 1) * cameraWorld
        let eyeWorld = cameraPoint / cameraPoint.w

        for (objectIndex, object) in objects.enumerated() {
            // Keep the exit out of the capture, and never sample the image while
            // writing it. The entrance stays an ordinary solid in that capture.
            if intoCameraTexture && (object.id == .exit || object.id == .quad || object.id == .fov) { continue }
            if intoCameraTexture, case .entranceBoundary = object.id { continue }
            // In the source view the quad replaces the filled entrance. Drawing
            // the cube too would hide the quad at its local Z = 0 opening plane.
            if !intoCameraTexture && hasEntranceSurface && object.id == .entrance { continue }
            let style: (pipeline: MTLRenderPipelineState, color: SIMD4<Float>)
            switch object.id {
            case .quad:
                style = (textureSurfacePipelineState, SIMD4<Float>(repeating: 1))
                encoder.setFragmentTexture(mappedColorTexture, index: 0)
            case .fov:
                style = (intoCameraTexture ? textureFOVPipelineState : fovPipelineState,
                         SceneConfiguration.mappedFOVColor)
            case .entrance, .exit, .entranceBoundary:
                style = (intoCameraTexture ? textureScenePipelineState : pipelineState,
                         SceneConfiguration.portalColor)
            case .player:
                style = (intoCameraTexture ? textureScenePipelineState : pipelineState,
                         SceneConfiguration.mappedPlayerColor)
            case .floor:
                style = (intoCameraTexture ? textureFloorPipelineState : floorPipelineState,
                         SceneConfiguration.floorColorA)
                var floor = FloorUniforms(colorA: SceneConfiguration.floorColorA,
                    colorB: SceneConfiguration.floorColorB, checkerSize: SceneConfiguration.floorCheckerSize)
                // A separate material contract; the 352-byte scene layout is unchanged.
                encoder.setFragmentBytes(&floor, length: MemoryLayout<FloorUniforms>.stride, index: 2)
            default:
                style = (intoCameraTexture ? textureScenePipelineState : pipelineState,
                         SceneConfiguration.sceneObjectColor)
            }
            // Every draw explicitly selects its pipeline, including after an FOV.
            encoder.setRenderPipelineState(style.pipeline)
            var uniforms = ShaderUniforms(
                modelMatrix: worldModels[objectIndex], viewMatrix: viewMatrix,
                projectionMatrix: projection, normalMatrix: normalMatrices[objectIndex],
                color: style.color, lightColor: SceneConfiguration.lightColor,
                lightPositionWorld: SceneConfiguration.lightPositionWorld, eyeWorld: eyeWorld,
                ambientIntensity: SceneConfiguration.ambientIntensity,
                diffuseIntensity: SceneConfiguration.diffuseIntensity,
                specularIntensity: SceneConfiguration.specularIntensity,
                specularShininess: SceneConfiguration.specularShininess,
                fillLightDirectionWorld: SceneConfiguration.fillLightDirectionWorld,
                fillIntensity: SceneConfiguration.fillIntensity
            )
            for (index, buffer) in object.mesh.vertexBuffers.enumerated() {
                encoder.setVertexBuffer(buffer.buffer, offset: buffer.offset, index: index)
            }
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 1)
            for submesh in object.mesh.submeshes {
                encoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount,
                    indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer,
                    indexBufferOffset: submesh.indexBuffer.offset)
            }
        }
    }
}

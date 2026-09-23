import MetalKit
import simd

/// Float targets expose nonfinite shader results instead of hiding them in UNorm conversion.
enum LightingChecks {
    static func run(device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary) throws {
        let mesh = try makePlane(device: device)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "scene_vertex")
        descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        descriptor.fragmentFunction = library.makeFunction(name: "lit_fragment")
        let litPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        descriptor.fragmentFunction = library.makeFunction(name: "fov_fragment")
        let unlitPipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        let pointWorld = SIMD3<Float>(0, 0, 4)
        let material = SIMD4<Float>(0.23, 0.47, 0.61, 1)
        let lightColor = SIMD4<Float>(0.9, 0.8, 0.7, 1)
        let materialLight = SmokeTests.xyz(material) * SmokeTests.xyz(lightColor)
        var uniforms = ShaderUniforms(
            modelMatrix: matrix_identity_float4x4, viewMatrix: matrix_identity_float4x4,
            projectionMatrix: Transforms.perspective(aspect: 1, fieldOfView: .pi / 2, near: 0.1, far: 100),
            normalMatrix: matrix_identity_float3x3, color: material, lightColor: lightColor,
            lightPositionWorld: [2, 0, 0, 1], eyeWorld: [0, 0, 0, 1],
            ambientIntensity: 0, diffuseIntensity: 0, specularIntensity: 0, specularShininess: 12,
            fillLightDirectionWorld: [0, 3, -4, 0], fillIntensity: 0)
        func draw(_ value: ShaderUniforms, unlit: Bool = false) throws -> SIMD4<Float> {
            try sample(device: device, queue: queue, mesh: mesh,
                       pipeline: unlit ? unlitPipeline : litPipeline, uniforms: value)
        }
        func expectColor(_ actual: SIMD4<Float>, _ expectedRGB: SIMD3<Float>, _ label: String) throws {
            let expected = SIMD4<Float>(expectedRGB, material.w)
            try SmokeTests.expect((0..<4).allSatisfy { actual[$0].isFinite }, "\(label) produced nonfinite shader output.")
            try SmokeTests.expect(simd_length(actual - expected) < 0.0002,
                                  "\(label): got \(actual), expected \(expected).")
        }
        // Both cameras aim at the same fixed world point. Thus a center pixel samples
        // identical geometry while eye-dependent specular is allowed to change.
        func movedCamera(_ value: ShaderUniforms) -> ShaderUniforms {
            var result = value
            let cameraWorld = Transforms.rotateY(atan(3.0 / 4.0)) * Transforms.translation([3, 0, 0])
            result.viewMatrix = simd_inverse(cameraWorld)
            result.eyeWorld = [3, 0, 0, 1]
            return result
        }
        let lightDirection = simd_normalize(SmokeTests.xyz(uniforms.lightPositionWorld) - pointWorld)
        let diffuse = -lightDirection.z
        func specularFactor(_ value: ShaderUniforms) -> Float {
            let view = simd_normalize(SmokeTests.xyz(value.eyeWorld) - pointWorld)
            let halfDirection = simd_normalize(lightDirection + view)
            return pow(max(-halfDirection.z, 0), value.specularShininess)
        }

        try expectColor(draw(uniforms), .zero, "Zero intensities")
        uniforms.ambientIntensity = 0.27
        try expectColor(draw(uniforms), materialLight * 0.27, "Independent ambient intensity")
        uniforms.ambientIntensity = 0
        uniforms.diffuseIntensity = 0.63
        let diffuseExpected = materialLight * (0.63 * diffuse)
        let sourceDiffuse = try draw(uniforms)
        let movedDiffuse = try draw(movedCamera(uniforms))
        try expectColor(sourceDiffuse, diffuseExpected, "Independent diffuse intensity")
        try expectColor(movedDiffuse, diffuseExpected, "World-stable diffuse under camera movement")
        try SmokeTests.expect(simd_length(sourceDiffuse - movedDiffuse) < 0.0002,
                              "Moving the camera changed diffuse at the same world point.")

        uniforms.diffuseIntensity = 0
        uniforms.specularIntensity = 0.31
        let sourceSpecular = try draw(uniforms)
        let moved = movedCamera(uniforms)
        let movedSpecular = try draw(moved)
        try expectColor(sourceSpecular, SmokeTests.xyz(lightColor) * (0.31 * specularFactor(uniforms)),
                        "Independent untinted specular intensity")
        try expectColor(movedSpecular, SmokeTests.xyz(lightColor) * (0.31 * specularFactor(moved)),
                        "View-dependent specular highlight")
        try SmokeTests.expect(simd_length(sourceSpecular - movedSpecular) > 0.1,
                              "The direct lighting fixture must distinguish the two camera highlights.")
        uniforms.specularShininess = 48
        try expectColor(draw(uniforms), SmokeTests.xyz(lightColor) * (0.31 * specularFactor(uniforms)),
                        "Independent specular shininess")

        uniforms.specularIntensity = 0
        uniforms.fillIntensity = 0.37
        let fillExpected = materialLight * (0.37 * 0.8)
        try expectColor(draw(uniforms), fillExpected, "Independent directional fill intensity")
        try expectColor(draw(movedCamera(uniforms)), fillExpected, "World-stable directional fill")
        uniforms.fillLightDirectionWorld = .zero
        try expectColor(draw(uniforms), .zero, "Zero fill direction")

        uniforms.fillIntensity = 0
        uniforms.ambientIntensity = 0.17
        uniforms.diffuseIntensity = 0.52
        uniforms.specularIntensity = 0.23
        uniforms.specularShininess = 11
        try expectColor(draw(uniforms), materialLight * (0.17 + 0.52 * diffuse)
            + SmokeTests.xyz(lightColor) * (0.23 * specularFactor(uniforms)), "Combined independent uploads")

        uniforms.lightPositionWorld = SIMD4<Float>(pointWorld, 1)
        try expectColor(draw(uniforms), materialLight * 0.17, "Zero light vector has no diffuse or specular")
        uniforms.lightPositionWorld = [0, 0, 0, 1]
        uniforms.eyeWorld = SIMD4<Float>(pointWorld, 1)
        let withoutSpecular = materialLight * (0.17 + 0.52)
        try expectColor(draw(uniforms), withoutSpecular, "Zero view vector has no false highlight")
        uniforms.eyeWorld = [0, 0, 8, 1]
        try expectColor(draw(uniforms), withoutSpecular, "Opposite light and view vectors have no false highlight")
        uniforms.lightPositionWorld = [4, 0, 5, 1]
        uniforms.eyeWorld = [0, 0, 0, 1]
        uniforms.specularShininess = 2
        try expectColor(draw(uniforms), materialLight * 0.17, "Back-facing main light has no diffuse or specular")

        uniforms.ambientIntensity = 2
        uniforms.diffuseIntensity = 3
        uniforms.specularIntensity = 4
        uniforms.fillIntensity = 5
        try expectColor(draw(uniforms, unlit: true), SmokeTests.xyz(material), "FOV stays exactly unlit")
        print("PASS: independent lighting controls, world-stable diffuse/fill, view-dependent specular, finite degenerate directions")
    }

    static func makePlane(device: MTLDevice) throws -> MTKMesh {
        // A single triangle covers the center pixel; its world sample is exactly (0,0,4).
        let vertices: [Float] = [
            -8, -8, 4, 0, 0, -1, 0, 0,
            24, -8, 4, 0, 0, -1, 0, 0,
            -8, 24, 4, 0, 0, -1, 0, 0
        ]
        let indices: [UInt16] = [0, 1, 2]
        let allocator = MTKMeshBufferAllocator(device: device)
        let vertexBuffer = allocator.newBuffer(with: vertices.withUnsafeBytes { Data($0) }, type: .vertex)
        let indexBuffer = allocator.newBuffer(with: indices.withUnsafeBytes { Data($0) }, type: .index)
        let submesh = MDLSubmesh(indexBuffer: indexBuffer, indexCount: indices.count,
            indexType: .uInt16, geometryType: .triangles, material: nil)
        let model = MDLMesh(vertexBuffer: vertexBuffer, vertexCount: 3,
            descriptor: MeshVertexLayout.makeDescriptor(), submeshes: [submesh])
        return try MTKMesh(mesh: model, device: device)
    }

    static func sample(
        device: MTLDevice, queue: MTLCommandQueue, mesh: MTKMesh,
        pipeline: MTLRenderPipelineState, uniforms: ShaderUniforms
    ) throws -> SIMD4<Float> {
        // An odd-sized target puts one pixel exactly on the optical axis while
        // avoiding the coarse vertex snapping of a single-pixel viewport.
        let size = 65
        let bytesPerRow = ((size * 16 + 255) / 256) * 256
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: size, height: size, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .private
        guard let target = device.makeTexture(descriptor: descriptor),
              let readback = device.makeBuffer(length: bytesPerRow * size, options: .storageModeShared),
              let command = queue.makeCommandBuffer() else {
            throw SmokeTests.Failure(description: "Could not allocate the float lighting fixture.")
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: -1, green: -1, blue: -1, alpha: -1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw SmokeTests.Failure(description: "Could not encode the float lighting fixture.")
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(size), height: Double(size), znear: 0, zfar: 1))
        let buffer = mesh.vertexBuffers[0]
        encoder.setVertexBuffer(buffer.buffer, offset: buffer.offset, index: 0)
        var uploaded = uniforms
        encoder.setVertexBytes(&uploaded, length: MemoryLayout<ShaderUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uploaded, length: MemoryLayout<ShaderUniforms>.stride, index: 1)
        for submesh in mesh.submeshes {
            encoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount,
                indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer,
                indexBufferOffset: submesh.indexBuffer.offset)
        }
        encoder.endEncoding()
        guard let blit = command.makeBlitCommandEncoder() else {
            throw SmokeTests.Failure(description: "Could not read back the float lighting fixture.")
        }
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: size, height: size, depth: 1), to: readback,
            destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * size)
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        try SmokeTests.expect(command.status == .completed, "Float lighting fixture did not complete.")
        let centerOffset = (size / 2) * bytesPerRow + (size / 2) * 16
        let values = readback.contents().advanced(by: centerOffset).assumingMemoryBound(to: Float.self)
        return SIMD4(values[0], values[1], values[2], values[3])
    }
}

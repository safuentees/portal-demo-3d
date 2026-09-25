import MetalKit
import simd

/// Independent mesh invariants and a real shader draw keep a torus's hole,
/// smooth outward normals, seams, and packed vertex contract observable.
enum TorusChecks {
    static func run(device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary) throws {
        for (major, tube, rings, sides): (Float, Float, Int, Int) in [
            (1.2, 0.3, 32, 12), (0.65, 0.12, 7, 5), (1, 0.2, 3, 3)
        ] {
            let mesh = try TorusMesh.make(device: device, majorRadius: major, tubeRadius: tube,
                                          ringSegments: rings, tubeSegments: sides)
            try checkGeometry(mesh, major: major, tube: tube, rings: rings, sides: sides)
        }
        let invalid: [(Float, Float, Int, Int)] = [
            (0, 0.1, 16, 8), (-1, 0.1, 16, 8), (1, 0, 16, 8), (1, -0.1, 16, 8),
            (1, 1, 16, 8), (1, 1.1, 16, 8), (.nan, 0.1, 16, 8),
            (.infinity, 0.1, 16, 8), (1, .nan, 16, 8), (1, .infinity, 16, 8),
            (.greatestFiniteMagnitude, .greatestFiniteMagnitude / 2, 16, 8),
            (1, 0.2, 2, 8), (1, 0.2, 16, 2), (1, 0.2, 0, 8),
            (1, 0.2, -1, 8), (1, 0.2, Int.max, 8), (1, 0.2, 16, Int.max)
        ]
        for (major, tube, rings, sides) in invalid {
            var rejected = false
            do {
                _ = try TorusMesh.make(device: device, majorRadius: major, tubeRadius: tube,
                                       ringSegments: rings, tubeSegments: sides)
            } catch {
                rejected = true
            }
            try SmokeTests.expect(rejected,
                "Invalid torus parameters were accepted: \(major), \(tube), \(rings), \(sides).")
        }
        try checkRenderedHole(device: device, queue: queue, library: library)
        print("PASS: torus radii, outward normals/winding, exact seam closure, packed layout, invalid parameters, and GPU hole from both sides")
    }

    private static func checkGeometry(
        _ mesh: MTKMesh, major: Float, tube: Float, rings: Int, sides: Int
    ) throws {
        try SmokeTests.expect(mesh.vertexBuffers.count == 1 && mesh.vertexCount == (rings + 1) * (sides + 1),
                              "The torus must contain one packed grid with duplicated UV seams.")
        let layout = mesh.vertexDescriptor.layouts[0] as! MDLVertexBufferLayout
        try SmokeTests.expect(layout.stride == 32, "Torus vertices must use the 32-byte scene layout.")
        for (index, offset, format): (Int, Int, MDLVertexFormat) in [(0, 0, .float3), (1, 12, .float3), (2, 24, .float2)] {
            let attribute = mesh.vertexDescriptor.attributes[index] as! MDLVertexAttribute
            try SmokeTests.expect(attribute.offset == offset && attribute.format == format && attribute.bufferIndex == 0,
                                  "Torus position, normal, and UV attributes must match the scene pipeline.")
        }
        let buffer = mesh.vertexBuffers[0]
        let bytes = buffer.buffer.contents().advanced(by: buffer.offset)
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvIndices: [SIMD2<Int>: Int] = [:]
        for index in 0..<mesh.vertexCount {
            let vertex = bytes.advanced(by: index * layout.stride).assumingMemoryBound(to: Float.self)
            let position = SIMD3<Float>(vertex[0], vertex[1], vertex[2])
            let normal = SIMD3<Float>(vertex[3], vertex[4], vertex[5])
            let uv = SIMD2<Float>(vertex[6], vertex[7])
            try SmokeTests.expect((0..<8).allSatisfy { vertex[$0].isFinite }, "Torus vertex contains nonfinite data.")
            let radialDistance = simd_length(SIMD2(position.x, position.y))
            let tubeOffset = SIMD2(radialDistance - major, position.z)
            try SmokeTests.expect(abs(simd_length(tubeOffset) - tube) < 0.00001,
                                  "A torus vertex is not the requested distance from its central ring.")
            let ringCenter = SIMD3(position.x, position.y, 0) * (major / radialDistance)
            let outward = simd_normalize(position - ringCenter)
            try SmokeTests.expect(abs(simd_length(normal) - 1) < 0.00001 && simd_dot(normal, outward) > 0.99999,
                                  "Torus normals must be unit length and point away from the tube center.")
            try SmokeTests.expect(uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1,
                                  "Torus UV coordinates must cover the normalized grid.")
            let key = SIMD2<Int>(Int((uv.x * Float(rings)).rounded()), Int((uv.y * Float(sides)).rounded()))
            try SmokeTests.expect(uvIndices.updateValue(index, forKey: key) == nil, "Torus UV grid contains duplicate vertices.")
            positions.append(position)
            normals.append(normal)
        }
        for ring in 0...rings {
            for side in 0...sides {
                try SmokeTests.expect(uvIndices[SIMD2(ring, side)] != nil, "Torus UV grid is missing a vertex.")
            }
        }
        // The texture coordinates differ at each seam, but its geometry must
        // close exactly; separately evaluated sin(2π) can otherwise leave cracks.
        for side in 0...sides {
            let first = uvIndices[SIMD2(0, side)]!, last = uvIndices[SIMD2(rings, side)]!
            try SmokeTests.expect(positions[first] == positions[last] && normals[first] == normals[last],
                                  "The ring seam must have identical positions and normals.")
        }
        for ring in 0...rings {
            let first = uvIndices[SIMD2(ring, 0)]!, last = uvIndices[SIMD2(ring, sides)]!
            try SmokeTests.expect(positions[first] == positions[last] && normals[first] == normals[last],
                                  "The tube seam must have identical positions and normals.")
        }
        try SmokeTests.expect(mesh.submeshes.count == 1, "The torus must use one indexed triangle submesh.")
        let submesh = mesh.submeshes[0]
        try SmokeTests.expect(submesh.primitiveType == .triangle && submesh.indexType == .uint32
            && submesh.indexCount == rings * sides * 6, "Torus triangle topology/count is incorrect.")
        let indices = submesh.indexBuffer.buffer.contents().advanced(by: submesh.indexBuffer.offset)
            .assumingMemoryBound(to: UInt32.self)
        for index in stride(from: 0, to: submesh.indexCount, by: 3) {
            let a = Int(indices[index]), b = Int(indices[index + 1]), c = Int(indices[index + 2])
            try SmokeTests.expect(a < mesh.vertexCount && b < mesh.vertexCount && c < mesh.vertexCount,
                                  "A torus triangle indexes outside its vertex buffer.")
            let faceNormal = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            try SmokeTests.expect(simd_dot(faceNormal, normals[a] + normals[b] + normals[c]) > 0,
                                  "Torus triangles must be nondegenerate and wound toward their outward normals.")
        }
    }

    private static func checkRenderedHole(device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary) throws {
        let mesh = try TorusMesh.make(device: device, majorRadius: 0.8, tubeRadius: 0.23,
                                      ringSegments: 48, tubeSegments: 24)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "scene_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "lit_fragment")
        descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let material = SIMD4<Float>(0.31, 0.43, 0.57, 1)
        for z: Float in [-3, 3] {
            for (x, expected): (Float, SIMD4<Float>) in [(0, SIMD4(repeating: -1)), (0.8, material), (1.4, SIMD4(repeating: -1))] {
                let eye = SIMD3<Float>(x, 0, z)
                let cameraWorld = Transforms.rotateY(z > 0 ? .pi : 0) * Transforms.translation(eye)
                let uniforms = ShaderUniforms(
                    modelMatrix: matrix_identity_float4x4, viewMatrix: simd_inverse(cameraWorld),
                    projectionMatrix: Transforms.perspective(aspect: 1, fieldOfView: .pi / 3, near: 0.1, far: 10),
                    normalMatrix: matrix_identity_float3x3, color: material,
                    lightColor: SIMD4(repeating: 1), lightPositionWorld: [0, 4, -3, 1], eyeWorld: SIMD4(eye, 1),
                    ambientIntensity: 1, diffuseIntensity: 0, specularIntensity: 0, specularShininess: 20,
                    fillLightDirectionWorld: [0, 1, 0, 0], fillIntensity: 0)
                let color = try LightingChecks.sample(device: device, queue: queue, mesh: mesh,
                                                      pipeline: pipeline, uniforms: uniforms)
                try SmokeTests.expect(simd_length(color - expected) < 0.0001,
                    "The torus must leave its hole/exterior clear and shade its tube from both viewing sides (eye \(eye)).")
            }
        }
    }
}

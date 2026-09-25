import MetalKit
import ModelIO

/// Upright ring in local XY, centered at the origin; the hole runs along Z.
/// majorRadius measures to the tube's center, tubeRadius measures its thickness.
/// Outer radius = majorRadius + tubeRadius; hole radius = majorRadius - tubeRadius.
enum TorusMesh {
    enum ParameterError: LocalizedError {
        case invalidRadii, invalidSegments

        var errorDescription: String? {
            switch self {
            case .invalidRadii:
                return "Torus radii must be finite and distinguishable: 0 < tubeRadius < majorRadius."
            case .invalidSegments:
                return "Torus ring and tube segment counts must each be between 3 and 512."
            }
        }
    }

    static func make(
        device: MTLDevice, majorRadius: Float, tubeRadius: Float,
        ringSegments: Int, tubeSegments: Int
    ) throws -> MTKMesh {
        let outerRadius = majorRadius + tubeRadius
        guard majorRadius.isFinite, tubeRadius.isFinite, outerRadius.isFinite,
              tubeRadius > 0, majorRadius > tubeRadius,
              outerRadius > majorRadius, majorRadius - tubeRadius < majorRadius else {
            throw ParameterError.invalidRadii
        }
        // Bound allocation and index arithmetic before adding/multiplying counts.
        guard (3...512).contains(ringSegments), (3...512).contains(tubeSegments) else {
            throw ParameterError.invalidSegments
        }

        let rowSize = tubeSegments + 1
        let vertexCount = (ringSegments + 1) * rowSize
        var vertices: [Float] = []
        vertices.reserveCapacity(vertexCount * 8)
        for ring in 0...ringSegments {
            let u = Float(ring) / Float(ringSegments)
            // Duplicate seam vertices for UV 0/1, with identical geometry/normals.
            let angle = ring == ringSegments ? Float.zero : u * 2 * .pi
            let cosU = cos(angle), sinU = sin(angle)
            for tube in 0...tubeSegments {
                let v = Float(tube) / Float(tubeSegments)
                let tubeAngle = tube == tubeSegments ? Float.zero : v * 2 * .pi
                let cosV = cos(tubeAngle), sinV = sin(tubeAngle)
                let radius = majorRadius + tubeRadius * cosV
                // Scalars preserve the shared packed 32-byte layout; SIMD3 pads.
                vertices += [radius * cosU, radius * sinU, tubeRadius * sinV,
                             cosV * cosU, cosV * sinU, sinV, u, v]
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(ringSegments * tubeSegments * 6)
        for ring in 0..<ringSegments {
            for tube in 0..<tubeSegments {
                let a = UInt32(ring * rowSize + tube)
                let b = UInt32((ring + 1) * rowSize + tube)
                // Counterclockwise when seen from outside, matching the normals.
                indices += [a, b, b + 1, a, b + 1, a + 1]
            }
        }

        // Model I/O -> MetalKit requires MTKMeshBufferAllocator for both buffers.
        let allocator = MTKMeshBufferAllocator(device: device)
        let vertexBuffer = allocator.newBuffer(with: vertices.withUnsafeBytes { Data($0) }, type: .vertex)
        let indexBuffer = allocator.newBuffer(with: indices.withUnsafeBytes { Data($0) }, type: .index)
        let submesh = MDLSubmesh(indexBuffer: indexBuffer, indexCount: indices.count,
            indexType: .uInt32, geometryType: .triangles, material: nil)
        let model = MDLMesh(vertexBuffer: vertexBuffer, vertexCount: vertexCount,
            descriptor: MeshVertexLayout.makeDescriptor(), submeshes: [submesh])
        return try MTKMesh(mesh: model, device: device)
    }
}

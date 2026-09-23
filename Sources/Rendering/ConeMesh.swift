import MetalKit
import ModelIO

/// A camera's rectangular viewing frustum, drawn as its twelve boundary edges.
/// Local origin is the eye; +Z is forward. FOV is vertical and measured in radians.
/// Near/far are distances from the eye; the frustum's axial length is far - near.
enum ConeMesh {
    enum ParameterError: LocalizedError {
        case invalidProjection

        var errorDescription: String? {
            "ConeMesh needs finite values: 0 < fieldOfView < pi, aspect > 0, and 0 < near < far."
        }
    }

    static func make(
        device: MTLDevice,
        fieldOfView: Float,
        aspect: Float,
        near: Float,
        far: Float
    ) throws -> MTKMesh {
        guard fieldOfView.isFinite, fieldOfView > 0, fieldOfView < .pi,
              aspect.isFinite, aspect > 0,
              near.isFinite, far.isFinite, near > 0, far > near else {
            throw ParameterError.invalidProjection
        }

        let slope = tan(fieldOfView / 2)
        // Eight corners: bottom-left, bottom-right, top-right, top-left per plane.
        // Use scalar floats: SIMD3<Float> has 16-byte storage, not packed float3's 12.
        var vertices: [Float] = []
        for distance in [near, far] {
            let halfHeight = distance * slope
            let halfWidth = halfHeight * aspect
            guard halfHeight.isFinite, halfHeight > 0,
                  halfWidth.isFinite, halfWidth > 0 else {
                throw ParameterError.invalidProjection
            }
            for corner: SIMD2<Float> in [
                [-halfWidth, -halfHeight], [halfWidth, -halfHeight],
                [halfWidth, halfHeight], [-halfWidth, halfHeight]
            ] {
                // Normal/UV are unused by the unlit outline, but match other meshes.
                vertices += [corner.x, corner.y, distance, 0, 0, 1, 0, 0]
            }
        }
        let indices: [UInt16] = [
            0, 1, 1, 2, 2, 3, 3, 0, // Near rectangle
            4, 5, 5, 6, 6, 7, 7, 4, // Far rectangle
            0, 4, 1, 5, 2, 6, 3, 7  // Connecting edges
        ]

        let allocator = MTKMeshBufferAllocator(device: device)
        let vertexData = vertices.withUnsafeBytes { Data($0) }
        let indexData = indices.withUnsafeBytes { Data($0) }
        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer, indexCount: indices.count, indexType: .uInt16,
            geometryType: .lines, material: nil
        )

        let descriptor = MeshVertexLayout.makeDescriptor()
        let model = MDLMesh(
            vertexBuffer: vertexBuffer, vertexCount: 8,
            descriptor: descriptor, submeshes: [submesh]
        )
        return try MTKMesh(mesh: model, device: device)
    }
}

import MetalKit
import ModelIO

/// A camera's rectangular viewing frustum, drawn as its twelve boundary edges.
/// Local origin is the eye; +Z is forward. FOV is vertical and measured in radians.
/// Near/far are distances from the eye; the frustum's axial length is far - near.
enum QuadMesh {
    enum ParameterError: LocalizedError {
        case invalidProjection

        var errorDescription: String? {
            "ConeMesh needs finite values: 0 < fieldOfView < pi, aspect > 0, and 0 < near < far."
        }
    }

    static func make(
        device: MTLDevice,
    ) throws -> MTKMesh {
        // TODO: add guard

        let vertices: [Float] = [
            // Position          Normal      UV
            -0.5, -0.5, 0,       0, 0, 1,    0, 0,
             0.5, -0.5, 0,       0, 0, 1,    1, 0,
             0.5,  0.5, 0,       0, 0, 1,    1, 1,
            -0.5,  0.5, 0,       0, 0, 1,    0, 1,
        ]
        
        let indices: [UInt16] = [
            0, 1, 2,
            0, 2, 3,
        ]

        let allocator = MTKMeshBufferAllocator(device: device)
        let vertexData = vertices.withUnsafeBytes { Data($0) }
        let indexData = indices.withUnsafeBytes { Data($0) }
        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer, indexCount: indices.count, indexType: .uInt16,
            geometryType: .triangles, material: nil
        )

        let descriptor = MeshVertexLayout.makeDescriptor()
        let model = MDLMesh(
            vertexBuffer: vertexBuffer, vertexCount: 4,
            descriptor: descriptor, submeshes: [submesh]
        )
        return try MTKMesh(mesh: model, device: device)
    }
}

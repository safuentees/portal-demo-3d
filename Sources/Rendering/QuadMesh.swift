import MetalKit
import ModelIO

/// Unit rectangle centered in local XY, at Z = 0, with a +Z normal.
/// UVs run from (0, 0) at bottom-left to (1, 1) at top-right.
enum QuadMesh {
    static func make(device: MTLDevice) throws -> MTKMesh {
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

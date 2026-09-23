import MetalKit
import ModelIO

enum SphereMesh {
    static func make(device: MTLDevice) throws -> MTKMesh {
        let allocator = MTKMeshBufferAllocator(device: device)
        let model = MDLMesh(
            sphereWithExtent: SceneConfiguration.sphereExtent,
            segments: SceneConfiguration.sphereSegments,
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )

        let descriptor = MeshVertexLayout.makeDescriptor()
        model.vertexDescriptor = descriptor
        return try MTKMesh(mesh: model, device: device)
    }
}

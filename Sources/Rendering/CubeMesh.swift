import MetalKit
import ModelIO

enum CubeMesh {
    static func make(device: MTLDevice) throws -> MTKMesh {
        let allocator = MTKMeshBufferAllocator(device: device)
        let model = MDLMesh(boxWithExtent: SceneConfiguration.cubeExtent,
                            segments: SceneConfiguration.cubeSegments,
                            inwardNormals: false,
                            geometryType: .triangles,
                            allocator: allocator
        )

        let descriptor = MeshVertexLayout.makeDescriptor()
        model.vertexDescriptor = descriptor
        return try MTKMesh(mesh: model, device: device)
    }
}

import ModelIO

/// Packed position/normal/UV in mesh buffer 0. Uniforms occupy buffer 1.
enum MeshVertexLayout {
    static let stride = 32

    static func makeDescriptor() -> MDLVertexDescriptor {
        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0
        )
        descriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0
        )
        descriptor.attributes[2] = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: 24, bufferIndex: 0
        )
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: stride)
        return descriptor
    }
}

import MetalKit
import simd

/// Test the real floor shader with independent materials and a float target.
/// Ambient-only fixtures isolate its checker from the separately tested lighting.
enum FloorChecks {
    static func run(device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary) throws {
        let mesh = try QuadMesh.make(device: device)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "scene_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "floor_fragment")
        descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let material = FloorUniforms(colorA: [0.13, 0.27, 0.41, 1], colorB: [0.61, 0.55, 0.23, 1], checkerSize: 1)

        func draw(
            point: SIMD2<Float>, height: Float = 2, pitch: Float = .pi / 2,
            floorOffset: SIMD3<Float> = .zero, checkerSize: Float = 1, size: Int = 65
        ) throws -> SIMD4<Float> {
            let eye = SIMD3(point.x, height, point.y - height / tan(pitch))
            let cameraWorld = Transforms.rotateX(pitch) * Transforms.translation(eye)
            let model = ObjectPlacement(position: floorOffset, scale: [10000, 10000, 1], pitch: -.pi / 2).modelMatrix
            let uniforms = ShaderUniforms(
                modelMatrix: model, viewMatrix: simd_inverse(cameraWorld),
                projectionMatrix: Transforms.perspective(aspect: 1, fieldOfView: .pi / 2, near: 0.01, far: 5000),
                normalMatrix: Transforms.normalMatrix(for: model), color: [0.99, 0.01, 0.01, 1],
                lightColor: SIMD4(repeating: 1), lightPositionWorld: [0, 4, 0, 1], eyeWorld: SIMD4(eye, 1),
                ambientIntensity: 1, diffuseIntensity: 0, specularIntensity: 0, specularShininess: 20,
                fillLightDirectionWorld: [0, 1, 0, 0], fillIntensity: 0)
            var floor = material
            floor.checkerSize = checkerSize
            return try LightingChecks.sample(device: device, queue: queue, mesh: mesh, pipeline: pipeline,
                                             uniforms: uniforms, floorUniforms: floor, size: size)
        }
        func expectColor(_ actual: SIMD4<Float>, _ expected: SIMD4<Float>, _ message: String, tolerance: Float = 0.001) throws {
            try SmokeTests.expect((0..<4).allSatisfy { actual[$0].isFinite }, "\(message) produced nonfinite output.")
            try SmokeTests.expect(simd_length(actual - expected) < tolerance,
                                  "\(message): got \(actual), expected \(expected).")
        }

        for size in [33, 65, 129] {
            // Close, fully covered squares must retain both editable tones.
            let squareSamples: [(SIMD2<Float>, SIMD4<Float>)] = [
                ([0.25, 0.25], material.colorA), ([1.25, 0.25], material.colorB),
                ([-0.25, 0.25], material.colorB), ([-0.25, -0.25], material.colorA)
            ]
            for (point, expected) in squareSamples {
                try expectColor(draw(point: point, size: size), expected, "Near checker at \(point), \(size)px")
            }
            try expectColor(draw(point: [1.25, 0.25], checkerSize: 2, size: size), material.colorA,
                            "Checker size is world units per square")
            try expectColor(draw(point: [0.25, 0.25], floorOffset: [0.37, 0, -0.28], size: size), material.colorA,
                            "Moving the mesh must not move the world-anchored pattern")
            try expectColor(draw(point: [0.25, 0.25], height: 0.8, pitch: .pi / 4, size: size), material.colorA,
                            "Moving the camera must not move the world-anchored pattern")
        }

        let average = (material.colorA + material.colorB) * 0.5
        // A pixel centered on an edge covers the two neighboring squares equally.
        try expectColor(draw(point: [1, 0.25]), average, "Checker boundary coverage")
        for size in [33, 65, 129] {
            // Many checks per pixel must converge toward the mean, including at a
            // grazing angle where the footprint is stretched mostly in one axis.
            for shift: Float in [0, 0.17, 0.53] {
                try expectColor(draw(point: [0.25 + shift, -0.25], height: 2000, size: size), average,
                                "Distant minification at \(size)px", tolerance: 0.005)
                try expectColor(draw(point: [0.25 + shift, -0.25], height: 3, pitch: 0.04, size: size), average,
                                "Oblique minification at \(size)px", tolerance: 0.035)
            }
        }
        print("PASS: floor tones/scale, negative coordinates, world anchoring, edge coverage, finite filtered minification, and resizing")
    }
}

import MetalKit
import simd

/// Exercises the actual offscreen scene pass and its sampled right-hand preview.
enum TexturePassChecks {
    @MainActor
    static func run(view: MTKView, library: MTLLibrary, device: MTLDevice, queue: MTLCommandQueue) throws {
        let quad = try QuadMesh.make(device: device)
        // Equal rigid frames make the mapping identity, while unequal visual scales
        // keep a tiny entrance and an opaque exit that would otherwise hide the scene.
        let objects = [
            RenderObject(id: .entrance, mesh: quad,
                placement: ObjectPlacement(position: [0, 0, 2], scale: [0.01, 0.01, 1])),
            RenderObject(id: .exit, mesh: quad,
                placement: ObjectPlacement(position: [0, 0, 2], scale: [20, 20, 1])),
            RenderObject(id: .quad, mesh: quad,
                placement: ObjectPlacement(position: [0, 0, 1], scale: [20, 20, 1])),
            RenderObject(id: .sphere, mesh: quad,
                placement: ObjectPlacement(position: [-0.38, 0.48, 3], scale: [0.35, 0.28, 1], yaw: .pi)),
            RenderObject(id: .player, mesh: quad,
                placement: ObjectPlacement(position: [0.36, -0.38, 3], scale: [0.27, 0.45, 1], yaw: .pi)),
            // Draw the large background LAST: correct foreground colors require depth.
            RenderObject(id: .cube, mesh: quad,
                placement: ObjectPlacement(position: [0, 0, 5], scale: [20, 20, 1], yaw: .pi))
        ]
        let renderer = try Renderer(view: view, library: library, objects: objects)
        var previousColor: MTLTexture?
        var previousDepth: MTLTexture?
        for (width, height) in [(512, 512), (800, 400), (400, 800), (801, 401), (512, 512)] {
            let frame = try SmokeTests.render(renderer, device: device, queue: queue, width: width, height: height)
            guard let color = renderer.mappedColorTexture, let depth = renderer.mappedDepthTexture else {
                throw SmokeTests.Failure(description: "The mapped scene did not allocate its render targets.")
            }
            let textureWidth = width / 2
            try SmokeTests.expect(color.width == textureWidth && color.height == height
                && depth.width == textureWidth && depth.height == height,
                "Mapped targets must match the source viewport's pixel dimensions.")
            try SmokeTests.expect(color.pixelFormat == .bgra8Unorm && depth.pixelFormat == .depth32Float
                && color.sampleCount == 1 && depth.sampleCount == 1,
                "Mapped targets must use matching single-sample color/depth formats.")
            try SmokeTests.expect(color.usage.contains(.renderTarget) && color.usage.contains(.shaderRead)
                && depth.usage.contains(.renderTarget), "Mapped target usage must permit rendering and sampling.")
            if let previousColor, let previousDepth {
                try SmokeTests.expect(color !== previousColor && depth !== previousDepth,
                    "A viewport size change must replace both mapped targets.")
            }
            let texturePixels = try read(color, device: device, queue: queue)
            try checkMarker(texturePixels, width: textureWidth, height: height,
                position: [-0.38, 0.48, 3], material: SceneConfiguration.sceneObjectColor)
            try checkMarker(texturePixels, width: textureWidth, height: height,
                position: [0.36, -0.38, 3], material: SceneConfiguration.mappedPlayerColor)
            try checkPreview(frame, width: width, height: height, texture: texturePixels, textureWidth: textureWidth)

            // The source pass still draws the user's quad; only the capture excludes it.
            let sourceCenter = ((height / 2) * width + textureWidth / 2) * 4
            let sourcePoint = worldPoint(pixelX: textureWidth / 2, pixelY: height / 2,
                                         width: textureWidth, height: height, depth: 1)
            let sourceExpected = SmokeTests.lightingBytes(pointWorld: sourcePoint, normalWorld: [0, 0, 1],
                eyeWorld: .zero, materialColor: SceneConfiguration.sceneObjectColor)
            try SmokeTests.expect((0..<4).allSatisfy { abs(Int(frame[sourceCenter + $0]) - sourceExpected[$0]) <= 2 },
                                  "The source scene must retain its ordinary quad draw.")

            let second = try SmokeTests.render(renderer, device: device, queue: queue, width: width, height: height)
            try SmokeTests.expect(renderer.mappedColorTexture === color && renderer.mappedDepthTexture === depth,
                                  "Stable dimensions must reuse the color and depth textures.")
            try SmokeTests.expect(frame == second, "The mapped texture preview changed at rest.")
            previousColor = color
            previousDepth = depth
        }
        print("PASS: mapped color/depth pass, excluded preview surfaces, orientation, sampling, resize, and resource reuse")
    }

    static func worldPoint(pixelX: Int, pixelY: Int, width: Int, height: Int, depth: Float) -> SIMD3<Float> {
        let slope = tan(SceneConfiguration.fieldOfViewRadians / 2)
        let ndcX = (Float(pixelX) + 0.5) / Float(width) * 2 - 1
        let ndcY = 1 - (Float(pixelY) + 0.5) / Float(height) * 2
        return [ndcX * Float(width) / Float(height) * slope * depth, ndcY * slope * depth, depth]
    }

    static func checkMarker(
        _ pixels: [UInt8], width: Int, height: Int, position: SIMD3<Float>, material: SIMD4<Float>
    ) throws {
        let slope = tan(SceneConfiguration.fieldOfViewRadians / 2)
        let ndcX = position.x / (position.z * slope * Float(width) / Float(height))
        let ndcY = position.y / (position.z * slope)
        let x = Int(floor((ndcX + 1) * 0.5 * Float(width)))
        let y = Int(floor((1 - ndcY) * 0.5 * Float(height)))
        try SmokeTests.expect((0..<width).contains(x) && (0..<height).contains(y),
                              "The mapped texture marker left the test viewport.")
        let point = worldPoint(pixelX: x, pixelY: y, width: width, height: height, depth: position.z)
        let expected = SmokeTests.lightingBytes(pointWorld: point, normalWorld: [0, 0, -1],
                                              eyeWorld: .zero, materialColor: material)
        let index = (y * width + x) * 4
        try SmokeTests.expect((0..<4).allSatisfy { abs(Int(pixels[index + $0]) - expected[$0]) <= 3 },
            "Mapped marker color/depth failed at \(x),\(y): got \(Array(pixels[index..<(index + 4)])), expected \(expected).")
    }

    static func checkPreview(
        _ frame: [UInt8], width: Int, height: Int, texture: [UInt8], textureWidth: Int
    ) throws {
        let previewWidth = width - textureWidth
        for y in 0..<height {
            for x in 0..<previewWidth {
                // UV at the output pixel center; texel centers lie at n + 0.5.
                // Height is unchanged, so only odd-width previews interpolate in X.
                let texelX = (Float(x) + 0.5) * Float(textureWidth) / Float(previewWidth) - 0.5
                let left = Int(floor(texelX))
                let fraction = texelX - Float(left)
                let x0 = min(max(left, 0), textureWidth - 1)
                let x1 = min(max(left + 1, 0), textureWidth - 1)
                let source0 = (y * textureWidth + x0) * 4
                let source1 = (y * textureWidth + x1) * 4
                let destination = (y * width + textureWidth + x) * 4
                for channel in 0..<4 {
                    let expected = Float(texture[source0 + channel]) * (1 - fraction)
                        + Float(texture[source1 + channel]) * fraction
                    try SmokeTests.expect(abs(Float(frame[destination + channel]) - expected) <= 2,
                        "Texture preview orientation/filtering mismatch at \(x),\(y), channel \(channel).")
                }
            }
        }
    }

    static func read(_ texture: MTLTexture, device: MTLDevice, queue: MTLCommandQueue) throws -> [UInt8] {
        let bytesPerRow = ((texture.width * 4 + 255) / 256) * 256
        guard let buffer = device.makeBuffer(length: bytesPerRow * texture.height, options: .storageModeShared),
              let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
            throw SmokeTests.Failure(description: "Could not read the mapped texture.")
        }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: buffer,
            destinationOffset: 0, destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: bytesPerRow * texture.height)
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        try SmokeTests.expect(command.status == .completed, "Mapped texture readback did not complete.")
        let bytes = buffer.contents().assumingMemoryBound(to: UInt8.self)
        var result: [UInt8] = []
        result.reserveCapacity(texture.width * texture.height * 4)
        for y in 0..<texture.height {
            result.append(contentsOf: UnsafeBufferPointer(start: bytes + y * bytesPerRow, count: texture.width * 4))
        }
        return result
    }
}

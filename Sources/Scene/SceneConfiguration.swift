import Metal
import simd

/// Start here when changing the scene. RGBA components use the 0...1 range.
enum SceneConfiguration {
    // False fills the window with the main view. True restores the right preview.
    // The mapped camera still renders the entrance texture in either mode.
    static let showsMappedPreview = true
    // Draw the mapped camera's frustum in the main scene, outside its own capture.
    static let showsMappedFOV = true
    // Extra occlusion/clipping probes are opt-in, separately from the FOV.
    static let showsDiagnosticObjects = true

    // Opaque role palette, authored for direct .bgra8Unorm output (no sRGB transfer).
    // The FOV is unlit and deliberately dimmer than the solid objects.
    static let backgroundColor = MTLClearColor(red: 24.0 / 255, green: 24.0 / 255, blue: 27.0 / 255, alpha: 1)
    // Pale cool solids, blue portals, and teal mapped representations.
    static let sceneObjectColor = SIMD4<Float>(0.54, 0.59, 0.64, 1.0)
    static let portalColor = SIMD4<Float>(0.38, 0.49, 0.64, 1.0)
    static let mappedPlayerColor = SIMD4<Float>(0.38, 0.65, 0.58, 1.0)
    static let mappedFOVColor = SIMD4<Float>(0.14, 0.27, 0.25, 1.0)
    // Two nearby material tones, shaded by the same neutral scene lighting.
    static let floorColorA = SIMD4<Float>(0.125, 0.14, 0.165, 1)
    static let floorColorB = SIMD4<Float>(0.14, 0.155, 0.18, 1)
    static let floorCheckerSize: Float = 1 // World units per square, in world XZ.

    static let lightColor = SIMD4<Float>(repeating: 1.0)
    // A neutral, elevated main light, fixed in world space. No distance falloff.
    static let lightPositionWorld = SIMD4<Float>(-3, 5, -1, 1)
    // Ambient retains the darkest faces; diffuse carries the main light's shape.
    static let ambientIntensity: Float = 0.38
    static let diffuseIntensity: Float = 0.85
    // A broad, restrained Blinn–Phong highlight leaves the material color visible.
    static let specularIntensity: Float = 0.045
    static let specularShininess: Float = 20
    // Weak diffuse-only fill from the opposite side separates rear-facing planes.
    // This is a world-space direction TOWARD the light, not a position (w = 0).
    static let fillLightDirectionWorld = SIMD4<Float>(2, 3, 5, 0)
    static let fillIntensity: Float = 0.22

    static let sphereExtent = SIMD3<Float>(repeating: 0.75)
    static let sphereSegments = SIMD2<UInt32>(30, 30)

    static let torusMajorRadius: Float = 0.5
    static let torusTubeRadius: Float = 0.16
    static let torusRingSegments = 64
    static let torusTubeSegments = 24

    static let cubeSegments = SIMD3<UInt32>(1, 1, 1)
    static let cubeExtent = SIMD3<Float>(repeating: 1.0)

    // Portal placements are world-space; player placement is source-camera-local.
    // Equal 2 x 3 openings rest on the floor. The 60-degree exit makes the
    // connection visibly directional without relying on a half-turn arrangement.
    static let entrancePlacement = ObjectPlacement(position: [0, 0, 3], scale: [2, 3, 0.1])
    static let exitPlacement = ObjectPlacement(position: [4.8, 0, 6], scale: [2, 3, 0.1], yaw: .pi / 3)
    static let playerPlacement = ObjectPlacement(scale: [0.01, 0.01, 0.01], yaw: .pi / 2)

    // One flat quad, extending beyond the usual view without a slab edge.
    static let floorHeight: Float = -1.5
    static let floorCenterXZ = SIMD2<Float>(1, 5)
    static let floorSize: Float = 200
    static let portalBoundaryWidth: Float = 0.012

    static var floorPlacement: ObjectPlacement {
        // QuadMesh lies in XY with normal +Z. -90 degrees around X makes it
        // horizontal with normal +Y; the last scale stays nonzero for normals.
        ObjectPlacement(position: [floorCenterXZ.x, floorHeight, floorCenterXZ.y],
                        scale: [floorSize, floorSize, 1], pitch: -.pi / 2)
    }

    // World-space landmarks near the source opening exercise ordinary depth:
    // the foreground block can cover the quad; the rear block is hidden by it.
    static let foregroundBlockPlacement = ObjectPlacement(
        position: [-1.4, -0.95, 1.8], scale: [0.6, 1.1, 0.6], yaw: 0.3)
    static let rearBlockPlacement = ObjectPlacement(
        position: [1.25, -0.85, 4.6], scale: [0.65, 1.3, 0.65], yaw: -0.3)

    // These positions are EXIT-LOCAL: X across the opening, Y up, +Z beyond it.
    // Convert once during scene construction so moving the exit carries its set
    // of landmarks along. They become ordinary world objects, not mapped clones.
    static var exitBlockPlacement: ObjectPlacement {
        placement(in: exitPlacement, at: [-0.65, -1, 1.8], scale: [0.75, 1, 0.75])
    }

    static var diagnosticExitPlacements: [(id: ObjectID, placement: ObjectPlacement)] {
        [
            (.farPillar, placement(in: exitPlacement, at: [-0.4, -0.1, 5], scale: [0.45, 2.8, 0.45])),
            (.edgePillar, placement(in: exitPlacement, at: [1.35, -0.4, 0.65], scale: [0.16, 2.2, 0.16])),
            // Negative Z is on the virtual-eye side of the exit. This low block
            // is an intentional probe for the exit-plane clipping step still to come.
            (.nearSideProbe, placement(in: exitPlacement, at: [-1.45, -1.15, -0.6], scale: [0.45, 0.7, 0.45]))
        ]
    }

    static var exitSpherePlacement: ObjectPlacement {
        // Model I/O's sphere extent is its radius; this makes a 1.2-unit ball.
        placement(in: exitPlacement, at: [0.7, -0.9, 3.6],
                  scale: SIMD3<Float>(repeating: 0.6) / sphereExtent)
    }

    static var exitTorusPlacement: ObjectPlacement {
        // Negative exit-local Z is opposite the cube and sphere. Keep the whole
        // tube on that side, with its bottom resting on the same ground plane.
        let centerY = floorHeight - exitPlacement.position.y + torusMajorRadius + torusTubeRadius
        return placement(in: exitPlacement, at: [2.2, centerY, -1.5], scale: [1, 1, 1])
    }

    static func portalBoundaryPlacements(for portal: ObjectPlacement) -> [ObjectPlacement] {
        let width = portal.scale.x, height = portal.scale.y, line = portalBoundaryWidth
        // Flat strips sit immediately outside the aperture at local Z = 0.
        // They share QuadMesh with the opening; no depth, bevel or inset frame.
        return [
            placement(in: portal, at: [-(width + line) / 2, 0, 0], scale: [line, height + 2 * line, 1]),
            placement(in: portal, at: [(width + line) / 2, 0, 0], scale: [line, height + 2 * line, 1]),
            placement(in: portal, at: [0, (height + line) / 2, 0], scale: [width, line, 1]),
            placement(in: portal, at: [0, -(height + line) / 2, 0], scale: [width, line, 1])
        ]
    }

    /// Local offsets use the rigid frame, so opening size never stretches them.
    /// Each piece inherits the frame's yaw/pitch; scale is only its own visual size.
    private static func placement(
        in frame: ObjectPlacement, at localPosition: SIMD3<Float>, scale: SIMD3<Float>
    ) -> ObjectPlacement {
        let world = SIMD4<Float>(localPosition, 1) * frame.rigidFrame
        return ObjectPlacement(position: [world.x, world.y, world.z], scale: scale,
                               yaw: frame.yaw, pitch: frame.pitch)
    }

    // Shared by the camera projection and its FOV outline. FOV is vertical;
    // near/far are distances from the eye along camera-local +Z, in world units.
    static let fieldOfViewRadians: Float = 70 * .pi / 180
    static let nearPlane: Float = 0.1
    static let farPlane: Float = 100
    static let cameraSpeed: Float = 1.5
    static let mouseSensitivity: Float = 0.01
}

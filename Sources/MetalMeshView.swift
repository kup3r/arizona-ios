import SwiftUI
import MetalKit
import simd

private struct Mesh: Decodable {
    let positions: [[Float]]
    let normals: [[Float]]
    let triangles: [[UInt32]]
}

private struct Uniforms {
    var mvp: simd_float4x4
    var model: simd_float4x4
}

struct MetalMeshView: UIViewRepresentable {
    let active: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColorMake(0.035, 0.045, 0.07, 1)
        view.preferredFramesPerSecond = 30
        view.isPaused = !active
        do {
            try context.coordinator.configure(view)
            view.isAccessibilityElement = true
            view.accessibilityIdentifier = "mesh-ready"
            view.accessibilityLabel = "3D-модель загружена"
            view.delegate = context.coordinator
            view.addGestureRecognizer(UIPanGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.pan(_:))))
        } catch {
            view.isPaused = true
            let label = UILabel()
            label.accessibilityIdentifier = "mesh-error"
            label.text = "Не удалось открыть модель: \(error.localizedDescription)"
            label.textColor = .white
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        view.isPaused = !active || !context.coordinator.ready
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        private var pipeline: MTLRenderPipelineState?
        private var depthState: MTLDepthStencilState?
        private var queue: MTLCommandQueue?
        private var vertices: MTLBuffer?
        private var indices: MTLBuffer?
        private var indexCount = 0
        private var yaw: Float = 0.5
        private var pitch: Float = 0.1
        private(set) var ready = false

        private func fail(_ message: String) -> NSError {
            NSError(domain: "ResourceLab", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
        }

        func configure(_ view: MTKView) throws {
            guard let device = view.device, let queue = device.makeCommandQueue() else {
                throw fail("Metal недоступен")
            }
            guard let url = Bundle.main.url(forResource: "mesh", withExtension: "json") else {
                throw fail("mesh.json отсутствует в ресурсах приложения")
            }
            let mesh = try JSONDecoder().decode(Mesh.self, from: Data(contentsOf: url))
            guard !mesh.positions.isEmpty, mesh.positions.count <= 1_000_000,
                  mesh.normals.count == mesh.positions.count,
                  !mesh.triangles.isEmpty, mesh.triangles.count <= 2_000_000,
                  mesh.positions.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite } }),
                  mesh.normals.allSatisfy({ $0.count == 3 && $0.allSatisfy { $0.isFinite } }),
                  mesh.triangles.allSatisfy({ $0.count == 3 && $0.allSatisfy { Int($0) < mesh.positions.count } }) else {
                throw fail("Некорректная геометрия")
            }
            var packed: [SIMD4<Float>] = []
            for (p, n) in zip(mesh.positions, mesh.normals) {
                packed.append(SIMD4(p[0], p[1], p[2], 1))
                packed.append(SIMD4(n[0], n[1], n[2], 0))
            }
            let flatIndices = mesh.triangles.flatMap { $0 }
            self.vertices = packed.withUnsafeBufferPointer {
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)
            }
            self.indices = flatIndices.withUnsafeBufferPointer {
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
            }
            guard vertices != nil, indices != nil else { throw fail("Нет памяти для модели") }
            indexCount = flatIndices.count
            self.queue = queue
            let library = try device.makeLibrary(source: Self.shaders, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "meshVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "meshFragment")
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            let depth = MTLDepthStencilDescriptor()
            depth.depthCompareFunction = .less
            depth.isDepthWriteEnabled = true
            depthState = device.makeDepthStencilState(descriptor: depth)
            ready = true
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let delta = gesture.translation(in: gesture.view)
            yaw += Float(delta.x) * 0.01
            pitch = min(1.3, max(-1.3, pitch + Float(delta.y) * 0.01))
            gesture.setTranslation(.zero, in: gesture.view)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard ready, view.drawableSize.width > 0, view.drawableSize.height > 0,
                  let pipeline = pipeline, let vertices = vertices, let indices = indices,
                  let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let command = queue?.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
            let model = Self.rotationY(yaw) * Self.rotationX(pitch)
            var camera = matrix_identity_float4x4
            camera.columns.3.z = -3.5
            let projection = Self.perspective(aspect: Float(view.drawableSize.width / view.drawableSize.height))
            var uniforms = Uniforms(mvp: projection * camera * model, model: model)
            encoder.setRenderPipelineState(pipeline)
            encoder.setDepthStencilState(depthState)
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(vertices, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount,
                indexType: .uint32, indexBuffer: indices, indexBufferOffset: 0)
            encoder.endEncoding()
            command.present(drawable)
            command.commit()
        }

        private static func rotationY(_ a: Float) -> simd_float4x4 {
            let c = cos(a), s = sin(a)
            return simd_float4x4(columns: (
                SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0),
                SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1)))
        }
        private static func rotationX(_ a: Float) -> simd_float4x4 {
            let c = cos(a), s = sin(a)
            return simd_float4x4(columns: (
                SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0),
                SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1)))
        }
        private static func perspective(aspect: Float) -> simd_float4x4 {
            let y: Float = 1 / tan(Float.pi / 7), x = y / aspect
            let near: Float = 0.1, far: Float = 100
            let z = far / (near - far)
            return simd_float4x4(columns: (
                SIMD4(x, 0, 0, 0), SIMD4(0, y, 0, 0),
                SIMD4(0, 0, z, -1), SIMD4(0, 0, near * z, 0)))
        }

        private static let shaders = """
        #include <metal_stdlib>
        using namespace metal;
        struct Uniforms { float4x4 mvp; float4x4 model; };
        struct Varying { float4 position [[position]]; float3 normal; };
        vertex Varying meshVertex(uint id [[vertex_id]],
            device const float4 *data [[buffer(0)]],
            constant Uniforms &u [[buffer(1)]]) {
            Varying o;
            o.position = u.mvp * data[id * 2];
            o.normal = (u.model * data[id * 2 + 1]).xyz;
            return o;
        }
        fragment float4 meshFragment(Varying in [[stage_in]]) {
            float diffuse = abs(dot(normalize(in.normal), normalize(float3(0.4, 0.8, 1.0))));
            return float4(float3(0.24, 0.70, 0.95) * (0.22 + 0.78 * diffuse), 1.0);
        }
        """
    }
}

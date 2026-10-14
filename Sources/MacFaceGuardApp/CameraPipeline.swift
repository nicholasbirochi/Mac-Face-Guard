import Foundation
@preconcurrency import AVFoundation
import Vision
import CoreImage
import QuartzCore

// Vision e AVCaptureSession permanecem na fila serial; só observações imutáveis cruzam para a UI.
struct FrameAnalysis: @unchecked Sendable {
    let run: UUID
    let count: Int
    let quality: Float
    let yaw: Double
    let print: VNFeaturePrintObservation?
    let capturedAt: TimeInterval
    let message: String
}

final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "MacFaceGuard.camera", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var run: UUID?
    private var lastAnalysis: TimeInterval = 0
    private var lastTimestamp = CMTime.invalid
    private var callback: (@Sendable (FrameAnalysis) -> Void)?

    func start(run: UUID, callback: @escaping @Sendable (FrameAnalysis) -> Void) {
        queue.async { [self] in
            stopOnQueue()
            self.run = run
            self.callback = callback
            do {
                guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                    throw GuardError.message("A câmera não foi autorizada.")
                }
                let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                    mediaType: .video, position: .unspecified).devices
                guard let device = devices.first(where: { !$0.isSuspended }) else {
                    throw GuardError.message("Câmera integrada indisponível. Câmeras externas e virtuais não são usadas.")
                }
                session.beginConfiguration()
                session.sessionPreset = .vga640x480
                let input: AVCaptureDeviceInput
                do { input = try AVCaptureDeviceInput(device: device) }
                catch { session.commitConfiguration(); throw error }
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: queue)
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    throw GuardError.message("Não foi possível configurar a câmera integrada.")
                }
                session.addInput(input)
                session.addOutput(output)
                session.commitConfiguration()
                session.startRunning()
                guard session.isRunning else { throw GuardError.message("A câmera não iniciou.") }
            } catch {
                let message = (error as? GuardError)?.localizedDescription ?? "Falha ao abrir a câmera. Verifique a permissão nos Ajustes do Sistema."
                callback(FrameAnalysis(run: run, count: -1, quality: 0, yaw: 0, print: nil,
                    capturedAt: CACurrentMediaTime(), message: message))
                stopOnQueue()
            }
        }
    }

    func stop() { queue.async { self.stopOnQueue() } }

    private func stopOnQueue() {
        run = nil
        callback = nil
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        session.commitConfiguration()
        lastAnalysis = 0
        lastTimestamp = .invalid
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard let run, let callback, now - lastAnalysis >= 0.5 else { return }
        lastAnalysis = now
        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
        guard timestamp.isValid, !lastTimestamp.isValid || timestamp > lastTimestamp,
              let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        lastTimestamp = timestamp
        autoreleasepool {
            do {
                let faces = VNDetectFaceLandmarksRequest()
                let qualityRequest = VNDetectFaceCaptureQualityRequest()
                let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
                try handler.perform([faces, qualityRequest])
                let observations = faces.results ?? []
                guard observations.count == 1, let face = observations.first else {
                    callback(FrameAnalysis(run: run, count: observations.count, quality: 0, yaw: 0, print: nil,
                        capturedAt: now, message: observations.isEmpty ? "Posicione seu rosto na área da câmera." : "Mantenha apenas um rosto na imagem."))
                    return
                }
                let quality = qualityRequest.results?.first?.faceCaptureQuality ?? 0
                let box = face.boundingBox
                let enoughSize = box.width > 0.18 && box.height > 0.22
                let inside = box.minX > 0.03 && box.maxX < 0.97 && box.minY > 0.03 && box.maxY < 0.97
                guard enoughSize, inside, quality >= 0.25, let yaw = face.yaw?.doubleValue else {
                    callback(FrameAnalysis(run: run, count: 1, quality: quality, yaw: 0, print: nil,
                        capturedAt: now, message: "Aproxime-se, centralize o rosto e procure luz uniforme."))
                    return
                }
                let image = CIImage(cvPixelBuffer: pixels)
                let rect = VNImageRectForNormalizedRect(box, Int(image.extent.width), Int(image.extent.height))
                guard let crop = context.createCGImage(image, from: rect.integral.intersection(image.extent)) else {
                    throw GuardError.message("Não foi possível analisar o quadro.")
                }
                let request = VNGenerateImageFeaturePrintRequest()
                request.revision = VNGenerateImageFeaturePrintRequestRevision2
                try VNImageRequestHandler(cgImage: crop, orientation: .up).perform([request])
                guard let feature = request.results?.first as? VNFeaturePrintObservation else {
                    throw GuardError.message("Comparação visual indisponível.")
                }
                callback(FrameAnalysis(run: run, count: 1, quality: quality, yaw: yaw, print: feature,
                    capturedAt: now, message: "Rosto detectado. Siga a orientação ao lado."))
            } catch {
                callback(FrameAnalysis(run: run, count: 0, quality: 0, yaw: 0, print: nil,
                    capturedAt: now, message: "A análise deste quadro falhou. Nenhuma autorização foi concedida."))
            }
        }
    }
}

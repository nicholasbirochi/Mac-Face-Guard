import Foundation
@preconcurrency import AVFoundation
import Vision
import QuartzCore
import MacFaceGuardCore

// Vision e AVCaptureSession permanecem na fila serial; só observações imutáveis cruzam para a UI.
struct FrameAnalysis: @unchecked Sendable {
    let run: UUID
    let count: Int
    let quality: Float
    let yaw: Double
    let turn: Double?
    let embedding: [Float]?
    let capturedAt: TimeInterval
    let message: String
}

final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "MacFaceGuard.camera", qos: .userInitiated)
    private var run: UUID?
    private var lastAnalysis: TimeInterval = 0
    private var lastTimestamp = CMTime.invalid
    private var callback: (@Sendable (FrameAnalysis) -> Void)?
    private var extractor: EdgeFaceExtractor?

    func start(run: UUID, extractor: EdgeFaceExtractor, callback: @escaping @Sendable (FrameAnalysis) -> Void) {
        queue.async { [self] in
            stopOnQueue()
            self.run = run
            self.callback = callback
            self.extractor = extractor
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
                callback(FrameAnalysis(run: run, count: -1, quality: 0, yaw: 0, turn: nil, embedding: nil,
                    capturedAt: CACurrentMediaTime(), message: message))
                stopOnQueue()
            }
        }
    }

    func stop() { queue.async { self.stopOnQueue() } }

    private func stopOnQueue() {
        run = nil
        callback = nil
        extractor = nil
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
        guard let run, let callback, let extractor, now - lastAnalysis >= 0.5 else { return }
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
                let detected = faces.results ?? []
                let observations = FaceGeometry.uniqueFaceIndices(detected.map(\.boundingBox)).map { detected[$0] }
                guard observations.count == 1, let face = observations.first else {
                    callback(FrameAnalysis(run: run, count: observations.count, quality: 0, yaw: 0, turn: nil, embedding: nil,
                        capturedAt: now, message: observations.isEmpty ? "Posicione seu rosto na área da câmera." : "Mantenha apenas um rosto na imagem."))
                    return
                }
                let box = face.boundingBox
                func overlap(_ candidate: VNFaceObservation) -> CGFloat {
                    let shared = candidate.boundingBox.intersection(box)
                    return shared.isNull ? 0 : shared.width * shared.height
                }
                let quality = qualityRequest.results?.max(by: { overlap($0) < overlap($1) })?.faceCaptureQuality ?? 0
                let enoughSize = box.width > 0.18 && box.height > 0.22
                let inside = box.minX > 0.03 && box.maxX < 0.97 && box.minY > 0.03 && box.maxY < 0.97
                let yaw = face.yaw?.doubleValue
                // Qualidade do Vision penaliza poses laterais; o cadastro experimental aceita uma virada pequena.
                guard enoughSize, inside, quality >= 0.10, let yaw, yaw.isFinite else {
                    let message = !enoughSize ? "Aproxime um pouco o rosto." : !inside ? "Mantenha o rosto inteiro dentro da imagem." : quality < 0.10 ? "Procure mais luz no rosto e vire só um pouco." : "Olhe de frente por um instante para localizar o rosto."
                    callback(FrameAnalysis(run: run, count: 1, quality: quality, yaw: yaw ?? 0, turn: nil, embedding: nil,
                        capturedAt: now, message: message))
                    return
                }
                var turn: Double?
                if let landmarks = face.landmarks,
                   let nose = averageX(landmarks.nose),
                   let left = averageX(landmarks.leftEye), let right = averageX(landmarks.rightEye) {
                    turn = FaceGeometry.noseOffset(nose: nose, leftEye: left, rightEye: right)
                }
                let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
                guard let landmarks = face.landmarks,
                      let points = fivePoints(landmarks, width: width, height: height),
                      let transform = try? FaceAlignment.transform(from: points) else {
                    callback(FrameAnalysis(run: run, count: 1, quality: quality, yaw: yaw, turn: turn, embedding: nil,
                        capturedAt: now, message: "Olhe para a câmera com olhos, nariz e boca visíveis."))
                    return
                }
                guard CVPixelBufferGetPixelFormatType(pixels) == kCVPixelFormatType_32BGRA,
                      CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else {
                    throw GuardError.message("Formato de quadro inesperado.")
                }
                let aligned: [UInt8]
                do {
                    defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
                    guard let base = CVPixelBufferGetBaseAddress(pixels) else { throw AlignmentError.invalidImage }
                    let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
                    aligned = try FaceAlignment.warp(UnsafeRawBufferPointer(start: base, count: rowBytes * height),
                        width: width, height: height, bytesPerRow: rowBytes, transform: transform)
                }
                let embedding = try extractor.embedding(alignedBGRA: aligned)
                callback(FrameAnalysis(run: run, count: 1, quality: quality, yaw: yaw, turn: turn, embedding: embedding,
                    capturedAt: now, message: "Rosto detectado. Siga a orientação ao lado."))
            } catch {
                callback(FrameAnalysis(run: run, count: 0, quality: 0, yaw: 0, turn: nil, embedding: nil,
                    capturedAt: now, message: "A análise deste quadro falhou. Nenhuma autorização foi concedida."))
            }
        }
    }

    /// Pupilas (ou centro dos olhos), ponta do nariz e cantos externos da boca em pixels, origem no topo.
    private func fivePoints(_ landmarks: VNFaceLandmarks2D, width: Int, height: Int) -> FivePoints? {
        let size = CGSize(width: width, height: height)
        func pixels(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint]? {
            guard let points = region?.pointsInImage(imageSize: size), !points.isEmpty else { return nil }
            return points.map { CGPoint(x: $0.x - 0.5, y: CGFloat(height) - $0.y - 0.5) }
        }
        func center(_ points: [CGPoint]) -> CGPoint {
            CGPoint(x: points.reduce(0) { $0 + $1.x } / CGFloat(points.count), y: points.reduce(0) { $0 + $1.y } / CGFloat(points.count))
        }
        guard let leftEye = pixels(landmarks.leftPupil).map(center) ?? pixels(landmarks.leftEye).map(center),
              let rightEye = pixels(landmarks.rightPupil).map(center) ?? pixels(landmarks.rightEye).map(center),
              let nose = pixels(landmarks.noseCrest)?.max(by: { $0.y < $1.y }) ?? pixels(landmarks.nose).map(center),
              let lips = pixels(landmarks.outerLips) else { return nil }
        return try? FivePoints(eyes: (leftEye, rightEye), nose: nose, lips: lips)
    }

    private func averageX(_ region: VNFaceLandmarkRegion2D?) -> Double? {
        guard let points = region?.normalizedPoints, !points.isEmpty else { return nil }
        return points.reduce(0) { $0 + Double($1.x) } / Double(points.count)
    }
}

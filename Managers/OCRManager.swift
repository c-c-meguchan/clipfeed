import AppKit
import Vision
import CoreImage
import Combine

class OCRManager {
    static let shared = OCRManager()
    
    private init() {}
    
    func performOCR(on image: NSImage) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        // CIColorControls でコントラストを上げて認識精度を向上させる
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        let preprocessed: CGImage
        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(1.2, forKey: kCIInputContrastKey)
            if let output = filter.outputImage,
               let processed = context.createCGImage(output, from: output.extent) {
                preprocessed = processed
            } else {
                preprocessed = cgImage
            }
        } else {
            preprocessed = cgImage
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation],
                      error == nil else {
                    continuation.resume(returning: nil)
                    return
                }

                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                let result = recognizedStrings.joined(separator: "\n")
                LogCapture.record("[OCR] result: \(result.isEmpty ? "(empty)" : result)")
                continuation.resume(returning: result.isEmpty ? nil : result)
            }

            request.recognitionLevel = .accurate
            // 言語補正まわりの API は ISO 639 の2文字を期待するため、locale 形式 (ja-JP) ではなく "ja", "en" を指定
            request.recognitionLanguages = ["ja", "en"]
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.01

            let handler = VNImageRequestHandler(cgImage: preprocessed, options: [:])

            do {
                try handler.perform([request])
            } catch {
                LogCapture.record("[OCR] error: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    func performOCR(on pasteboard: NSPasteboard) async -> String? {
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else {
            return nil
        }
        
        return await performOCR(on: image)
    }
}

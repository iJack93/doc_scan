import Flutter
import UIKit
import Vision
import VisionKit
import PhotosUI

public class DocScanPlugin: NSObject, FlutterPlugin, VNDocumentCameraViewControllerDelegate, PHPickerViewControllerDelegate {
    private var flutterResult: FlutterResult?
    private var sourceType: String?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "doc_scan", binaryMessenger: registrar.messenger())
        let instance = DocScanPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        self.flutterResult = result

        switch call.method {
        case "getImage":
            guard let args = call.arguments as? [String: Any],
                  let source = args["source"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Argomenti mancanti o non validi per 'getImage'", details: nil))
                return
            }
            self.sourceType = source
            getImage(from: source)

        case "detectEdges":
            guard let args = call.arguments as? [String: Any],
                  let imagePath = args["imagePath"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Argomento 'imagePath' mancante", details: nil))
                return
            }
            detectEdges(imagePath: imagePath)

        case "applyCropAndSave":
            guard let args = call.arguments as? [String: Any],
                  let imagePath = args["imagePath"] as? String,
                  let quadValues = args["quad"] as? [String: Double],
                  let format = args["format"] as? String,
                  let filter = args["filter"] as? String else { // Nuovo parametro per il filtro
                result(FlutterError(code: "INVALID_ARGS", message: "Argomenti mancanti o non validi per 'applyCropAndSave'", details: nil))
                return
            }
            applyCropAndSave(imagePath: imagePath, quadValues: quadValues, format: format, filter: filter)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Core Logic

    private func getImage(from source: String) {
        guard let root = getRootViewController() else {
            flutterResult?(FlutterError(code: "NO_VIEW_CONTROLLER", message: "Impossibile accedere al root view controller", details: nil))
            return
        }

        if source == "camera" {
            let scannerVC = VNDocumentCameraViewController()
            scannerVC.delegate = self
            root.present(scannerVC, animated: true)
        } else if source == "gallery" {
            if #available(iOS 14, *) {
                var config = PHPickerConfiguration()
                config.selectionLimit = 1
                let pickerVC = PHPickerViewController(configuration: config)
                pickerVC.delegate = self
                root.present(pickerVC, animated: true)
            } else {
                flutterResult?(FlutterError(code: "UNAVAILABLE", message: "La galleria è disponibile solo su iOS 14+", details: nil))
            }
        }
    }

    private func detectEdges(imagePath: String) {
        guard let image = UIImage(contentsOfFile: imagePath) else {
            flutterResult?(FlutterError(code: "FILE_NOT_FOUND", message: "Impossibile caricare l'immagine dal percorso fornito", details: nil))
            return
        }

        let uprightImage = image.forceUprightOrientation()
        guard let cgImage = uprightImage.cgImage else {
            flutterResult?(FlutterError(code: "PROCESSING_ERROR", message: "Impossibile processare l'immagine", details: nil))
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        let request = VNDetectRectanglesRequest { (request, error) in
            guard let observations = request.results as? [VNRectangleObservation], let observation = observations.first else {
                let defaultQuad = Quadrilateral.defaultQuad()
                self.flutterResult?(defaultQuad.toDictionary())
                return
            }
            let quad = Quadrilateral(observation: observation)
            self.flutterResult?(quad.toDictionary())
        }
        request.minimumConfidence = 0.6

        do {
            try requestHandler.perform([request])
        } catch {
            flutterResult?(FlutterError(code: "VISION_ERROR", message: "Errore durante l'analisi dell'immagine", details: error.localizedDescription))
        }
    }

    private func applyCropAndSave(imagePath: String, quadValues: [String: Double], format: String, filter: String) {
        guard let image = UIImage(contentsOfFile: imagePath) else {
            flutterResult?(FlutterError(code: "FILE_NOT_FOUND", message: "Impossibile caricare l'immagine originale", details: nil))
            return
        }

        guard let quad = Quadrilateral(from: quadValues) else {
            flutterResult?(FlutterError(code: "INVALID_ARGS", message: "Coordinate del quadrilatero non valide", details: nil))
            return
        }

        let finalImage = processImage(for: image, with: quad, filter: filter)

        let tempDir = NSTemporaryDirectory()
        let filename = "\(UUID().uuidString).\(format)"
        let finalPath = tempDir.appending(filename)

        var success = false
        if format == "pdf" {
            if let pdfPath = saveImageAsPDF(image: finalImage, at: finalPath) {
                success = true
            }
        } else { // jpeg
            if let data = finalImage.jpegData(compressionQuality: 0.8) {
                do {
                    try data.write(to: URL(fileURLWithPath: finalPath))
                    success = true
                } catch {}
            }
        }

        if success {
            flutterResult?(finalPath)
        } else {
            flutterResult?(FlutterError(code: "SAVE_ERROR", message: "Impossibile salvare il file finale", details: nil))
        }
    }

    // MARK: - Image Processing Helpers

    /// **MODIFICATO**: Applica sia la correzione della prospettiva che il filtro colore.
    private func processImage(for image: UIImage, with quad: Quadrilateral, filter filterName: String) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        let imageSize = ciImage.extent.size

        let perspectiveCorrection = CIFilter(
            name: "CIPerspectiveCorrection",
            parameters: [
                "inputImage": ciImage,
                "inputTopLeft": CIVector(cgPoint: quad.topLeft.scaledForCoreImage(size: imageSize)),
                "inputTopRight": CIVector(cgPoint: quad.topRight.scaledForCoreImage(size: imageSize)),
                "inputBottomLeft": CIVector(cgPoint: quad.bottomLeft.scaledForCoreImage(size: imageSize)),
                "inputBottomRight": CIVector(cgPoint: quad.bottomRight.scaledForCoreImage(size: imageSize))
            ]
        )!

        guard let perspectiveCorrectedImage = perspectiveCorrection.outputImage else {
            return image
        }

        // Applica il filtro colore
        let filteredImage = applyFilter(filterName, to: perspectiveCorrectedImage)

        if let finalCgImage = CIContext().createCGImage(filteredImage, from: filteredImage.extent) {
            return UIImage(cgImage: finalCgImage)
        }

        return image
    }

    /// **NUOVO**: Applica un filtro Core Image a un'immagine.
    private func applyFilter(_ filterName: String, to ciImage: CIImage) -> CIImage {
        switch filterName {
        case "grayscale":
            if let filter = CIFilter(name: "CIPhotoEffectNoir") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                return filter.outputImage ?? ciImage
            }
        case "blackAndWhite":
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(0.0, forKey: kCIInputSaturationKey) // Desatura
                filter.setValue(2.0, forKey: kCIInputContrastKey)   // Aumenta il contrasto
                return filter.outputImage ?? ciImage
            }
        default: // "none" o qualsiasi altro valore
            return ciImage
        }
        return ciImage
    }

    private func saveImageAsPDF(image: UIImage, at path: String) -> String? {
        let pdfData = NSMutableData()
        let pdfConsumer = CGDataConsumer(data: pdfData)!
        var mediaBox = CGRect(origin: .zero, size: image.size)
        guard let pdfContext = CGContext(consumer: pdfConsumer, mediaBox: &mediaBox, nil) else { return nil }
        pdfContext.beginPage(mediaBox: &mediaBox)
        pdfContext.draw(image.cgImage!, in: mediaBox)
        pdfContext.endPage()
        pdfContext.closePDF()
        do {
            try pdfData.write(to: URL(fileURLWithPath: path))
            return path
        } catch { return nil }
    }

    private func saveTempImage(_ image: UIImage) -> String? {
        let tempDir = NSTemporaryDirectory()
        let filename = "\(UUID().uuidString).jpeg"
        let path = tempDir.appending(filename)
        if let data = image.jpegData(compressionQuality: 0.9) {
            do {
                try data.write(to: URL(fileURLWithPath: path))
                return path
            } catch {
                return nil
            }
        }
        return nil
    }

    // MARK: - Delegate Callbacks

    public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        guard scan.pageCount > 0 else {
            controller.dismiss(animated: true) { self.flutterResult?(nil) }
            return
        }
        let image = scan.imageOfPage(at: 0).forceUprightOrientation()
        controller.dismiss(animated: true) {
            if let path = self.saveTempImage(image) {
                self.flutterResult?(path)
            } else {
                self.flutterResult?(FlutterError(code: "SAVE_ERROR", message: "Impossibile salvare l'immagine temporanea", details: nil))
            }
        }
    }

    @available(iOS 14, *)
    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let firstResult = results.first else {
            picker.dismiss(animated: true) { self.flutterResult?(nil) }
            return
        }
        let itemProvider = firstResult.itemProvider
        if itemProvider.canLoadObject(ofClass: UIImage.self) {
            itemProvider.loadObject(ofClass: UIImage.self) { (image, error) in
                DispatchQueue.main.async {
                    picker.dismiss(animated: true) {
                        if let image = (image as? UIImage)?.forceUprightOrientation() {
                            if let path = self.saveTempImage(image) {
                                self.flutterResult?(path)
                            } else {
                                self.flutterResult?(FlutterError(code: "SAVE_ERROR", message: "Impossibile salvare l'immagine temporanea", details: nil))
                            }
                        } else { self.flutterResult?(nil) }
                    }
                }
            }
        } else {
            picker.dismiss(animated: true) { self.flutterResult?(nil) }
        }
    }

    public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true) { self.flutterResult?(nil) }
    }

    // MARK: - Helpers
    private func getRootViewController() -> UIViewController? {
        return UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
    }
}

// MARK: - Helper Structs & Extensions
struct Quadrilateral {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint

    init(topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }

    init(observation: VNRectangleObservation) {
        self.topLeft = observation.topLeft
        self.topRight = observation.topRight
        self.bottomLeft = observation.bottomLeft
        self.bottomRight = observation.bottomRight
    }

    init?(from dictionary: [String: Double]) {
        guard let tl_x = dictionary["topLeftX"], let tl_y = dictionary["topLeftY"],
              let tr_x = dictionary["topRightX"], let tr_y = dictionary["topRightY"],
              let bl_x = dictionary["bottomLeftX"], let bl_y = dictionary["bottomLeftY"],
              let br_x = dictionary["bottomRightX"], let br_y = dictionary["bottomRightY"] else {
            return nil
        }
        self.topLeft = CGPoint(x: tl_x, y: tl_y)
        self.topRight = CGPoint(x: tr_x, y: tr_y)
        self.bottomLeft = CGPoint(x: bl_x, y: bl_y)
        self.bottomRight = CGPoint(x: br_x, y: br_y)
    }

    static func defaultQuad() -> Quadrilateral {
        return Quadrilateral(
            topLeft: CGPoint(x: 0, y: 1),
            topRight: CGPoint(x: 1, y: 1),
            bottomLeft: CGPoint(x: 0, y: 0),
            bottomRight: CGPoint(x: 1, y: 0)
        )
    }

    func toDictionary() -> [String: Double] {
        return [
            "topLeftX": topLeft.x, "topLeftY": topLeft.y,
            "topRightX": topRight.x, "topRightY": topRight.y,
            "bottomLeftX": bottomLeft.x, "bottomLeftY": bottomLeft.y,
            "bottomRightX": bottomRight.x, "bottomRightY": bottomRight.y
        ]
    }
}

extension CGPoint {
    func scaledForCoreImage(size: CGSize) -> CGPoint {
        return CGPoint(x: self.x * size.width, y: self.y * size.height)
    }
}

extension UIImage {
    func forceUprightOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

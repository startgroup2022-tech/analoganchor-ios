import Foundation
import UIKit
import AnalogAnchorKit

/// Camera capture for the analog whiteboard "proof" flow.
///
/// Uses `UIImagePickerController` with `sourceType = .camera` so the user
/// explicitly captures a physical photo. `NSCameraUsageDescription` is required.
/// Images are written to the shared container so a future extension (or the app)
/// can read them; nothing is uploaded.
@MainActor
final class CameraService: NSObject, ObservableObject {

    @Published private(set) var lastCapturedImagePath: String?
    @Published private(set) var lastError: String?

    var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Presents the camera from the given view controller.
    func capturePhoto(from presenter: UIViewController, prefix: String = "proof") {
        guard isCameraAvailable else {
            lastError = "Camera is not available on this device."
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    private func save(image: UIImage, prefix: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            lastError = "Failed to encode captured image."
            return
        }
        let directory = SharedStore.directory().appendingPathComponent("proof", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(prefix)_\(Int(Date().timeIntervalSince1970)).jpg")
        do {
            try data.write(to: url)
            lastCapturedImagePath = url.path
        } catch {
            lastError = "Failed to save proof image: \(error.localizedDescription)"
        }
    }
}

extension CameraService: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    nonisolated func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = info[.originalImage] as? UIImage
        Task { @MainActor in
            picker.dismiss(animated: true)
            if let image {
                self.save(image: image, prefix: "proof")
            }
        }
    }

    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor in
            picker.dismiss(animated: true)
        }
    }
}

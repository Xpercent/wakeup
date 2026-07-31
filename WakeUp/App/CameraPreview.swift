import SwiftUI
import UIKit
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView { let view = PreviewView(); view.session = session; return view }
    func updateUIView(_ uiView: PreviewView, context: Context) { uiView.session = session }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var session: AVCaptureSession? { get { previewLayer.session } set { previewLayer.session = newValue } }
    private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() { super.layoutSubviews(); previewLayer.videoGravity = .resizeAspectFill }
}

//
//  ViewController.swift
//  UVCStreamer
//
//  Created by Dmitry Matyushkin on 06/01/2019.
//  Copyright © 2019 Dmitry Matyushkin. All rights reserved.
//

import Cocoa
import AVFoundation
import CoreGraphics
import Accelerate
import CoreImage

class ViewController: NSViewController, AVCaptureVideoDataOutputSampleBufferDelegate, NSTextFieldDelegate {

    @IBOutlet private weak var videoPanel: NSView!
    @IBOutlet private weak var cameraPopupButton: NSPopUpButton!
    @IBOutlet private weak var imageNameInput: NSTextField!
    @IBOutlet private weak var saveButton: NSButton!
    @IBOutlet private weak var currentBlurLabel: NSTextField!
    @IBOutlet private weak var minBlurInput: NSTextField!
    @IBOutlet private weak var maxBlurInput: NSTextField!
    @IBOutlet private weak var blurMinLabel: NSTextField!
    @IBOutlet private weak var blurMaxLabel: NSTextField!
    
    private let videoQueue = DispatchQueue(label: "VideoProcessingQueue", qos: DispatchQoS.userInteractive, attributes: [], autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.inherit, target: nil)
    private let captureSession = AVCaptureSession()
    private var videoLayer: AVCaptureVideoPreviewLayer?
    private var cameras: [AVCaptureDevice] = [] {
        didSet {
            if let camera = self.cameras.first {
                self.setDevice(device: camera)
            }
            self.cameraPopupButton.removeAllItems()
            self.cameraPopupButton.addItems(withTitles: self.cameras.map({$0.localizedName}))
        }
    }
    private let output = AVCaptureVideoDataOutput()
    private var isSaving: Bool = false
    private var settingsController: VVUVCController?
    private var minBlurValue: Double?
    private var maxBlurValue: Double?
	private var minBlurInputValue: Double?
	private var maxBlurInputValue: Double?

    override func viewDidLoad() {
        super.viewDidLoad()
		self.minBlurInput.delegate = self
		self.maxBlurInput.delegate = self
        self.videoPanel.layer = CALayer()
        let layer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        self.videoPanel.layer?.addSublayer(layer)
        self.videoLayer = layer
        self.output.alwaysDiscardsLateVideoFrames = true
        self.output.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String) : NSNumber(value: kCVPixelFormatType_32BGRA as UInt32)]
        self.captureSession.addOutput(self.output)
        self.output.setSampleBufferDelegate(self, queue: self.videoQueue)
        self.cameras = AVCaptureDevice.devices().filter({$0.hasMediaType(AVMediaType.video)})
    }
    
    private func setDevice(device: AVCaptureDevice) {
        do {            
            self.captureSession.stopRunning()
            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }
            if let uvcController = VVUVCController(deviceIDString: device.uniqueID) {
                self.settingsController = uvcController
                uvcController.openSettingsWindow()
            }
            try self.captureSession.addInput(AVCaptureDeviceInput(device: device))
            self.captureSession.startRunning()
        } catch {
            print(error.localizedDescription)
        }
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }

	func controlTextDidChange(_ obj: Notification) {
		guard let field = obj.object as? NSTextField else { return }
		if field == self.maxBlurInput {
			self.maxBlurInputValue = Double(field.stringValue)
		}
		if field == self.minBlurInput {
			self.minBlurInputValue = Double(field.stringValue)
		}
	}

    override func viewDidLayout() {
        super.viewDidLayout()
        self.videoLayer?.frame = self.videoPanel.bounds
    }
    
    @IBAction private func cameraSelectAction(_ sender: NSPopUpButton) {
        if sender.indexOfSelectedItem < self.cameras.count {
            self.setDevice(device: self.cameras[sender.indexOfSelectedItem])
        }
    }
    
    @IBAction func saveAction(_ sender: Any) {
        self.imageName = self.imageNameInput.stringValue
        self.isSaving = !self.isSaving
        self.saveButton.title = self.isSaving ? "Stop" : "Save"
        if isSaving {
            self.lastImage = nil
            self.imageNameInput.isEnabled = false
        } else {
            self.imageNameInput.isEnabled = true
        }
    }
    
    @IBAction func clearAction(_ sender: Any) {
        self.minBlurValue = nil
        self.maxBlurValue = nil
    }

    private var lastImage: Data? = nil
    private var imageName: String = ""
    
    private func generateFilename(blur: Double) -> String {
        let interval = Date().timeIntervalSince1970
        let prefix = self.imageName.isEmpty ? "Image" : self.imageName
        return "\(prefix)-\(interval)-\(blur).png"
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		autoreleasepool {
			guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
			CVPixelBufferLockBaseAddress(imageBuffer, [])
			defer {
				CVPixelBufferUnlockBaseAddress(imageBuffer, [])
			}
			guard let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) else { return }
			let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
			let width = CVPixelBufferGetWidth(imageBuffer)
			let height = CVPixelBufferGetHeight(imageBuffer)
			let colorSpace = CGColorSpaceCreateDeviceRGB()
			let dataSize = CVPixelBufferGetDataSize(imageBuffer)
			let data = Data(bytes: baseAddress, count: dataSize)
			let image = CIImage(bitmapData: data, bytesPerRow: bytesPerRow, size: CGSize(width: width, height: height), format: .BGRA8, colorSpace: colorSpace)
			let context = CIContext()
			guard let cgImage = context.createCGImage(image, from: image.extent),
				let buffer = ViewController.imageBuffer(image: cgImage) else { return }
			let blur = ViewController.evaluateBlurriness(buffer: buffer)
			let minBlur = min(self.minBlurValue ?? blur, blur)
			let maxBlur = max(self.maxBlurValue ?? blur, blur)
			self.minBlurValue = minBlur
			self.maxBlurValue = maxBlur
			DispatchQueue.main.async {
				self.currentBlurLabel.stringValue = "\(blur)"
				self.blurMinLabel.stringValue = "\(minBlur)"
				self.blurMaxLabel.stringValue = "\(maxBlur)"
			}
			let blurMin = self.minBlurInputValue ?? blur
			let blurMax = self.maxBlurInputValue ?? blur
			if self.isSaving && blurMin <= blur && blurMax >= blur {
				let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
				if let imageData = bitmapRep.representation(using: .png, properties: [:]), !(self.lastImage?.elementsEqual(imageData) ?? false), let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
					self.lastImage = imageData
					let url = downloads.appendingPathComponent(self.generateFilename(blur: blur))
					do {
						try imageData.write(to: url)
					} catch {
						print("Error write data to \(url.absoluteString) \(error.localizedDescription)")
					}
				}
			}
		}
    }
    
    class func imageBuffer(image: CGImage) -> vImage_Buffer? {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: image.width * image.height)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: buffer, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width, space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let image = vImage_Buffer(data: buffer, height: vImagePixelCount(image.height), width: vImagePixelCount(image.width), rowBytes: image.width)
		buffer.deallocate()
		return image
    }
    
    class func evaluateBlurriness(buffer: vImage_Buffer) -> Double {
        var buffer = buffer
        let convolutionPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(buffer.width*buffer.height))
        var convolutionBuffer = vImage_Buffer(data: convolutionPointer, height: buffer.height, width: buffer.width, rowBytes: buffer.rowBytes)
        let kernel : [Int16] = [0,1,0, 1,-4,1, 0,1,0]
        vImageConvolve_Planar8(&buffer, &convolutionBuffer, nil, 0, 0, kernel, 3, 3, 1, 0, UInt32(kvImageTruncateKernel))
        
        let imageBufferFloatPointer = UnsafeMutablePointer<Float>.allocate(capacity: Int(buffer.width*buffer.height))
        var imageBufferFloat = vImage_Buffer(data: imageBufferFloatPointer, height: buffer.height, width: buffer.width, rowBytes: buffer.rowBytes * 4)
        vImageConvert_Planar8toPlanarF(&convolutionBuffer, &imageBufferFloat, 255.0, 0, UInt32(kvImageNoFlags))
        var average: Float = 0
        vDSP_meanv(imageBufferFloatPointer, 1, &average, buffer.width*buffer.height)
        let unsafeBufferPointer = UnsafeMutableBufferPointer(start: imageBufferFloatPointer, count: Int(buffer.width*buffer.height))
        let numerator = unsafeBufferPointer.reduce(0) { total, value  in
            return total + powf(average - value, 2)
        }
        imageBufferFloatPointer.deallocate()
        convolutionPointer.deallocate()
        
        return Double(numerator / Float(buffer.width*buffer.height))
    }
}


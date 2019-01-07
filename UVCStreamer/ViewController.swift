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

class ViewController: NSViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    @IBOutlet private weak var videoPanel: NSView!
    @IBOutlet private weak var cameraPopupButton: NSPopUpButton!
    @IBOutlet private weak var imageNameInput: NSTextField!
    @IBOutlet private weak var saveButton: NSButton!
    
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
        
    override func viewDidLoad() {
        super.viewDidLoad()
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
    
    private var lastImage: Data? = nil
    private var imageName: String = ""
    
    private func generateFilename() -> String {
        let interval = Date().timeIntervalSince1970
        let prefix = self.imageName.isEmpty ? "Image" : self.imageName
        return "\(prefix)-\(interval).png"
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if self.isSaving, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            CVPixelBufferLockBaseAddress(imageBuffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
                let width = CVPixelBufferGetWidth(imageBuffer)
                let height = CVPixelBufferGetHeight(imageBuffer)
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                
                let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                if let context = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue), let cgImage = context.makeImage() {
                    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                    if let imageData = bitmapRep.representation(using: .png, properties: [:]), !(self.lastImage?.elementsEqual(imageData) ?? false) {
                        self.lastImage = imageData
                        let url = URL(fileURLWithPath: "/Users/dmatushkin/Downloads", isDirectory: true).appendingPathComponent(self.generateFilename())
                        do {
                            try imageData.write(to: url)
                        } catch {
                            print("Error write data to \(url.absoluteString) \(error.localizedDescription)")
                        }
                        
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(imageBuffer, [])
        }
    }
}


//
//  ViewController.swift
//  fax-demo
//
//  Created by Branden Byers on 6/12/17.
//  Copyright © 2017 genesys. All rights reserved.
//

import UIKit
import Vision
import ImageIO
import PDFKit

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @IBOutlet weak var correctedImageView: UIImageView!
    
    @IBAction func takePicture(_ sender: Any) {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        present(picker, animated: true)
    }
    @IBAction func chooseImage(_ sender: Any) {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .savedPhotosAlbum
        present(picker, animated: true)
    }
    
    var inputImage: CIImage! // The image to be processed.
    
    let pdfView: PDFView = {
        return PDFView()
    }()
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        picker.dismiss(animated: true)
        correctedImageView.image = nil
        
        guard let uiImage = info[UIImagePickerControllerOriginalImage] as? UIImage
            else { fatalError("no image from image picker") }
        guard let ciImage = CIImage(image: uiImage)
            else { fatalError("can't create CIImage from UIImage") }
        let orientation = CGImagePropertyOrientation(uiImage.imageOrientation)
        inputImage = ciImage.applyingOrientation(Int32(orientation.rawValue))
        
        // Run the rectangle detector.
        let handler = VNImageRequestHandler(ciImage: ciImage, orientation: Int32(orientation.rawValue))
        DispatchQueue.global(qos: .userInteractive).async {
            do {
                try handler.perform([self.rectanglesRequest])
            } catch {
                print(error)
            }
        }
    }
    
    func generatePDF(view: UIImageView) -> NSData? {
        let pdfData = NSMutableData()
        UIGraphicsBeginPDFContextToData(pdfData, CGRect(x: 0, y: 0, width: 612, height: 792), nil)
        
        let context = UIGraphicsGetCurrentContext()
        
        UIGraphicsBeginPDFPage()
        view.layer.render(in: context!)
        UIGraphicsEndPDFContext()
        
        return pdfData
    }
    
    lazy var rectanglesRequest: VNDetectRectanglesRequest = {
        return VNDetectRectanglesRequest(completionHandler: self.handleRectangles)
    }()
    func handleRectangles(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNRectangleObservation]
            else { fatalError("unexpected result type from VNDetectRectanglesRequest") }
        guard let detectedRectangle = observations.first else {
            DispatchQueue.main.async {
                // No rectangles detected
            }
            return
        }
        let imageSize = inputImage.extent.size
        
        // Verify detected rectangle is valid.
        let boundingBox = detectedRectangle.boundingBox.scaled(to: imageSize)
        guard inputImage.extent.contains(boundingBox)
            else { print("invalid detected rectangle"); return }
        
        // Rectify the detected image.
        let topLeft = detectedRectangle.topLeft.scaled(to: imageSize)
        let topRight = detectedRectangle.topRight.scaled(to: imageSize)
        let bottomLeft = detectedRectangle.bottomLeft.scaled(to: imageSize)
        let bottomRight = detectedRectangle.bottomRight.scaled(to: imageSize)
        let correctedImage = inputImage
            .cropping(to: boundingBox)
            .applyingFilter("CIPerspectiveCorrection", withInputParameters: [
                "inputTopLeft": CIVector(cgPoint: topLeft),
                "inputTopRight": CIVector(cgPoint: topRight),
                "inputBottomLeft": CIVector(cgPoint: bottomLeft),
                "inputBottomRight": CIVector(cgPoint: bottomRight)
                ])
        
        // Show the pre-processed image and generate PDF
        DispatchQueue.main.async {
            self.correctedImageView.image = UIImage(ciImage: correctedImage)
            let data = self.generatePDF(view: self.correctedImageView)
            let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
            let filePath = "\(documentsPath)/fax-sample-document.pdf"
            data?.write(toFile: filePath, atomically: true)
            print(documentsPath)
//            self.pdfView.document =  self.generatePDF(view: self.correctedImageView)
        }
        
    }
    
}

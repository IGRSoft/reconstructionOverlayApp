//
//  UIImageHelpers.swift
//  Capture


import UIKit

extension UIImage {
    
    func resized(toWidth width: CGFloat) -> UIImage {
        let scale = width / size.width
        let newSize = CGSize(width: width, height: size.height * scale)
        UIGraphicsBeginImageContext(newSize)
        
        draw(in: CGRect(origin: .zero, size: newSize))
        
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        
        UIGraphicsEndImageContext()
        
        return resized!
    }
    
}

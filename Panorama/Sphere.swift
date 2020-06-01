//
//  Sphere.swift
//  Panorama
//
//  Created by David Hoerl on 4/12/20.
//  Copyright © 2020 Robby Kraft. All rights reserved.
//

import Foundation
import GLKit
import MetalKit

// LINEAR for smoothing, NEAREST for pixelized
private let IMAGE_SCALING = GLint(GL_LINEAR)

private typealias WithRawPtr = (UnsafeRawPointer) -> Void

//private struct Pointer2 {
//    private var array: [SIMD2<Float>]
//
//    init(size: Int) {
//        let n: SIMD2<Float> = [Float.nan, Float.nan]
//
//        array = Array<SIMD2<Float>>(repeating: n, count: size)
//print("SIZE:", MemoryLayout<SIMD2<Float>>.size, MemoryLayout<SIMD2<Float>>.stride, MemoryLayout<SIMD2<Float>>.alignment)
//    }
//
//    subscript(index: Int) -> SIMD2<Float>{
//        get { return array[index] }
//        set(newValue) { array[index] = newValue }
//    }
//
//    mutating func usingRawPointer(block: WithRawPtr) {
//        array.withUnsafeBytes { (bufPtr) -> Void in
//            block(bufPtr.baseAddress!)
//        }
//    }
//}
//private struct Pointer3 {
//    private var array: [SIMD3<Float>]
//    private var a: Array<Float>
//
//    init(size: Int) {
//        a = Array<Float>(repeating: Float.nan, count: size * 3)
//        let n: SIMD3<Float> = [Float.nan, Float.nan, Float.nan]
//        array = Array<SIMD3<Float>>(repeating: n, count: size)
//print("SIZE:", MemoryLayout<SIMD3<Float>>.size, MemoryLayout<SIMD3<Float>>.stride, MemoryLayout<SIMD3<Float>>.alignment)
//    }
//
//    private mutating func flatten() {
//        var index = 0
//        for simd in array {
//            a[index] = simd.x
//            a[index+1] = simd.y
//            a[index+2] = simd.z
//            index += 3
//        }
//    }
//
//    subscript(index: Int) -> SIMD3<Float>{
//        get { return array[index] }
//        set(newValue) { array[index] = newValue }
//    }
//
//    mutating func usingRawPointer(block: WithRawPtr) {
//        flatten()
//        a.withUnsafeBytes { (bufPtr) -> Void in
//            block(bufPtr.baseAddress!)
//        }
//    }
//}


private let nanSIMD2: SIMD2<Float> = [Float.nan, Float.nan]
private let nanSIMD4: SIMD4<Float> = [Float.nan, Float.nan, Float.nan, Float.nan]  // 4th is unused

//@objcMembers
final class Sphere: NSObject {
    //  from Touch Fighter by Apple
    //  in Pro OpenGL ES for iOS
    //  by Mike Smithwick Jan 2011 pg. 78
    let textureFile: String
    lazy var m_Texture: MTLTexture = { loadTexture(fromBundle: textureFile) }()
    private var mtlDevice: MTLDevice

    private(set) var commonSize: Int
    private(set) var tPtr: [SIMD2<Float>] // m_TexCoordsData
    private(set) var vPtr: [SIMD4<Float>] // m_VertexData

    private let m_Stacks: GLint
    private let m_Slices: GLint
    private let m_Scale: GLfloat

//    var kQuadVertices: [SIMD4<Float>] = []
//    var kQuadTexCoords: [SIMD2<Float>] = []

    init(_ stacks: GLint, slices: GLint, radius: GLfloat, textureFile: String, device: MTLDevice) {
        mtlDevice = device
        // modifications:
        //   flipped(inverted) texture coords across the Z
        //   vertices rotated 90deg
        m_Scale = radius
        m_Stacks = stacks
        m_Slices = slices

        commonSize = Int((m_Slices*2+2) * m_Stacks)
        tPtr = Array<SIMD2<Float>>(repeating: nanSIMD2, count: commonSize)
        vPtr = Array<SIMD4<Float>>(repeating: nanSIMD4, count: commonSize)

        self.textureFile = textureFile

        super.init()

        // Vertices
        // Latitude
        var index = 0
        for phiIdx in 0..<Int(m_Stacks) {
            //starts at -pi/2 goes to pi/2
            //the first circle
            let phi0 = Float(.pi * (Float(phiIdx + 0) * (1.0 / Float(m_Stacks)) - 0.5))
            //second one
            let phi1 = Float(.pi * (Float(phiIdx + 1) * (1.0 / Float(m_Stacks)) - 0.5))
            let cosPhi0 = Float(cos(phi0))
            let sinPhi0 = Float(sin(phi0))
            let cosPhi1 = Float(cos(phi1))
            let sinPhi1 = Float(sin(phi1))

            //longitude
            for thetaIdx in 0..<Int(m_Slices) {

                let theta: Float = -2.0 * .pi * (Float(thetaIdx)) * (1.0 / Float(m_Slices - 1))
                let cosTheta: Float = cos(theta + .pi * 0.5)
                let sinTheta: Float = sin(theta + .pi * 0.5)

                //get x-y-x of the first vertex of stack
                vPtr[index] = SIMD4<Float>(cosPhi0 * cosTheta, sinPhi0, (cosPhi0 * sinTheta), 1.0) * Float(m_Scale)
                //the same but for the vertex immediately above the previous one.
                let texX = Float(thetaIdx) * (1.0 / Float(m_Slices - 1))
                tPtr[index] = SIMD2<Float>(1.0 - Float(texX), Float(phiIdx + 0) * (1.0 / Float(m_Stacks)))
                index += 1

                vPtr[index] = SIMD4<Float>(cosPhi1 * cosTheta, sinPhi1, (cosPhi1 * sinTheta), 1.0) * Float(m_Scale)
                tPtr[index] = SIMD2<Float>(1.0 - Float(texX), Float(phiIdx + 1) * (1.0 / Float(m_Stacks)))
                index += 1
            }

            // Degenerate triangle to connect stacks and maintain winding order
            let lastVector = vPtr[index - 1]
            let lastTexCord = tPtr[index - 1]
            for _ in 0..<2 {
                vPtr[index] = lastVector
                tPtr[index] = lastTexCord
                index += 1
            }
        }
//        func printAll(
//            rows: Int,
//            vPtr: Pointer3,
//            tPtr: Pointer2
//        ) {
//            var s = ""
//            s += "---TYPE:              Vector                Coords\n"
//
//            for row in 0..<rows {
//                let v = vPtr[row]
//                let t = tPtr[row]
//
//                s += String(format: "[%.2d] %10.4lf %10.4lf %10.4lf    %10.4lf %10.4lf \n", row, v[0], v[1], v[2], t[0], t[1])
//            }
//            print("\n\(s)\n")
//        }
        //printAll(rows: Int((m_Slices*2+2) * m_Stacks), vPtr: vPtr, tPtr: tPtr)
    }

    deinit {
    }

    func execute() -> Bool {

#if false
        glEnableClientState(UInt32(GL_VERTEX_ARRAY))

        do {
            glEnable(UInt32(GL_TEXTURE_2D))
            glEnableClientState(UInt32(GL_TEXTURE_COORD_ARRAY))
            if let textureInfo = m_Texture {
                glBindTexture(UInt32(GL_TEXTURE_2D), textureInfo.name)
            }
            tPtr.usingRawPointer(block: { (ptr) in
                glTexCoordPointer(2, UInt32(GL_FLOAT), 0, ptr)
            })
        }
        vPtr.usingRawPointer(block: { (ptr) in
            glVertexPointer(3, UInt32(GL_FLOAT), 0, ptr)
        })

        let count = Int32(((m_Slices*2+2) * m_Stacks))
        glDrawArrays(UInt32(GL_TRIANGLE_STRIP), 0, count)
         glDrawArrays(UInt32(GL_TRIANGLE_STRIP), 0, (m_Slices+1) * 2 * (m_Stacks-1)+2)

        glDisableClientState(UInt32(GL_TEXTURE_COORD_ARRAY))
        glDisable(UInt32(UInt32(GL_TEXTURE_2D)))

        glDisableClientState(UInt32(GL_VERTEX_ARRAY))
#endif
        return true
    }

    func swapTexture(_ textureFile: String) {
#if false
        if let textureInfo = m_Texture {
            var name = textureInfo.name
            glDeleteTextures(GLsizei(1), &name)
        }
        if FileManager.default.fileExists(atPath: textureFile), let texture = loadTexture(fromPath: textureFile) {
            m_Texture = texture
        } else if let texture = loadTexture(fromBundle: textureFile) {
            m_Texture = texture
        }
#endif
    }

    func swapTexture(image: UIImage) {
#if false
        if let textureInfo = m_Texture {
            var name = textureInfo.name
            glDeleteTextures(GLsizei(1), &name)
        }
        if let texture = loadTexture(from: image) {
            m_Texture = texture
        }
#endif
    }

    func getTextureSize() -> CGSize {
        return CGSize(width: CGFloat(m_Texture.width), height: CGFloat(m_Texture.height))
    }

    // MARK: - Private -

    private func loadTexture(fromBundle filename: String) -> MTLTexture {
        guard let path = Bundle.main.path(forResource: filename, ofType: nil) else { fatalError() }
        return loadTexture(fromPath: path)
    }

    private func loadTexture(fromPath path: String) -> MTLTexture {
        let loader: MTKTextureLoader = MTKTextureLoader(device: mtlDevice)
        let url = URL(fileURLWithPath: path)

        do {
            let texture = try loader.newTexture(URL: url, options: [
                MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.bottomLeft,
                MTKTextureLoader.Option.SRGB: false
            ])
            //JPEG: MTLPixelFormatBGRA8Unorm_sRGB, but this is bogus. The image looks moer washed out on the web.
            //MetalView.layer: MTLPixelFormatBGRA8Unorm
            return texture
        } catch {
            print("Failed to create the texture from \(path)", error);
            fatalError()
        }
    }

    private func loadTexture(from image: UIImage) -> MTLTexture? {
        guard let cgImage = image.cgImage else { return nil }
        let loader: MTKTextureLoader = MTKTextureLoader(device: mtlDevice)
        do {
            let texture = try loader.newTexture(cgImage: cgImage, options: [
                MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.bottomLeft,
                MTKTextureLoader.Option.SRGB: false
            ])
            //JPEG: MTLPixelFormatBGRA8Unorm_sRGB, but this is bogus. The image looks moer washed out on the web.
            //MetalView.layer: MTLPixelFormatBGRA8Unorm
            return texture
        } catch {
            print("Failed to create the texture from image", error);
            fatalError()
        }
    }

}

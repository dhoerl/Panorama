//
//  Sphere.swift
//  Panorama
//
//  Created by David Hoerl on 4/12/20.
//  Copyright © 2020 Robby Kraft. All rights reserved.
//

import Foundation
//import CoreMotion
import GLKit
import OpenGLES

// LINEAR for smoothing, NEAREST for pixelized
private let IMAGE_SCALING = GLint(GL_LINEAR)

private typealias WithRawPtr = (UnsafeRawPointer) -> Void

private struct Pointer {
    private var array: Array<GLfloat>
    private(set) var offset: Int = 0
    private let increment: Int

    init(size: Int, increment: Int) {
        array = Array<GLfloat>(repeating: 0, count: size)
        self.increment = increment
    }

    subscript(index: Int) -> GLfloat {
        get { return array[offset + index] }
        set(newValue) { array[offset + index] = newValue }
    }

    mutating func advance() { offset += increment }
    mutating func reset() { offset = 0 }

    mutating func usingRawPointer(block: WithRawPtr) {
        array.withUnsafeBytes { (bufPtr) -> Void in
            block(bufPtr.baseAddress!)
        }
    }
}

private struct Pointer2 {
    private var array: [SIMD2<Float>]

    init(size: Int) {
        let n: SIMD2<Float> = [Float.nan, Float.nan]

        array = Array<SIMD2<Float>>(repeating: n, count: size)
print("SIZE:", MemoryLayout<SIMD2<Float>>.size, MemoryLayout<SIMD2<Float>>.stride, MemoryLayout<SIMD2<Float>>.alignment)
    }

    subscript(index: Int) -> SIMD2<Float>{
        get { return array[index] }
        set(newValue) { array[index] = newValue }
    }

    mutating func usingRawPointer(block: WithRawPtr) {
        array.withUnsafeBytes { (bufPtr) -> Void in
            block(bufPtr.baseAddress!)
        }
    }
}
private struct Pointer3 {
    private var array: [SIMD3<Float>]
    private var a: Array<Float>

    init(size: Int) {
        a = Array<Float>(repeating: Float.nan, count: size * 3)
        let n: SIMD3<Float> = [Float.nan, Float.nan, Float.nan]
        array = Array<SIMD3<Float>>(repeating: n, count: size)
print("SIZE:", MemoryLayout<SIMD3<Float>>.size, MemoryLayout<SIMD3<Float>>.stride, MemoryLayout<SIMD3<Float>>.alignment)
    }

    private mutating func flatten() {
        var index = 0
        for simd in array {
            a[index] = simd.x
            a[index+1] = simd.y
            a[index+2] = simd.z
            index += 3
        }
    }

    subscript(index: Int) -> SIMD3<Float>{
        get { return array[index] }
        set(newValue) { array[index] = newValue }
    }

    mutating func usingRawPointer(block: WithRawPtr) {
        flatten()
        a.withUnsafeBytes { (bufPtr) -> Void in
            block(bufPtr.baseAddress!)
        }
    }
}


//@objcMembers
final class Sphere: NSObject {
    //  from Touch Fighter by Apple
    //  in Pro OpenGL ES for iOS
    //  by Mike Smithwick Jan 2011 pg. 78
    private var m_TextureInfo: GLKTextureInfo?

#if false
    private var tPtr: Pointer   // m_TexCoordsData
    private var vPtr: Pointer   // m_VertexData
#else
    private var tPtr: Pointer2   // m_TexCoordsData
    private var vPtr: Pointer3   // m_VertexData
#endif

    private let m_Stacks: GLint
    private let m_Slices: GLint
    private let m_Scale: GLfloat

    init(_ stacks: GLint, slices: GLint, radius: GLfloat, textureFile: String?) {

        // modifications:
        //   flipped(inverted) texture coords across the Z
        //   vertices rotated 90deg
        m_Scale = radius
        m_Stacks = stacks
        m_Slices = slices

#if false
        let sizeOfGLfloat = GLint(MemoryLayout<GLfloat>.size)
        let commonSize = Int(sizeOfGLfloat * ((m_Slices*2+2) * m_Stacks))
        tPtr = Pointer(size: commonSize * 2, increment: 2 * 2)  // m_TexCoordsData
        vPtr = Pointer(size: commonSize * 2, increment: 2 * 3)  // m_VertexData
#else
        let commonSize = Int((m_Slices*2+2) * m_Stacks)
        vPtr = Pointer3(size: commonSize)
        tPtr = Pointer2(size: commonSize)
#endif
        // Vertices
        // Latitude

        super.init()

        if let textureFile = textureFile {
            m_TextureInfo = loadTexture(fromBundle: textureFile)
        }

#if false
        for phiIdx in 0..<Int(m_Stacks) {
            //starts at -pi/2 goes to pi/2
            //the first circle
            let phi0 = GLfloat(.pi * (GLfloat(phiIdx + 0) * (1.0 / GLfloat(m_Stacks)) - 0.5))
            //second one
            let phi1 = GLfloat(.pi * (GLfloat(phiIdx + 1) * (1.0 / GLfloat(m_Stacks)) - 0.5))
            let cosPhi0 = GLfloat(cos(phi0))
            let sinPhi0 = GLfloat(sin(phi0))
            let cosPhi1 = GLfloat(cos(phi1))
            let sinPhi1 = GLfloat(sin(phi1))

            //longitude
            for thetaIdx in 0..<Int(m_Slices) {
                let theta: GLfloat = -2.0 * .pi * (GLfloat(thetaIdx)) * (1.0 / GLfloat(m_Slices - 1))
                let cosTheta: GLfloat = cos(theta + .pi * 0.5)
                let sinTheta: GLfloat = sin(theta + .pi * 0.5)

                //get x-y-x of the first vertex of stack
                vPtr[0] = m_Scale * cosPhi0 * cosTheta
                vPtr[1] = m_Scale * sinPhi0
                vPtr[2] = m_Scale * (cosPhi0 * sinTheta)
                //the same but for the vertex immediately above the previous one.
                vPtr[3] = m_Scale * cosPhi1 * cosTheta
                vPtr[4] = m_Scale * sinPhi1
                vPtr[5] = m_Scale * (cosPhi1 * sinTheta)
print("WTF:", vPtr[2], vPtr[5])
                do {
                    let texX = GLfloat(thetaIdx) * (1.0 / GLfloat(m_Slices - 1))
                    tPtr[0] = 1.0 - GLfloat(texX)
                    tPtr[1] = Float(phiIdx + 0) * (1.0 / GLfloat(m_Stacks))
                    tPtr[2] = 1.0 - GLfloat(texX)
                    tPtr[3] = Float(phiIdx + 1) * (1.0 / GLfloat(m_Stacks))
                }
                vPtr.advance()
                tPtr.advance()
            }
            //Degenerate triangle to connect stacks and maintain winding order
            vPtr[3] = vPtr[-3]
            vPtr[0] = vPtr[3]
            vPtr[4] = vPtr[-2]
            vPtr[1] = vPtr[4]
            vPtr[5] = vPtr[-1]
            vPtr[2] = vPtr[5]

            tPtr[2] = tPtr[-2]
            tPtr[0] = tPtr[2]
            tPtr[3] = tPtr[-1]
            tPtr[1] = tPtr[3]

            vPtr.advance()
            tPtr.advance()
        }
        print("OFFSETS:", vPtr.offset, tPtr.offset)
        vPtr.reset()
        tPtr.reset()

        func printAll(
            rows: Int,
            vPtr: Pointer,
            tPtr: Pointer
        ) {

            var s = ""
            s += "---TYPE:              Vector                Coords\n"

            for row in 0..<rows {
                s += String(format: "[%.2d] %10.4lf %10.4lf %10.4lf    %10.4lf %10.4lf \n", row, vPtr[row*3], vPtr[row*3+1], vPtr[row*3+2], tPtr[row*2], tPtr[row*2+1])
            }
            print("\n\(s)\n")
        }
        printAll(rows: Int((m_Slices*2+2) * m_Stacks), vPtr: vPtr, tPtr: tPtr)

#else
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
                vPtr[index] = SIMD3<Float>(cosPhi0 * cosTheta, sinPhi0, (cosPhi0 * sinTheta)) * Float(m_Scale)
                //the same but for the vertex immediately above the previous one.
                let texX = Float(thetaIdx) * (1.0 / Float(m_Slices - 1))
                tPtr[index] = SIMD2<Float>(1.0 - Float(texX), Float(phiIdx + 0) * (1.0 / Float(m_Stacks)))
                index += 1

                vPtr[index] = SIMD3<Float>(cosPhi1 * cosTheta, sinPhi1, (cosPhi1 * sinTheta)) * Float(m_Scale)
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
        func printAll(
            rows: Int,
            vPtr: Pointer3,
            tPtr: Pointer2
        ) {
            var s = ""
            s += "---TYPE:              Vector                Coords\n"

            for row in 0..<rows {
                let v = vPtr[row]
                let t = tPtr[row]

                s += String(format: "[%.2d] %10.4lf %10.4lf %10.4lf    %10.4lf %10.4lf \n", row, v[0], v[1], v[2], t[0], t[1])
            }
            print("\n\(s)\n")
        }
        //printAll(rows: Int((m_Slices*2+2) * m_Stacks), vPtr: vPtr, tPtr: tPtr)
#endif
    }

    deinit {
        guard let textureInfo = m_TextureInfo else { return }
        var name = textureInfo.name
        glDeleteTextures(GLsizei(1), &name)
    }

    func execute() -> Bool {
//        glEnableClientState(UInt32(GL_NORMAL_ARRAY))
        glEnableClientState(UInt32(GL_VERTEX_ARRAY))

        do {
            glEnable(UInt32(UInt32(GL_TEXTURE_2D)))
            glEnableClientState(UInt32(GL_TEXTURE_COORD_ARRAY))
            if let textureInfo = m_TextureInfo {
                glBindTexture(UInt32(UInt32(GL_TEXTURE_2D)), textureInfo.name)
            }
            tPtr.usingRawPointer(block: { (ptr) in
                glTexCoordPointer(2, UInt32(GL_FLOAT), 0, ptr)
            })
        }
        vPtr.usingRawPointer(block: { (ptr) in
            glVertexPointer(3, UInt32(GL_FLOAT), 0, ptr)
        })
//        nPtr.usingRawPointer(block: { (ptr) in
//            glNormalPointer(UInt32(GL_FLOAT), 0, ptr)
//        })

        //let count = (m_Slices+1) * 2 * (m_Stacks-1)+2
        let count = Int32(((m_Slices*2+2) * m_Stacks))
//print("COUNT:", count, "CM:", commonSize)
        glDrawArrays(UInt32(GL_TRIANGLE_STRIP), 0, count)
        glDisableClientState(UInt32(GL_TEXTURE_COORD_ARRAY))
        glDisable(UInt32(UInt32(GL_TEXTURE_2D)))
        glDisableClientState(UInt32(GL_VERTEX_ARRAY))
//        glDisableClientState(UInt32(GL_NORMAL_ARRAY))
        return true
    }

    func swapTexture(_ textureFile: String) {
        if let textureInfo = m_TextureInfo {
            var name = textureInfo.name
            glDeleteTextures(GLsizei(1), &name)
        }
        if FileManager.default.fileExists(atPath: textureFile), let texture = loadTexture(fromPath: textureFile) {
            m_TextureInfo = texture
        } else if let texture = loadTexture(fromBundle: textureFile) {
            m_TextureInfo = texture
        }
    }

    func swapTexture(image: UIImage) {
        if let textureInfo = m_TextureInfo {
            var name = textureInfo.name
            glDeleteTextures(GLsizei(1), &name)
        }
        if let texture = loadTexture(from: image) {
            m_TextureInfo = texture
        }
    }

    func getTextureSize() -> CGSize {
        guard let textureInfo = m_TextureInfo else { return CGSize.zero }
        return CGSize(width: CGFloat(textureInfo.width), height: CGFloat(textureInfo.height))
    }

    // MARK: - Private -

    private func loadTexture(fromBundle filename: String) -> GLKTextureInfo? {
        guard let path = Bundle.main.path(forResource: filename, ofType: nil) else { return nil }
        return loadTexture(fromPath: path)
    }

    private func loadTexture(fromPath path: String) -> GLKTextureInfo? {
        let options: [String: NSNumber] = [GLKTextureLoaderOriginBottomLeft : NSNumber(value: true) ]
        do {
            let info = try GLKTextureLoader.texture(withContentsOfFile: path, options: options)

            glBindTexture(UInt32(UInt32(GL_TEXTURE_2D)), info.name)
            glTexParameteri(UInt32(UInt32(GL_TEXTURE_2D)), UInt32(GL_TEXTURE_WRAP_S), GLint(GL_REPEAT))
            glTexParameteri(UInt32(UInt32(GL_TEXTURE_2D)), UInt32(GL_TEXTURE_WRAP_T), GLint(GL_REPEAT))
            glTexParameteri(UInt32(UInt32(GL_TEXTURE_2D)), UInt32(GL_TEXTURE_MAG_FILTER), IMAGE_SCALING)
            glTexParameteri(UInt32(UInt32(GL_TEXTURE_2D)), UInt32(GL_TEXTURE_MIN_FILTER), IMAGE_SCALING)
            return info
        } catch {
            print("ERROR:", String(describing: error))
            return nil
        }
    }

    private func loadTexture(from image: UIImage) -> GLKTextureInfo? {
        guard let cgImage = image.cgImage else { return nil }
        let options: [String: NSNumber] = [ GLKTextureLoaderOriginBottomLeft : NSNumber(value: true) ]
        do {
            let info = try GLKTextureLoader.texture(with: cgImage, options: options)
            glBindTexture(UInt32(UInt32(GL_TEXTURE_2D)), info.name)
            glTexParameteri(UInt32(UInt32(GL_TEXTURE_2D)), UInt32(GL_TEXTURE_WRAP_S), GLint(GL_REPEAT))
            glTexParameteri(UInt32(UInt32(GL_TEXTURE_2D)), UInt32(GL_TEXTURE_WRAP_T), GLint(GL_REPEAT))
            glTexParameteri(UInt32(UInt32(GL_TEXTURE_2D)), UInt32(GL_TEXTURE_MAG_FILTER), IMAGE_SCALING)
            glTexParameteri(UInt32(UInt32(GL_TEXTURE_2D)), UInt32(GL_TEXTURE_MIN_FILTER), IMAGE_SCALING)
            return info
        } catch {
            print("ERROR:", String(describing: error))
            return nil
        }
    }

}

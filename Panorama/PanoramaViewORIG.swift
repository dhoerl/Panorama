//
//  PanoramaView.swift
//  Panorama
//
//  Created by Robby Kraft on 8/24/2013.
//  Swift Conversion by David Hoerl 4/25/2020
//  Copyright (c) 2013 Robby Kraft. All rights reserved.
//
//  Remark: a dynamic GLKView with a touch and motion sensor interface to align and immerse the perspective inside an equirectangular panorama projection
//  Converted to Swift 5.2 by Swiftify v5.2.18740 - https://swiftify.com/

import Foundation
import CoreMotion
import GLKit
import OpenGLES

@objc
final class PanoramaView: GLKView {

    private static let renderSceneWhiteColor: [GLfloat] = [1.0, 1.0, 1.0, 1.0]
    private static let renderSceneClearColor: [GLfloat] = [0.0, 0.0, 0.0, 0.0]
    private static var panHandlerTouchVector: GLKVector3 = GLKVector3(v: (0.0, 0.0, 0.0))
    private static var pinchHandlerZoom: CGFloat = 0.0

    private static let FPS = 60
    private static let FOV_MIN = 1
    private static let FOV_MAX = 155
    private static let Z_NEAR: Float = 0.1
    private static let Z_FAR: Float = 100.0

    private var SENSOR_ORIENTATION: UIInterfaceOrientation { UIApplication.shared.statusBarOrientation }
    private lazy var motionManager: CMMotionManager = CMMotionManager()
    private lazy var sphere: Sphere = Sphere(48, slices: 48, radius: 10.0, textureFile: nil)
    private lazy var meridians: Sphere = Sphere(48, slices: 48, radius: 8.0, textureFile: "equirectangular-projection-lines.png")
    private lazy var pinchGesture: UIPinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinchHandler(_:)))
    private lazy var panGesture: UIPanGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panHandler(_:)))
    private var projectionMatrix: GLKMatrix4 = GLKMatrix4Identity
    private var attitudeMatrix: GLKMatrix4 = GLKMatrix4Identity
    private var offsetMatrix: GLKMatrix4 = GLKMatrix4Identity
    private var aspectRatio: Float = 1.0
    private var retinaScale: Float = 0.0
    private var circlePoints = [GLfloat](repeating: 0, count: 64 * 3) // meridian lines

    /// Set of (UITouch*) touches currently active
    private var touches: Set<UITouch> = []
    /// Dynamic overlay of latitude and longitude intersection lines for all touches
    @objc var showTouches = false

    /// forward vector axis (into the screen)
    @objc private(set) var lookVector: GLKVector3 = GLKVector3(v: (0.0, 0.0, 0.0))
    /// forward horizontal azimuth (-π to π)
    @objc private(set) var lookAzimuth: Float = 0.0
    /// forward vertical altitude (-.5π to .5π)
    @objc private(set) var lookAltitude: Float = 0.0
    /// Shift the horizonal alignment, move the center pixel of the image away from cardinal north. in degrees
    @objc var cardinalOffset: Float = 0.0

    /// If the event of a pan gesture, the view will remain vertically fixed on the horizon line
    @objc var lockPanToHorizon = false

  /// Field of view in DEGREES
    private var _fieldOfView: Float = 0.0
    @objc var fieldOfView: Float {
        get {
            _fieldOfView
        }
        set(fieldOfView) {
            _fieldOfView = fieldOfView
            rebuildProjectionMatrix()
        }
    }
    /// set image by path or bundle - will check at both
    private var _imageWithName: String = ""
    @objc var imageWithName: String {
        get {
            _imageWithName
        }
        set(imageWithName) {
            _imageWithName = imageWithName
            sphere.swapTexture(imageWithName)
        }
    }
    /// set image
    private var _image: UIImage = UIImage()
    @objc var image: UIImage {
        get {
            _image
        }
        set(image) {
            _image = image
            sphere.swapTexture(image: image)
        }
    }
    /// Enables UIPanGestureRecognizer to affect view orientation
    private var _touchToPan = false
    @objc var  touchToPan: Bool {
        get {
            _touchToPan
        }
        set(touchToPan) {
            _touchToPan = touchToPan
            panGesture.isEnabled = _touchToPan
        }
    }
    /// Enables UIPinchGestureRecognizer to affect FieldOfView
    private var _pinchToZoom = false
    @objc var  pinchToZoom: Bool {
        get {
            _pinchToZoom
        }
        set(pinchToZoom) {
            _pinchToZoom = pinchToZoom
            pinchGesture.isEnabled = _pinchToZoom
        }
    }
    /// Activates accelerometer + gyro orientation
    private var _orientToDevice = false
    @objc var orientToDevice: Bool {
        // At this point, it's still recommended to activate either OrientToDevice or TouchToPan, not both
        // it's possible to have them simultaneously, but the effect is confusing and disorienting
        get {
            _orientToDevice
        }
        set(orientToDevice) {
            _orientToDevice = orientToDevice
            if motionManager.isDeviceMotionAvailable {
                if _orientToDevice {
                    motionManager.startDeviceMotionUpdates()
                } else {
                    motionManager.stopDeviceMotionUpdates()
                }
            }
        }
    }
    /// Split screen mode for use in VR headsets
    private var _vrMode = false
    @objc var VRMode: Bool {
        get {
            _vrMode
        }
        set(VRMode) {
            _vrMode = VRMode
            if VRMode {
                aspectRatio = Float(frame.size.width / (frame.size.height * 0.5))
                rebuildProjectionMatrix()
            } else {
                aspectRatio = Float(frame.size.width / frame.size.height)
                rebuildProjectionMatrix()
            }
        }
    }

    // MARK: - Inits -

    convenience init() {
        self.init(frame: UIScreen.main.bounds)
    }

    override init(frame: CGRect) {
        guard let context = EAGLContext(api: .openGLES1) else { fatalError() }
        EAGLContext.setCurrent(context)

        super.init(frame: frame)
        self.context = context

        initOpenGL(context)

        pinchGesture.isEnabled = false
        addGestureRecognizer(pinchGesture)

        panGesture.maximumNumberOfTouches = 1
        panGesture.isEnabled = false
        addGestureRecognizer(panGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        EAGLContext.setCurrent(nil)
    }

    // MARK: - Public -

    @objc func imagePixel(from vector: GLKVector3) -> CGPoint {
        var pxl = CGPoint(x: CGFloat(atan2(-vector.x, vector.z)) / (2 * .pi), y: CGFloat(acos(vector.y) / .pi))
        if pxl.x < 0.0 {
            pxl.x += 1.0
        }
        let tex = sphere.getTextureSize()
        if tex != CGSize.zero {
            // if no texture exists, returns between 0.0 - 1.0
            if !(tex.width == 0.0 && tex.height == 0.0) {
                pxl.x *= tex.width
                pxl.y *= tex.height
            }
        }
        return pxl
    }

    @objc func vector(fromScreenLocation point: CGPoint, inAttitude matrix: GLKMatrix4) -> GLKVector3 {
        let inverse = GLKMatrix4Invert(GLKMatrix4Multiply(projectionMatrix, matrix), nil)
        let screen = GLKVector4Make(Float(2.0 * (point.x / frame.size.width - 0.5)), Float(2.0 * (0.5 - point.y / frame.size.height)), 1.0, 1.0)
        //    if (SENSOR_ORIENTATION == 3 || SENSOR_ORIENTATION == 4)
        //        screen = GLKVector4Make(2.0*(screenTouch.x/self.frame.size.height-.5),
        //                                2.0*(.5-screenTouch.y/self.frame.size.width),
        //                                1.0, 1.0);
        let vec = GLKMatrix4MultiplyVector4(inverse, screen)
        return GLKVector3Normalize(GLKVector3Make(vec.x, vec.y, vec.z))
    }

    /// Align Z coordinate axis (into the screen) to a GLKVector.
    /// (due to a fixed up-vector, flipping will occur at the poles)
    ///
    /// - Parameter GLKVector3: can be non-normalized
    @objc func orient(to v: GLKVector3) {
        attitudeMatrix = GLKMatrix4MakeLookAt(0, 0, 0, v.x, v.y, v.z, 0, 1, 0)
        updateLook()
    }

    /// Align Z coordinate axis (into the screen) to azimuth and altitude.
    /// (due to a fixed up-vector, flipping will occur at the poles)
    ///
    /// - Parameter Azimuth(-π: to π) Altitude(-.5π to .5π)
    @objc func orient(toAzimuth azimuth: Float, altitude: Float) {
        orient(to: GLKVector3Make(-cosf(azimuth), sinf(altitude), sinf(azimuth)))
    }

    /// Hit-detection for all active touches
    ///
    /// - Parameter CGRect: defined in image pixel coordinates
    /// - Returns: YES if touch is inside CGRect, NO otherwise
    @objc func touch(in rect: CGRect) -> Bool {
        for touch in touches {
            let touchPoint = CGPoint(x: touch.location(in: self).x, y: touch.location(in: self).y )
            let found = rect.contains(imagePixel(atScreenLocation: touchPoint))
            if found { return true }
        }
        return false
    }

    // MARK: - projection & touches -

    /// Convert a 3D world-coordinate (specified by a vector from the origin) to a 2D on-screen coordinate
    ///
    /// - Parameter GLKVector3: coordinate location from origin. Use with CGRectContainsPoint( [[UIScreen mainScreen] bounds], screenPoint )
    /// - Returns: a screen pixel coordinate representation of a 3D world coordinate
    @objc func screenLocation(from vector: GLKVector3) -> CGPoint {
        let matrix = GLKMatrix4Multiply(projectionMatrix, attitudeMatrix)
        let screenVector = GLKMatrix4MultiplyVector3(matrix, vector)
        let x1 = (screenVector.x / screenVector.z) / 2.0 + 0.5
        let y1 = 0.5 - (screenVector.y / screenVector.z) / 2
        return CGPoint(
            x: CGFloat(x1) * frame.size.width,
            y: CGFloat(y1) * frame.size.height
        )
    }

    /// Converts a 2D on-screen coordinate to a vector in 3D space pointing out from the origin
    ///
    /// - Parameter CGPoint: screen coordinate
    /// - Returns: GLKVector3 vector pointing outward from origin
    func vector(fromScreenLocation point: CGPoint) -> GLKVector3 {
        return vector(fromScreenLocation: point, inAttitude: attitudeMatrix)
    }

    /// Converts a 2D on-screen coordinate to a pixel (x,y) of the loaded panorama image
    ///
    /// - Parameter CGPoint: screen coordinate
    /// - Returns: CGPoint image coordinate in pixels. If no image, between 0.0 and 1.0
    func imagePixel(atScreenLocation point: CGPoint) -> CGPoint {
        return imagePixel(from: vector(fromScreenLocation: point, inAttitude: attitudeMatrix))
    }

    // MARK:- OPENGL

    private func initOpenGL(_ context: EAGLContext?) {
        guard let layer = self.layer as? CAEAGLLayer else { fatalError() }
        layer.isOpaque = false
        aspectRatio = Float(frame.size.width / frame.size.height)
        fieldOfView = 45 + 45 * atanf(aspectRatio) // hell ya
        retinaScale = Float(UIScreen.main.nativeScale)
        rebuildProjectionMatrix()
        attitudeMatrix = GLKMatrix4Identity
        offsetMatrix = GLKMatrix4Identity
        customGL()
        makeLatitudeLines()
    }

    @objc func draw() {
        // place in GLKViewController's glkView:drawInRect:
        glClearColor(0.0, 0.0, 0.0, 0.0)
        glClear(UInt32(GL_COLOR_BUFFER_BIT))
        if _vrMode {
            // one eye
            glMatrixMode(UInt32(GL_PROJECTION))
            glViewport(0, 0, GLsizei(frame.size.width * CGFloat(retinaScale)), GLsizei(frame.size.height * CGFloat(retinaScale) * 0.5))
            glMatrixMode(UInt32(GL_MODELVIEW ))
            renderScene()
            // other eye
            glMatrixMode(UInt32(GL_PROJECTION))
            glViewport(0, GLsizei(frame.size.height * CGFloat(retinaScale) * 0.5), GLsizei(frame.size.width * CGFloat(retinaScale)), GLsizei(frame.size.height * CGFloat(retinaScale) * 0.5))
            glMatrixMode(UInt32(GL_MODELVIEW ))
            renderScene()
        } else {
            renderScene()
        }
    }

    override func didMoveToSuperview() {
        // this breaks MVC, but useful for setting GLKViewController's frame rate
        var responder: UIResponder = self as UIResponder
        while !(responder is GLKViewController) {
            if let next = responder.next {
                responder = next
            } else {
                return
            }
        }
        if let glkVC = responder as? GLKViewController {
            glkVC.preferredFramesPerSecond = Self.FPS
        }
    }

    private func rebuildProjectionMatrix() {
        glMatrixMode(UInt32(GL_PROJECTION))
        glLoadIdentity()
        let frustum: Float = Self.Z_NEAR * tanf(fieldOfView * 0.00872664625997) // pi/180/2
        projectionMatrix = GLKMatrix4MakeFrustum(
            Float(-frustum),
            Float(frustum),
            Float(-frustum) / aspectRatio,
            Float(frustum) / aspectRatio,
            Float(Self.Z_NEAR), Float(Self.Z_FAR)
        )
//        var ma: GLint = 0
//        glGetIntegerv(UInt32(GL_MATRIX_MODE), &ma)
//        print("MATRIX:", ma,  GL_PROJECTION_MATRIX, GL_MODELVIEW_MATRIX, GL_TEXTURE_MATRIX) ;   // , GL2.GL_PROJECTION
//
//        var m = Array<GLfloat>(repeating: 0, count: 16)
//        glGetFloatv(UInt32(GL_PROJECTION_MATRIX), &m)
//        print("M:", m)

        withUnsafeBytes(of: &projectionMatrix) { bytes in
            guard let ptr = bytes.baseAddress else { fatalError() }
            let glPtr = ptr.assumingMemoryBound(to: GLfloat.self)
            glMultMatrixf(glPtr) // GL_PROJECTION_MATRIX GL_MODELVIEW_MATRIX GL_TEXTURE_MATRIX
        }

//        glGetFloatv(UInt32(GL_PROJECTION_MATRIX), &m);
//        print("M:", m)

        if !_vrMode {
            glViewport(0, 0, GLsizei(frame.size.width), GLsizei(frame.size.height))
        } else {
            // no matter. glViewport gets called every draw call anyway.
        }
        glMatrixMode(UInt32(GL_MODELVIEW))
    }


    private func customGL() {
        glMatrixMode(UInt32(GL_MODELVIEW))
        //    glEnable(GL_CULL_FACE);
        //    glCullFace(GL_FRONT);
        //    glEnable(GL_DEPTH_TEST);
        glEnable(UInt32(GL_BLEND))
        glBlendFunc(UInt32(GL_SRC_ALPHA), UInt32(GL_ONE_MINUS_SRC_ALPHA))
    }


    private func renderScene() {
        glPushMatrix() // begin device orientation
        attitudeMatrix = GLKMatrix4Multiply(getDeviceOrientationMatrix(), offsetMatrix)
        updateLook()

        withUnsafeBytes(of: &attitudeMatrix) { bytes in
            guard let ptr = bytes.baseAddress else { fatalError() }
            let glPtr = ptr.assumingMemoryBound(to: GLfloat.self)
            glMultMatrixf(glPtr)
        }

        glRotatef(cardinalOffset, 0, 1, 0)
        glMaterialfv(UInt32(GL_FRONT_AND_BACK), UInt32(GL_EMISSION), Self.renderSceneWhiteColor) // panorama at full color
        let _ = sphere.execute()
        glMaterialfv(UInt32(GL_FRONT_AND_BACK), UInt32(GL_EMISSION), Self.renderSceneClearColor)
        let _ = meridians.execute()  // semi-transparent texture overlay (15° meridian lines)

        //TODO: add any objects here to make them a part of the virtual reality
        //        glPushMatrix();
        //            // object code
        //        glPopMatrix();

        // touch lines
        if showTouches && !touches.isEmpty {
            glColor4f(1.0, 1.0, 1.0, 0.5)
            for touch in touches {
                glPushMatrix()
                var touchPoint = CGPoint(x: touch.location(in: self).x, y: touch.location(in: self).y)
                if _vrMode {
                    touchPoint.y = CGFloat((Int(touchPoint.y) % Int(frame.size.height * 0.5))) * 2.0
                }
                drawHotspotLines(vector(fromScreenLocation: touchPoint, inAttitude: attitudeMatrix))
                glPopMatrix()
            }
            glColor4f(1.0, 1.0, 1.0, 1.0)
        }
        glPopMatrix() // end device orientation
    }

    // Mark: - ORIENTATION -

    private func getDeviceOrientationMatrix() -> GLKMatrix4 {
        if orientToDevice && motionManager.isDeviceMotionActive {
            guard let a = motionManager.deviceMotion?.attitude.rotationMatrix else { return GLKMatrix4Identity }
            // arrangements of mappings of sensor axis to virtual axis (columns)
            // and combinations of 90 degree rotations (rows)
/*
    UIInterfaceOrientationUnknown            = UIDeviceOrientationUnknown,
    UIInterfaceOrientationPortrait           = UIDeviceOrientationPortrait,
    UIInterfaceOrientationPortraitUpsideDown = UIDeviceOrientationPortraitUpsideDown,
    UIInterfaceOrientationLandscapeLeft      = UIDeviceOrientationLandscapeRight,
    UIInterfaceOrientationLandscapeRight     = UIDeviceOrientationLandscapeLeft
*/
            switch SENSOR_ORIENTATION {
            case .landscapeRight:
                return GLKMatrix4Make(Float(a.m21), Float(-(a.m11)), Float(a.m31), 0.0, Float(a.m23), Float(-(a.m13)), Float(a.m33), 0.0, Float(-(a.m22)), Float(a.m12), Float(-(a.m32)), 0.0, 0.0, 0.0, 0.0, 1.0)
            case .landscapeLeft:
                return GLKMatrix4Make(Float(-(a.m21)), Float(a.m11), Float(a.m31), 0.0, Float(-(a.m23)), Float(a.m13), Float(a.m33), 0.0, Float(a.m22), Float(-(a.m12)), Float(-(a.m32)), 0.0, 0.0, 0.0, 0.0, 1.0)
            case .portraitUpsideDown:
                return GLKMatrix4Make(Float(-(a.m11)), Float(-(a.m21)), Float(a.m31), 0.0, Float(-(a.m13)), Float(-(a.m23)), Float(a.m33), 0.0, Float(a.m12), Float(a.m22), Float(-(a.m32)), 0.0, 0.0, 0.0, 0.0, 1.0)
            case .unknown, .portrait:
                fallthrough
            @unknown default:
                return GLKMatrix4Make(Float(a.m11), Float(a.m21), Float(a.m31), 0.0, Float(a.m13), Float(a.m23), Float(a.m33), 0.0, Float(-(a.m12)), Float(-(a.m22)), Float(-(a.m32)), 0.0, 0.0, 0.0, 0.0, 1.0)
            }
        }
        return GLKMatrix4Identity
    }

    private func updateLook() {
        lookVector = GLKVector3Make(-attitudeMatrix.m02, -attitudeMatrix.m12, -attitudeMatrix.m22)
        lookAzimuth = atan2f(lookVector.x, -lookVector.z)
        lookAltitude = asinf(lookVector.y)
    }

    private func GLKQuaternionFromTwoVectors(_ u: GLKVector3, _ v: GLKVector3) -> GLKQuaternion {
        let w = GLKVector3CrossProduct(u, v)
        var q = GLKQuaternionMake(w.x, w.y, w.z, GLKVector3DotProduct(u, v))
        q.w += GLKQuaternionLength(q)
        return GLKQuaternionNormalize(q)
    }

    private func computeScreenLocation(_ location: inout CGPoint, from vector: GLKVector3, inAttitude matrix: GLKMatrix4) -> Bool {
        //This method returns whether the point is before or behind the screen.
        //guard location != nil else { return false }

        var screenVector: GLKVector4
        var vector4: GLKVector4
        let matrix = GLKMatrix4Multiply(projectionMatrix, matrix)
        vector4 = GLKVector4Make(vector.x, vector.y, vector.z, 1)
        screenVector = GLKMatrix4MultiplyVector4(matrix, vector4)

        let x1 = (screenVector.x / screenVector.z) / 2.0 + 0.5
        let y1 = 0.5 - (screenVector.y / screenVector.z) / 2
        location = CGPoint(x: CGFloat(x1) * frame.size.width, y: CGFloat(y1) * frame.size.height)
        return screenVector.z >= 0
    }

    // MARK:- MERIDIANS

    private func makeLatitudeLines() {
        for i in 0..<64 {
            let radians = Float((.pi * 2) / 64.0) * Float(i)
            circlePoints[i * 3 + 0] = -sinf(radians)
            circlePoints[i * 3 + 1] = 0.0
            circlePoints[i * 3 + 2] = cosf(radians)
        }
    }

    private func drawHotspotLines(_ touchLocation: GLKVector3) {
        glLineWidth(2.0)
        let scale = sqrtf(1 - powf(touchLocation.y, 2))
        glPushMatrix()
        glScalef(scale, 1.0, scale)
        glTranslatef(0, touchLocation.y, 0)
        glDisableClientState(UInt32(GL_NORMAL_ARRAY))
        glEnableClientState(UInt32(GL_VERTEX_ARRAY))
        glVertexPointer(3, UInt32(GL_FLOAT), 0, circlePoints)
        glDrawArrays(UInt32(GL_LINE_LOOP), 0, GLsizei(64))
        glDisableClientState(UInt32(GL_VERTEX_ARRAY))
        glPopMatrix()

        glPushMatrix()
        glRotatef(-atan2f(-touchLocation.z, -touchLocation.x) * 180 / .pi, 0, 1, 0)
        glRotatef(90, 1, 0, 0)
        glDisableClientState(UInt32(GL_NORMAL_ARRAY))
        glEnableClientState(UInt32(GL_VERTEX_ARRAY))
        glVertexPointer(3, UInt32(GL_FLOAT), 0, circlePoints)
        glDrawArrays(UInt32(GL_LINE_STRIP), 0, GLsizei(33))
        glDisableClientState(UInt32(GL_VERTEX_ARRAY))
        glPopMatrix()
    }

    // MARK: - Touches -

    override func touchesBegan(_ newTouches: Set<UITouch>, with event: UIEvent?) {
        touches.removeAll()
        for touch in newTouches { touches.insert(touch) }
    }

    override func touchesMoved(_ _touches: Set<UITouch>, with event: UIEvent?) {
        touches.removeAll()
        if let newTouches = event?.allTouches {
            for touch in newTouches { touches.insert(touch) }
        }
    }

    override func touchesEnded(_ _touches: Set<UITouch>, with event: UIEvent?) {
        touches.removeAll()
    }

    @objc func pinchHandler(_ sender: UIPinchGestureRecognizer?) {
        guard let sender = sender else { return }

        if sender.state.rawValue == 1 {
            Self.pinchHandlerZoom = CGFloat(fieldOfView)
        }
        if sender.state.rawValue == 2 {
            var newFOV = Self.pinchHandlerZoom / sender.scale
            if newFOV < CGFloat(Self.FOV_MIN) {
                newFOV = CGFloat(Self.FOV_MIN)
            } else if newFOV > CGFloat(Self.FOV_MAX) {
                newFOV = CGFloat(Self.FOV_MAX)
            }
            // was setFieldOfView()
            fieldOfView = Float(newFOV)
            rebuildProjectionMatrix()
        }
        if sender.state.rawValue == 3 {
            touches.removeAll()
        }
    }


    @objc func panHandler(_ sender: UIPanGestureRecognizer?) {
        guard let sender = sender else { return }

        if sender.state.rawValue == 1 {
            var location = sender.location(in: sender.view)
            if lockPanToHorizon {
                location.y = frame.size.height / 2.0
            }
            if _vrMode {
                location.y = CGFloat((Int(location.y) % Int(frame.size.height * 0.5))) * 2.0
            }
            Self.panHandlerTouchVector = vector(fromScreenLocation: location, inAttitude: offsetMatrix)
        } else if sender.state.rawValue == 2 {
            var location = sender.location(in: sender.view)
            if lockPanToHorizon {
                location.y = frame.size.height / 2.0
            }
            if _vrMode {
                location.y = CGFloat((Int(location.y) % Int(frame.size.height * 0.5))) * 2.0
            }
            let nowVector = vector(fromScreenLocation: location, inAttitude: offsetMatrix)
            let q = GLKQuaternionFromTwoVectors(Self.panHandlerTouchVector, nowVector)
            offsetMatrix = GLKMatrix4Multiply(offsetMatrix, GLKMatrix4MakeWithQuaternion(q))
            // in progress for preventHeadTilt
            //        GLKMatrix4 mat = GLKMatrix4Multiply(_offsetMatrix, GLKMatrix4MakeWithQuaternion(q));
            //        _offsetMatrix = GLKMatrix4MakeLookAt(0, 0, 0, -mat.m02, -mat.m12, -mat.m22,  0, 1, 0);
        } else {
            touches.removeAll()
        }
    }

}

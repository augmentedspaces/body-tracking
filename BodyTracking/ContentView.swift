//
//  ContentView.swift
//  BodyTracking
//
//  Created by Nien Lam on 11/16/21.
//

import SwiftUI
import ARKit
import RealityKit
import Combine

// FILTER:
import CoreImage.CIFilterBuiltins


// MARK: - View model for handling communication between the UI and ARView.
class ViewModel: ObservableObject {
    /*
    let uiSignal = PassthroughSubject<UISignal, Never>()

    enum UISignal {
    }
     */
}


// MARK: - UI Layer.
struct ContentView : View {
    @StateObject var viewModel: ViewModel
    
    var body: some View {
        ZStack {
            // AR View.
            ARViewContainer(viewModel: viewModel)
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
    }
}


// MARK: - AR View.
struct ARViewContainer: UIViewRepresentable {
    let viewModel: ViewModel
    
    func makeUIView(context: Context) -> ARView {
        SimpleARView(frame: .zero, viewModel: viewModel)
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

class SimpleARView: ARView, ARSessionDelegate {
    var viewModel: ViewModel
    var arView: ARView { return self }
    var originAnchor: AnchorEntity!
    var subscriptions = Set<AnyCancellable>()
    
    // Dictionary for joint entities.
    var jointEntities = [SkeletonJoint:Entity]()
    
    // Rigged character entity.
    var character: BodyTrackedEntity!
    
    // FILTER:
    var context: CIContext?
    var device: MTLDevice!

    init(frame: CGRect, viewModel: ViewModel) {
        self.viewModel = viewModel
        super.init(frame: frame)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        setupScene()
        
        setupEntities()
    }

    func setupScene() {
        // Setup body tracking configuration.
        let configuration = ARBodyTrackingConfiguration()
        arView.renderOptions = [.disableDepthOfField, .disableMotionBlur]
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        // Called every frame.
        scene.subscribe(to: SceneEvents.Update.self) { event in
            self.renderLoop()
        }.store(in: &subscriptions)
        
        /*
        // Process UI signals.
        viewModel.uiSignal.sink { [weak self] in
            self?.processUISignal($0)
        }.store(in: &subscriptions)
         */
             
        // Set session delegate.
        arView.session.delegate = self
    

        // FILTER:
        arView.renderCallbacks.prepareWithDevice = { [weak self] device in
            self?.context = CIContext(mtlDevice: device)
            self?.device = device
        }
        arView.renderCallbacks.postProcess = { [weak self] context in
            self?.filter(context)
        }
    }
    
    // FILTER:
    func filter(_ context: ARView.PostProcessContext) {
        let inputImage = CIImage(mtlTexture: context.sourceColorTexture)!

        // Change filter here.
        // Reference: https://developer.apple.com/documentation/coreimage/processing_an_image_using_built-in_filters

        // Crystallize filter.
        let filter = CIFilter.crystallize()
        filter.setValue(40, forKey: kCIInputRadiusKey)
        
        /*
        // Pixellate filter
        let filter = CIFilter.pixellate()
        filter.setValue(20, forKey: kCIInputScaleKey)
        */
         
        /*
        // Sepia filter
        let filter = CIFilter.sepiaTone()
        filter.setValue(0.9, forKey: kCIInputIntensityKey)
         */
         
        /*
        // B&W filter
        let filter = CIFilter.photoEffectNoir()
         */
         
        /*
        // Bloom filter
        let filter = CIFilter.bloom()
        filter.setValue(1.0, forKey: kCIInputIntensityKey)
        filter.setValue(100, forKey: kCIInputRadiusKey)
         */

        filter.inputImage = inputImage
        
        
        let destination = CIRenderDestination(mtlTexture: context.targetColorTexture,
                                              commandBuffer: context.commandBuffer)
        
        destination.isFlipped = false
        
        _ = try? self.context?.startTask(toRender: filter.outputImage!, to: destination)
    }

    
    /*
    // Process UI signals.
    func processUISignal(_ signal: ViewModel.UISignal) {
 
    }
     */
     
    // Setup method for non image anchor entities.
    func setupEntities() {
        // Create an anchor at scene origin.
        originAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(originAnchor)

        // Create empty entity for all joints
        for joint in SkeletonJoint.allCases {
            let entity = Entity()
            jointEntities[joint] = entity
            originAnchor.addChild(entity)
        }
        
        /*
        jointEntities[SkeletonJoint.root]?.addChild(makeBoxMarker(color: .randomHue))
        jointEntities[SkeletonJoint.head_joint]?.addChild(makeBoxMarker(color: .randomHue))
        jointEntities[SkeletonJoint.left_handIndex_1_joint]?.addChild(makeBoxMarker(color: .randomHue))
         */

        // Add random colored boxes to joints.
        for joint in SkeletonJoint.mainJoints {
            let box = makeBoxMarker(color: .randomHue)
            jointEntities[joint]?.addChild(box)
        }


        // Load rigged model.
        character = try! ModelEntity.loadBodyTracked(named: "biped-robot")
        character.scale = [1, 1, 1]
        originAnchor.addChild(character)
    }

    // Render loop.
    func renderLoop() {
    }


    // Helper methods.
    func makeBoxMarker(color: UIColor) -> Entity {
        let boxMesh   = MeshResource.generateBox(size: 0.2, cornerRadius: 0.002)
        var material  = PhysicallyBasedMaterial()
        material.baseColor.tint = color
        return ModelEntity(mesh: boxMesh, materials: [material])
    }

    func makeSphereMarker(color: UIColor) -> Entity {
        let sphereMesh   = MeshResource.generateSphere(radius: 0.1)
        var material  = PhysicallyBasedMaterial()
        material.baseColor.tint = color
        return ModelEntity(mesh: sphereMesh, materials: [material])
    }


    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }

            // We can access the 3D skeleton here.
            let skeleton3D = bodyAnchor.skeleton
            
            // Transform for the anchor.
            let anchorTransform = bodyAnchor.transform

            // Update joint transforms.
            for joint in SkeletonJoint.allCases {
                jointEntities[joint]?.transform.matrix = anchorTransform * skeleton3D.modelTransform(for: joint.jointName)!
            }

            // Update rigged character position and orientation.
            let transform = Transform(matrix: anchorTransform)
            character.position = transform.translation
            character.orientation = transform.rotation
        }
    }

}


// Enum for referencing joint names.
enum SkeletonJoint: String, CaseIterable {
    case root,
         hips_joint,
         left_upLeg_joint,
         left_leg_joint,
         left_foot_joint,
         left_toes_joint,
         left_toesEnd_joint,
         right_upLeg_joint,
         right_leg_joint,
         right_foot_joint,
         right_toes_joint,
         right_toesEnd_joint,
         spine_1_joint,
         spine_2_joint,
         spine_3_joint,
         spine_4_joint,
         spine_5_joint,
         spine_6_joint,
         spine_7_joint,
         left_shoulder_1_joint,
         left_arm_joint,
         left_forearm_joint,
         left_hand_joint,
         left_handIndexStart_joint,
         left_handIndex_1_joint,
         left_handIndex_2_joint,
         left_handIndex_3_joint,
         left_handIndexEnd_joint,
         left_handMidStart_joint,
         left_handMid_1_joint,
         left_handMid_2_joint,
         left_handMid_3_joint,
         left_handMidEnd_joint,
         left_handPinkyStart_joint,
         left_handPinky_1_joint,
         left_handPinky_2_joint,
         left_handPinky_3_joint,
         left_handPinkyEnd_joint,
         left_handRingStart_joint,
         left_handRing_1_joint,
         left_handRing_2_joint,
         left_handRing_3_joint,
         left_handRingEnd_joint,
         left_handThumbStart_joint,
         left_handThumb_1_joint,
         left_handThumb_2_joint,
         left_handThumbEnd_joint,
         neck_1_joint,
         neck_2_joint,
         neck_3_joint,
         neck_4_joint,
         head_joint,
         jaw_joint,
         chin_joint,
         left_eye_joint,
         left_eyeLowerLid_joint,
         left_eyeUpperLid_joint,
         left_eyeball_joint,
         nose_joint,
         right_eye_joint,
         right_eyeLowerLid_joint,
         right_eyeUpperLid_joint,
         right_eyeball_joint,
         right_shoulder_1_joint,
         right_arm_joint,
         right_forearm_joint,
         right_hand_joint,
         right_handIndexStart_joint,
         right_handIndex_1_joint,
         right_handIndex_2_joint,
         right_handIndex_3_joint,
         right_handIndexEnd_joint,
         right_handMidStart_joint,
         right_handMid_1_joint,
         right_handMid_2_joint,
         right_handMid_3_joint,
         right_handMidEnd_joint,
         right_handPinkyStart_joint,
         right_handPinky_1_joint,
         right_handPinky_2_joint,
         right_handPinky_3_joint,
         right_handPinkyEnd_joint,
         right_handRingStart_joint,
         right_handRing_1_joint,
         right_handRing_2_joint,
         right_handRing_3_joint,
         right_handRingEnd_joint,
         right_handThumbStart_joint,
         right_handThumb_1_joint,
         right_handThumb_2_joint,
         right_handThumbEnd_joint
    
    var jointName: ARSkeleton3D.JointName {
        .init(rawValue: self.rawValue)
    }
    
    static var mainJoints: [SkeletonJoint] {
        [.left_foot_joint,
         .right_foot_joint,
         .left_hand_joint,
         .right_hand_joint,
         .head_joint,
         .left_arm_joint,
         .right_arm_joint,
         .left_leg_joint,
         .right_leg_joint,
         .neck_1_joint,
         .left_forearm_joint,
         .right_forearm_joint,
         .left_upLeg_joint,
         .right_upLeg_joint,
         .spine_5_joint,
         .spine_1_joint,
         .root]
    }
}


// Extension for creating random colors.
extension UIColor {
    static var random: UIColor {
        return .init(red: .random(in: 0...1),
                     green: .random(in: 0...1),
                     blue: .random(in: 0...1),
                     alpha: 1)
    }
    
    static var randomHue: UIColor {
        return .init(hue: .random(in: 0...1),
                     saturation: 1,
                     brightness: 1,
                     alpha: 1)
    }
}

//
//  LightPhaseManager.swift
//  Ampel Pilot
//
//  Created by Patrick Valenta on 04.10.17.
//  Copyright © 2017 Patrick Valenta. All rights reserved.
//

import Foundation
import UIKit

class LightPhaseManager {
    
    struct Detection: Comparable {
        var rect: CGRect
        var confirmed: Int
        var detectedInCurrentFrame: Bool
        var phase: Phase
        
        mutating func confirm() {
            self.confirmed += 1
            self.detectedInCurrentFrame = true
        }
        
        static func ==(lhs: Detection, rhs: Detection) -> Bool {
            return (lhs.rect.width * lhs.rect.height) < (rhs.rect.width * rhs.rect.height)
        }
        
        static func <(lhs: Detection, rhs: Detection) -> Bool {
            return (lhs.rect.width * lhs.rect.height) < (rhs.rect.width * rhs.rect.height)
        }
    }
    
    struct Feedback {
        var sound: Bool
        var vibrate: Bool
    }
    
    public enum Phase {
        case red
        case green
        case none
        
        func description() -> String {
            switch self {
            case .red: return "Red"
            case .green: return "Green"
            case .none: return "None"
            }
        }
        
        func speech() -> String {
            switch self {
            case .red: return "紅燈"
            case .green: return "綠燈"
            case .none: return ""
            }
        }
        
        func hapticInterval() -> TimeInterval {
            switch self {
            case .red: return 1.4
            case .green: return 0.35
            case .none: return 0
            }
        }
    }
    
    // Determines how often a detection needs to be validated
    // until considered for light phase determination
    var confidenceThreshold: Int!
    
    // Determines the minimum Intersect over union of a detection
    // to be validated as detected over multiple frames
    var minIOU: Float!
    
    var maxDetections: Int!
    
    var feedback: Feedback! {
        didSet {
            self.feedbackManager.stop()
        }
    }
    
    var feedbackManager: FeedbackManager!
    
    var detections: [Detection]!
    
    // Keeping the state of detections for a certain amount of frames.
    // Allows for smoother transition between changes of state
    var maxFramesWithNoDetection: Int = 5
    private var framesWithNoDetection: Int = 0
    
    var currentPhase: Phase! {
        didSet {
            if oldValue != currentPhase {
                self.onPhaseChanged(currentPhase)
            }
        }
    }
    
    init(confidenceThreshold: Int, maxDetections: Int, minIOU: Float, feedback: Feedback) {
        self.feedbackManager = FeedbackManager()
        
        self.confidenceThreshold = confidenceThreshold
        self.minIOU = minIOU
        self.maxDetections = maxDetections
        self.feedback = feedback
        
        self.detections = [Detection]()
        self.currentPhase = LightPhaseManager.Phase.none
    }
    
    func add(predictions: [YOLO.Prediction]) {
        var toBeAdded = [Detection]()
        
        for i in 0..<detections.count {
            detections[i].detectedInCurrentFrame = false
        }
        
        for prediction in predictions {
            // Check if prediction exists in detections
            let existingDetection = self.predictionExistsInDetections(prediction: prediction)
            
            if existingDetection == nil {
                let newDetection = Detection(rect: prediction.rect, confirmed: 0, detectedInCurrentFrame: true, phase: self.classIndexToPhase(prediction.classIndex))
                // -> No. detections.length < maxDetections?
                if detections.count < self.maxDetections {
                    // -> Yes. add it to detections
                    detections.append(newDetection)
                } else {
                    // -> No. add it later
                    toBeAdded.append(newDetection)
                }
            }
        }
        
        // Keeping the current state of detections if no new detections came in until
        // framesWithNoDetection exceeds maxFramesWithNoDetection
        if predictions.count == 0 && framesWithNoDetection <= maxFramesWithNoDetection  {
            // Increment backdoor count
            framesWithNoDetection += 1
        } else {
            // Remove all detections that have not been detected in this frame
            // or set detections to only have detections that have been detected in the current frame
            detections = detections.filter { $0.detectedInCurrentFrame }

            framesWithNoDetection = 0
        }
    }
    
    func determine() -> Phase {
        let qualifiedDetections = detections.filter { $0.confirmed >= self.confidenceThreshold }
        
        if qualifiedDetections.count == 0 {
            self.currentPhase = Phase.none
            return self.currentPhase
        }
        
        // Get detection with the largest area, which is most likely the closest on the frame
        if let max = detections.max() {
            self.currentPhase = max.phase
        }
        
        return self.currentPhase
    }
    
    private func predictionExistsInDetections(prediction: YOLO.Prediction) -> Detection? {
        for i in 0..<detections.count {
            let det = detections[i]
            let debugIOU = IOU(a: det.rect, b: prediction.rect)

            if debugIOU >= self.minIOU {
                detections[i].confirm()
                return det
            }
        }
        
        return nil
    }
    
    private func onPhaseChanged(_ newPhase: Phase) {
        self.feedbackManager.stop()
        
        switch newPhase {
        case .red: self.feedbackManager.start(withFeedbackType: .warning, text: Phase.red.speech(), withInterval: Phase.red.hapticInterval(), feedback: feedback)
        case .green: self.feedbackManager.start(withFeedbackType: .success, text: Phase.green.speech(), withInterval: Phase.green.hapticInterval(), feedback: feedback)
        case .none: break
        }
    }
    
    private func classIndexToPhase(_ index: Int) -> Phase {
        return index == 0 ? .red : .green
    }
}

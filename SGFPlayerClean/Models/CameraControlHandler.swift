// MARK: - File: CameraControlHandler.swift (v2.105)
import SwiftUI
import SceneKit

struct CameraControlHandler: View {
    @Binding var rotationX: Float
    @Binding var rotationY: Float
    @Binding var distance: CGFloat
    @Binding var panX: CGFloat
    @Binding var panY: CGFloat
    let sceneManager: SceneManager3D
    let onInteractionEnded: () -> Void // Signal to save state
    
    @State private var lastDragPosition: CGPoint = .zero
    @State private var isDragging: Bool = false
    
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in handleDrag(value) }
                    .onEnded { _ in
                        isDragging = false
                        onInteractionEnded()
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in handleZoom(value) }
                    .onEnded { _ in onInteractionEnded() }
            )
    }
    
    private func handleDrag(_ value: DragGesture.Value) {
        let currentPosition = value.location
        if !isDragging {
            lastDragPosition = currentPosition
            isDragging = true
            return
        }
        let delta = CGPoint(
            x: currentPosition.x - lastDragPosition.x,
            y: currentPosition.y - lastDragPosition.y
        )
        
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        let isShiftPressed = flags.contains(.shift)
        let isControlPressed = flags.contains(.control)
        
        if isShiftPressed && isControlPressed {
            // ZOOM: Ctrl + Shift + Drag
            let zoomSpeed: CGFloat = 0.1
            distance -= delta.y * zoomSpeed
            distance = max(10.0, min(100.0, distance))
        } else if isShiftPressed {
            // TRANSLATION: Shift + Drag
            // Pulling Board (+dx) -> Pushes board right
            // Pulling Board (+dy) -> Pushes board toward user
            let panSpeed: CGFloat = 0.05
            panX += delta.x * panSpeed
            panY += delta.y * panSpeed
        } else {
            // ROTATION: Pulling the board world
            let rotationSpeed: Float = 0.005
            // Mouse Down (+dy) -> Increases X rotation (tilts board forward)
            rotationX += Float(delta.y) * rotationSpeed
            // Mouse Right (+dx) -> Increases Y rotation (turns board clockwise)
            rotationY += Float(delta.x) * rotationSpeed
            
            // Limit: 0.05 (side on) to 1.57 (90 deg top down)
            rotationX = max(0.05, min(1.57, rotationX))
        }
        #endif
        
        sceneManager.updateCameraPosition(
            distance: distance,
            rotationX: rotationX,
            rotationY: rotationY,
            panX: panX,
            panY: panY
        )
        lastDragPosition = currentPosition
    }
    
    private func handleZoom(_ value: MagnificationGesture.Value) {
        let newDistance = distance / value
        distance = max(10.0, min(100.0, newDistance))
        sceneManager.updateCameraPosition(
            distance: distance,
            rotationX: rotationX,
            rotationY: rotationY,
            panX: panX,
            panY: panY
        )
    }
}

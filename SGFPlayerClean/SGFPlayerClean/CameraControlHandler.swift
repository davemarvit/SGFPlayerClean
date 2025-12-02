//
//  CameraControlHandler.swift
//  SGFPlayerClean
//
//  Created: 2025-11-28
//  Purpose: Handle 3D camera rotation, pan, and zoom gestures
//
//  ARCHITECTURE:
//  - Transparent overlay for gesture capture
//  - Updates camera parameters via binding
//  - Used by ContentView3D
//

import SwiftUI
import SceneKit

struct CameraControlHandler: View {
    @Binding var rotationX: Float
    @Binding var rotationY: Float
    @Binding var distance: CGFloat
    @Binding var panX: CGFloat
    @Binding var panY: CGFloat

    let sceneManager: SceneManager3D

    @State private var lastDragPosition: CGPoint = .zero
    @State private var isDragging: Bool = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(value)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        handleZoom(value)
                    }
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

        // Right-click or Option+drag for panning
        #if os(macOS)
        if NSEvent.modifierFlags.contains(.option) || NSEvent.pressedMouseButtons == 2 {
            // Pan camera
            let panSpeed: CGFloat = 0.05
            panX += delta.x * panSpeed
            panY -= delta.y * panSpeed  // Invert Y for natural panning
        } else {
            // Rotate camera
            let rotationSpeed: Float = 0.005
            rotationY -= Float(delta.x) * rotationSpeed  // Inverted for intuitive control
            rotationX -= Float(delta.y) * rotationSpeed

            // Clamp vertical rotation to avoid flipping
            rotationX = max(-Float.pi / 2, min(Float.pi / 2, rotationX))
        }
        #endif

        // Update scene manager
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
        // Zoom in/out by adjusting camera distance
        let newDistance = distance / value
        distance = max(10.0, min(100.0, newDistance))  // Clamp between 10-100

        sceneManager.updateCameraPosition(
            distance: distance,
            rotationX: rotationX,
            rotationY: rotationY,
            panX: panX,
            panY: panY
        )
    }
}

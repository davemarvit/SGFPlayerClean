//
//  OGSGameViewModel.swift
//  SGFPlayerClean
//
//  Created: 2025-11-24
//  Updated: 2025-12-02
//  Purpose: Bridges the OGSClient to the App/UI
//

import Foundation
import Combine

class OGSGameViewModel: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var currentGameID: Int?
    @Published var gamePhase: String = "none"
    
    // Internal
    private var ogsClient: OGSClient
    private var player: SGFPlayer
    private var timeControl: TimeControlManager
    private var cancellables: Set<AnyCancellable> = []
    
    init(ogsClient: OGSClient, player: SGFPlayer, timeControl: TimeControlManager) {
        self.ogsClient = ogsClient
        self.player = player
        self.timeControl = timeControl
        
        setupBindings()
    }
    
    private func setupBindings() {
        // Sync connection state
        ogsClient.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: \.isConnected, on: self)
            .store(in: &cancellables)
            
        // Sync Active Game ID
        ogsClient.$activeGameID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                self?.currentGameID = id
                if id != nil {
                    print("OGSVM: Game Started! ID: \(id!)")
                    self?.gamePhase = "playing"
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    
    func findMatch() {
        print("OGSVM: Requesting Automatch...")
        ogsClient.startAutomatch()
    }
}

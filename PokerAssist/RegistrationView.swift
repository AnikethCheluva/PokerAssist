/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// HomeScreenView.swift
//
// Welcome screen that guides users through the DAT SDK registration process.
// This view is displayed when the app is not yet registered.
//

import MWDATCore
import SwiftUI

struct RegistrationView: View {
    @StateObject var viewModel: WearablesManager
    
    // State for handling registration errors
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Wearable Device Setup")
                .font(.title)
                .bold()
            
            Text("Please register your wearable to continue.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: {
                viewModel.registerGlasses()
            }) {
                Text("Connect Glasses")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
        }
        // Handle callback URLs from the Meta mobile app
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        // Error handling popup
        .alert("Registration Error", isPresented: $showingError, actions: {
            Button("OK", role: .cancel) {
                // Resetting error state returns the user to the base view
                errorMessage = nil
            }
        }, message: {
            Text(errorMessage ?? "An unexpected error occurred.")
        })
    }
    
    /// Logic to process the URL returned from the Meta app
    private func handleIncomingURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
        else {
            return // Not a DAT SDK URL
        }
        
        Task {
            do {
                // Pass the callback URL to the DAT SDK for processing
                _ = try await Wearables.shared.handleUrl(url)
            } catch let error as RegistrationError {
                errorMessage = error.description
                showingError = true
            } catch {
                errorMessage = "Unknown error: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

//#Preview {
//    let manager = WearablesManager(wearables: Wearables.shared)
//    RegistrationView(viewModel: manager)
//}


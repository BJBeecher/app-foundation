//
//  SwiftUIView.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 5/5/25.
//

import SwiftUI

public struct AsyncButton<Label: View>: View {
    let role: ButtonRole?
    let priority: TaskPriority
    let feedback: SensoryFeedback?
    let action: () async -> Void
    let label: () -> Label
    
    public init(
        role: ButtonRole? = nil,
        priority: TaskPriority = .userInitiated,
        feedback: SensoryFeedback? = nil,
        @_inheritActorContext action: @Sendable @escaping () async -> Void,
        label: @escaping () -> Label
    ) {
        self.role = role
        self.priority = priority
        self.feedback = feedback
        self.action = action
        self.label = label
    }
    
    public init(
        _ label: LocalizedStringKey,
        role: ButtonRole? = nil,
        priority: TaskPriority = .userInitiated,
        feedback: SensoryFeedback? = nil,
        @_inheritActorContext action: @Sendable @escaping () async -> Void
    ) where Label == Text {
        self.init(
            role: role,
            priority: priority,
            feedback: feedback,
            action: action
        ) {
            Text(label)
        }
    }
    
    @State private var disabled = false
    @State private var feedbackTrigger = false
    
    public var body: some View {
        Button(role: role) {
            disabled = true
            
            Task(priority: priority) {
                await action()
                
                await MainActor.run {
                    if feedback != nil {
                        feedbackTrigger.toggle()
                    }
                    
                    disabled = false
                }
            }
        } label: {
            label()
        }
        .disabled(disabled)
        .sensoryFeedback(feedback ?? .selection, trigger: feedbackTrigger) { _, _ in
            feedback != nil
        }
    }
}

#Preview {
    AsyncButton("Hi", action: {})
}

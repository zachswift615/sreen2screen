import SwiftUI

struct SpecialKeyboardView: View {
    @ObservedObject var cursorState: CursorState
    let onKeyPress: (UInt16) -> Void
    let onTextInput: (String) -> Void

    @State private var showingTextInput = false

    // macOS key codes
    private let escKeyCode: UInt16 = 53
    private let tabKeyCode: UInt16 = 48
    private let deleteKeyCode: UInt16 = 51
    private let homeKeyCode: UInt16 = 115
    private let endKeyCode: UInt16 = 119
    private let pageUpKeyCode: UInt16 = 116
    private let pageDownKeyCode: UInt16 = 121
    private let leftArrowKeyCode: UInt16 = 123
    private let rightArrowKeyCode: UInt16 = 124
    private let upArrowKeyCode: UInt16 = 126
    private let downArrowKeyCode: UInt16 = 125

    // F-key codes (F1 = 122, F2 = 120, etc. - macOS uses non-sequential codes)
    private let fKeyCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    var body: some View {
        VStack(spacing: 8) {
            // Row 1: Esc + F-keys
            HStack(spacing: 4) {
                KeyButton(label: "Esc", isActive: false) {
                    onKeyPress(escKeyCode)
                }

                ForEach(1...12, id: \.self) { i in
                    KeyButton(label: "F\(i)", isActive: false) {
                        onKeyPress(fKeyCodes[i - 1])
                    }
                }
            }

            // Row 2: Modifiers + Arrows
            HStack(spacing: 4) {
                ModifierButton(label: "⌘", modifier: "cmd", cursorState: cursorState)
                ModifierButton(label: "⌥", modifier: "alt", cursorState: cursorState)
                ModifierButton(label: "⌃", modifier: "ctrl", cursorState: cursorState)
                ModifierButton(label: "⇧", modifier: "shift", cursorState: cursorState)

                Spacer().frame(width: 20)

                KeyButton(label: "←", isActive: false) {
                    onKeyPress(leftArrowKeyCode)
                }
                KeyButton(label: "→", isActive: false) {
                    onKeyPress(rightArrowKeyCode)
                }
                KeyButton(label: "↑", isActive: false) {
                    onKeyPress(upArrowKeyCode)
                }
                KeyButton(label: "↓", isActive: false) {
                    onKeyPress(downArrowKeyCode)
                }
            }

            // Row 3: Navigation keys + keyboard toggle
            HStack(spacing: 4) {
                KeyButton(label: "Tab", isActive: false) {
                    onKeyPress(tabKeyCode)
                }
                KeyButton(label: "Del", isActive: false) {
                    onKeyPress(deleteKeyCode)
                }
                KeyButton(label: "Home", isActive: false) {
                    onKeyPress(homeKeyCode)
                }
                KeyButton(label: "End", isActive: false) {
                    onKeyPress(endKeyCode)
                }
                KeyButton(label: "PgUp", isActive: false) {
                    onKeyPress(pageUpKeyCode)
                }
                KeyButton(label: "PgDn", isActive: false) {
                    onKeyPress(pageDownKeyCode)
                }

                Spacer()

                Button(action: { showingTextInput = true }) {
                    Image(systemName: "keyboard")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 40)
                        .background(Color.blue)
                        .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .sheet(isPresented: $showingTextInput) {
            TextInputView(onSubmit: { text in
                onTextInput(text)
                showingTextInput = false
            })
        }
    }
}

struct KeyButton: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(minWidth: 35, minHeight: 35)
                .background(isActive ? Color.blue : Color.gray.opacity(0.6))
                .cornerRadius(6)
        }
    }
}

struct ModifierButton: View {
    let label: String
    let modifier: String
    @ObservedObject var cursorState: CursorState

    var isActive: Bool {
        cursorState.activeModifiers.contains(modifier)
    }

    var body: some View {
        Button(action: { cursorState.toggleModifier(modifier) }) {
            Text(label)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 45, height: 40)
                .background(isActive ? Color.blue : Color.gray.opacity(0.6))
                .cornerRadius(6)
        }
    }
}

struct TextInputView: View {
    @State private var text = ""
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                TextField("Type text to send...", text: $text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                Button("Send") {
                    if !text.isEmpty {
                        onSubmit(text)
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .navigationTitle("Text Input")
            .navigationBarItems(trailing: Button("Cancel") { dismiss() })
        }
    }
}

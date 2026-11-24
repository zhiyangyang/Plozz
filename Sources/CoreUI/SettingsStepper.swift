#if canImport(SwiftUI)
import SwiftUI

/// A compact − / value / + stepper for dialing a value through an ordered set of
/// presets (e.g. skip intervals, playback speed).
///
/// A labeled TV stepper makes its entire row one native focus target. Left/Right
/// adjusts, Select increments, and Up/Down leaves. Other platforms retain their
/// labeled row and separate decrement/increment buttons.
public struct SettingsStepper<Value: Hashable>: View {
    public let options: [Value]
    @Binding public var selection: Value
    public let title: (Value) -> Text
    /// Compact spacing for tight surfaces. TV always uses the shared Settings font.
    public let compact: Bool
    /// When true the value wraps from the last option back to the first (and vice
    /// versa) and the − / + buttons never dim — for cyclic ranges like a clock
    /// time. When false (the default) the value clamps at the ends of the preset
    /// list and the end arrow dims.
    public let wraps: Bool
    /// Reports focus entering/leaving the whole control, including live previews.
    public let onFocusChange: ((Bool) -> Void)?
    private let label: LocalizedStringResource?
    private let subtitle: LocalizedStringResource?
    private let labelWidth: CGFloat
    private let rangeLabels: (LocalizedStringResource, LocalizedStringResource)?
    private let rangeMidpointLabel: LocalizedStringResource?
    private let inlineRange: Bool
    private var sizingOptions: [Value]?
    private var directionalAdjustment: ((_ forward: Bool, _ repeating: Bool) -> Void)?
    private var editingEnded: ((_ cancelled: Bool) -> Void)?
    private var swipeEditingBegan: (() -> Void)?
    private var focusRequest = 0

    @Environment(\.themePalette) private var palette
    @FocusState private var focusedButton: StepperButton?

    private enum StepperButton { case minus, plus }

    public init(
        options: [Value],
        selection: Binding<Value>,
        compact: Bool = false,
        wraps: Bool = false,
        onFocusChange: ((Bool) -> Void)? = nil,
        label: LocalizedStringResource? = nil,
        subtitle: LocalizedStringResource? = nil,
        labelWidth: CGFloat = 240,
        rangeLabels: (LocalizedStringResource, LocalizedStringResource)? = nil,
        rangeMidpointLabel: LocalizedStringResource? = nil,
        inlineRange: Bool = false,
        title: @escaping (Value) -> LocalizedStringResource
    ) {
        self.init(options: options, selection: selection, compact: compact, wraps: wraps,
                  onFocusChange: onFocusChange, label: label, subtitle: subtitle,
                  labelWidth: labelWidth, rangeLabels: rangeLabels, rangeMidpointLabel: rangeMidpointLabel,
                  inlineRange: inlineRange,
                  textTitle: { Text(title($0)) })
    }

    /// A stepper whose values are formatted CONTENT rather than copy — playback
    /// speeds, times, sizes. Spelled separately so content cannot drift into the
    /// catalog by accident.
    public init(
        options: [Value],
        selection: Binding<Value>,
        compact: Bool = false,
        wraps: Bool = false,
        onFocusChange: ((Bool) -> Void)? = nil,
        label: LocalizedStringResource? = nil,
        subtitle: LocalizedStringResource? = nil,
        labelWidth: CGFloat = 240,
        rangeLabels: (LocalizedStringResource, LocalizedStringResource)? = nil,
        rangeMidpointLabel: LocalizedStringResource? = nil,
        inlineRange: Bool = false,
        verbatimTitle: @escaping (Value) -> String
    ) {
        self.init(options: options, selection: selection, compact: compact, wraps: wraps,
                  onFocusChange: onFocusChange, label: label, subtitle: subtitle,
                  labelWidth: labelWidth, rangeLabels: rangeLabels, rangeMidpointLabel: rangeMidpointLabel,
                  inlineRange: inlineRange,
                  textTitle: { Text(verbatim: verbatimTitle($0)) })
    }

    public init(
        options: [Value],
        selection: Binding<Value>,
        compact: Bool = false,
        wraps: Bool = false,
        onFocusChange: ((Bool) -> Void)? = nil,
        label: LocalizedStringResource? = nil,
        subtitle: LocalizedStringResource? = nil,
        labelWidth: CGFloat = 240,
        rangeLabels: (LocalizedStringResource, LocalizedStringResource)? = nil,
        rangeMidpointLabel: LocalizedStringResource? = nil,
        inlineRange: Bool = false,
        textTitle: @escaping (Value) -> Text
    ) {
        self.options = options
        self._selection = selection
        self.compact = compact
        self.wraps = wraps
        self.onFocusChange = onFocusChange
        self.label = label
        self.subtitle = subtitle
        self.labelWidth = labelWidth
        self.rangeLabels = rangeLabels
        self.rangeMidpointLabel = rangeMidpointLabel
        self.inlineRange = inlineRange
        self.title = textTitle
    }

    private var index: Int { options.firstIndex(of: selection) ?? 0 }

    /// Opt in to custom TV hold behavior without installing a second input scope.
    public func onDirectionalAdjustment(
        _ action: @escaping (_ forward: Bool, _ repeating: Bool) -> Void,
        onEditingEnded: @escaping (_ cancelled: Bool) -> Void
    ) -> Self {
        var result = self
        result.directionalAdjustment = action
        result.editingEnded = onEditingEnded
        return result
    }

    /// Numeric ranges can reserve their widest values without laying out every step.
    public func reservingValueWidth(for values: [Value]) -> Self {
        var result = self
        result.sizingOptions = values
        return result
    }

    /// Opt in to distance-based TV swipes without changing taps or held arrows.
    public func swipeToAdjust(onEditingBegan: @escaping () -> Void = {}) -> Self {
        var result = self
        result.swipeEditingBegan = onEditingBegan
        return result
    }

    /// Change the request to hand TV focus to the button inside the adjustment host.
    public func focusOnRequest(_ request: Int) -> Self {
        var result = self
        result.focusRequest = request
        return result
    }

    private var rangePositions: [Int] {
        guard options.count > 21 else { return Array(options.indices) }
        return (0...20).map { Int((Double($0) * Double(options.count - 1) / 20).rounded()) }
    }
    private var canDecrement: Bool { !options.isEmpty && (wraps || index > 0) }
    private var canIncrement: Bool { !options.isEmpty && (wraps || index < options.count - 1) }

    private func stepped(by delta: Int) -> Value? {
        guard !options.isEmpty else { return nil }
        let count = options.count
        if wraps {
            return options[((index + delta) % count + count) % count]
        }
        let target = index + delta
        guard options.indices.contains(target) else { return nil }
        return options[target]
    }

    private var buttonSize: CGFloat { compact ? 46 : 72 }
    private var glyphSize: CGFloat { compact ? 16 : 26 }
    private var rowSpacing: CGFloat { compact ? 12 : 24 }
    private var valueMinWidth: CGFloat {
        compact ? 52 : 96
    }
    private var valueFont: Font {
        compact ? .body : .headline.weight(.semibold)
    }

    public var body: some View {
        if let label {
            LabeledSettingRow(label, subtitle: subtitle, labelWidth: labelWidth) {
                buttonPair
            }
        } else {
            buttonPair
        }
    }

    private var buttonPair: some View {
        HStack(spacing: rowSpacing) {
            stepButton(symbol: "minus", dimmed: !canDecrement, focus: .minus) {
                if let next = stepped(by: -1) { selection = next }
            }

            value
                .animation(.easeOut(duration: 0.16), value: index)

            stepButton(symbol: "plus", dimmed: !canIncrement, focus: .plus) {
                if let next = stepped(by: 1) { selection = next }
            }
        }
        .fixedSize()
        // Report focus entering/leaving the stepper as a whole (either button) so
        // a caller can drive a live preview while the value is being dialed.
        .onChange(of: focusedButton) { _, focused in
            onFocusChange?(focused != nil)
        }
    }

    private func step(by delta: Int) {
        if let next = stepped(by: delta) { selection = next }
    }


    private var value: some View {
        let sizingOptions = sizingOptions ?? options
        return ZStack {
            // Reserve the widest option without exposing hidden sizing labels to VoiceOver.
            ForEach(sizingOptions.indices, id: \.self) { i in
                valueLabel(title(sizingOptions[i])).hidden().accessibilityHidden(true)
            }
            valueLabel(title(selection))
                .transaction { $0.animation = nil }
        }
        .frame(minWidth: valueMinWidth)
    }

    private func valueLabel(_ text: Text) -> some View {
        text
            .font(valueFont)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(palette.primaryText)
    }

    private func stepButton(symbol: String, dimmed: Bool, focus: StepperButton, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyphSize, weight: .semibold))
                .frame(width: buttonSize, height: buttonSize)
                // Dim the glyph at the ends, but keep the button focusable so the
                // left-exit point stays consistent (always the − button).
                .opacity(dimmed ? 0.35 : 1)
        }
        .buttonStyle(StepperButtonStyle())
        .focused($focusedButton, equals: focus)
    }
}

/// Round step button mirroring the segmented picker's theme-aware focus thumb:
/// a subtle neutral chip at rest, the bright inverted thumb (white-on-dark /
/// black-on-light) when focused. Public so compact ± steppers built outside this
/// component (e.g. the in-player subtitle-sync control) share the exact look.
public struct StepperButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        StepperButtonBody(configuration: configuration)
    }

    private struct StepperButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.themePalette) private var palette

        private var fill: Color {
            if isFocused { return colorScheme == .dark ? .white : .black }
            return palette.primaryText.opacity(0.14)
        }
        private var foreground: Color {
            if isFocused { return colorScheme == .dark ? .black : .white }
            return palette.primaryText
        }

        var body: some View {
            configuration.label
                .foregroundStyle(foreground)
                .background(
                    Circle()
                        .fill(fill)
                        .shadow(
                            color: .black.opacity(isFocused ? 0.25 : 0),
                            radius: isFocused ? 8 : 0,
                            y: isFocused ? 3 : 0
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.94 : (isFocused ? 1.08 : 1.0))
                .animation(.easeOut(duration: 0.16), value: isFocused)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
#endif

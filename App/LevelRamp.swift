import Foundation

/// A level that glides to a target over a few seconds (a fade). Each new ramp starts from wherever the last one
/// got to, so a fade that is interrupted never jumps.
@MainActor
final class LevelRamp {
    private(set) var value: Float
    private let apply: (Float) -> Void
    private var task: Task<Void, Never>?

    init(initial: Float, apply: @escaping (Float) -> Void) {
        value = initial
        self.apply = apply
        apply(initial)
    }

    /// Glides to `target` over `seconds` along a smooth curve; `done` runs when it gets there (not if it is
    /// interrupted by another ramp or `jump`).
    func ramp(to target: Float, over seconds: Double, then done: (@MainActor () -> Void)? = nil) {
        task?.cancel()
        let start = value
        guard seconds > 0, start != target else {
            value = target
            apply(target)
            task = nil
            done?()
            return
        }
        let began = Date()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let f = Float(min(1, Date().timeIntervalSince(began) / seconds))
                let eased = f * f * (3 - 2 * f)
                self.value = start + (target - start) * eased
                self.apply(self.value)
                if f >= 1 { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard !Task.isCancelled else { return }
            self?.task = nil
            done?()
        }
    }

    /// Sets the level at once, cancelling any ramp.
    func jump(to target: Float) {
        task?.cancel()
        task = nil
        value = target
        apply(target)
    }
}

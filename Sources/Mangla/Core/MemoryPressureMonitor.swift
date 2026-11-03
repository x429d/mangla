import Dispatch
import Foundation

/// Watches the system memory-pressure signal so the reader can drop decoded
/// pages without closing the session. The dispatch source is retained for the
/// lifetime of the monitor and cancelled on shutdown.
@MainActor
final class MemoryPressureMonitor {
    private var source: DispatchSourceMemoryPressure?
    private let onPressure: @Sendable () -> Void

    init(onPressure: @escaping @Sendable () -> Void) {
        self.onPressure = onPressure
    }

    func start() {
        guard source == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler(handler: onPressure)
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}

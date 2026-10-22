import Foundation
import DiskArbitration
import IOKit

/// Notification registration and teardown are serialized with callbacks on one dedicated queue.
public final class DeviceMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "KindleMargin.discovery.events", qos: .utility)
    private var session: DASession?
    private var port: IONotificationPortRef?
    private var added: io_iterator_t = 0
    private var removed: io_iterator_t = 0
    private let changed: @Sendable (Bool) -> Void
    public init(changed: @escaping @Sendable (Bool) -> Void) { self.changed = changed }
    public func start() {
        queue.async {
            guard self.session == nil else { return }
            let context = Unmanaged.passUnretained(self).toOpaque()
            if let session = DASessionCreate(kCFAllocatorDefault) {
                self.session = session
                DARegisterDiskAppearedCallback(session, nil, { _, context in
                    if let context { Unmanaged<DeviceMonitor>.fromOpaque(context).takeUnretainedValue().changed(false) }
                }, context)
                DARegisterDiskDisappearedCallback(session, nil, { _, context in
                    if let context { Unmanaged<DeviceMonitor>.fromOpaque(context).takeUnretainedValue().changed(true) }
                }, context)
                DASessionSetDispatchQueue(session, self.queue)
            }
            if let port = IONotificationPortCreate(kIOMainPortDefault) {
                self.port = port; IONotificationPortSetDispatchQueue(port, self.queue)
                let callback: IOServiceMatchingCallback = { context, iterator in
                    var object = IOIteratorNext(iterator)
                    while object != 0 { IOObjectRelease(object); object = IOIteratorNext(iterator) }
                    if let context { Unmanaged<DeviceMonitor>.fromOpaque(context).takeUnretainedValue().changed(true) }
                }
                IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"), callback, context, &self.added)
                IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice"), callback, context, &self.removed)
                callback(context, self.added); callback(context, self.removed)
            }
            self.changed(false)
        }
    }
    public func stop() {
        queue.sync {
            if let session { DASessionSetDispatchQueue(session, nil) }; self.session = nil
            if added != 0 { IOObjectRelease(added); added = 0 }; if removed != 0 { IOObjectRelease(removed); removed = 0 }
            if let port { IONotificationPortDestroy(port) }; self.port = nil
        }
    }
}

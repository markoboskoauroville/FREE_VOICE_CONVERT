// Meters.swift: what the machine is doing while it converts (Marko, 1.11.2026: "Imagine my meters in my application,
// TTT Mini, which is going horizontal. On one side is CPU, and on the other is GPU ... memory available (RAM) and GPU
// memory available. ..."). Read once a second, nothing installed, no permission needed:
//   CPU  host_statistics(HOST_CPU_LOAD_INFO), the busy share of all cores since the last reading
//   GPU  IOAccelerator's PerformanceStatistics "Device Utilization %"
//   RAM  free + inactive + purgeable + speculative pages (what macOS can hand out now)
//   GPU memory  Metal's recommendedMaxWorkingSetSize less IOAccelerator's "In use system memory" (unified memory)
import SwiftUI
import Foundation
import IOKit
import Metal

final class SysMeters: ObservableObject {
    @Published var cpu: Double = 0          // 0...1
    @Published var gpu: Double = 0          // 0...1
    @Published var ramFree: Double = 0      // bytes
    @Published var ramTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    @Published var vramFree: Double = 0     // bytes
    @Published var vramTotal: Double = Double(MTLCreateSystemDefaultDevice()?.recommendedMaxWorkingSetSize ?? 0)
    private var last: host_cpu_load_info?
    private var timer: Timer?

    init() {
        read()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.read() }
    }

    func read() {
        // CPU
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if r == KERN_SUCCESS {
            if let l = last {
                let u = Double(info.cpu_ticks.0 &- l.cpu_ticks.0), s = Double(info.cpu_ticks.1 &- l.cpu_ticks.1)
                let i = Double(info.cpu_ticks.2 &- l.cpu_ticks.2), n = Double(info.cpu_ticks.3 &- l.cpu_ticks.3)
                let t = u + s + i + n
                if t > 0 { cpu = (u + s + n) / t }
            }
            last = info
        }
        // RAM
        var vm = vm_statistics64()
        var vc = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vc)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vc) }
        }
        if vr == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            ramFree = Double(UInt64(vm.free_count) + UInt64(vm.inactive_count) + UInt64(vm.purgeable_count) + UInt64(vm.speculative_count)) * page
        }
        // GPU
        var it: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS {
            var svc = IOIteratorNext(it)
            while svc != 0 {
                if let p = IORegistryEntryCreateCFProperty(svc, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] {
                    if let u = p["Device Utilization %"] as? Int { gpu = Double(u) / 100 }
                    if let used = p["In use system memory"] as? Int, vramTotal > 0 { vramFree = max(0, vramTotal - Double(used)) }
                }
                IOObjectRelease(svc)
                svc = IOIteratorNext(it)
            }
            IOObjectRelease(it)
        }
    }
}

/// One cell of the table: the label above, the value, a hairline under it that fills (a progress line).
/// Green, amber over 70 %, red over 90 % when `warn` (the machine's load); otherwise always green (progress).
struct Cell: View {
    let label: String; let value: String; let fill: Double; var warn = false; var invert = false
    var color: Color {
        guard warn else { return .green }
        let load = invert ? 1 - fill : fill
        return load > 0.9 ? .red : load > 0.7 ? .orange : .green
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.7)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.12))
                    Rectangle().fill(color).frame(width: max(1, g.size.width * min(max(fill, 0), 1)))
                        .animation(.easeOut(duration: 0.25), value: fill)
                }
            }.frame(height: 1)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore).accessibilityLabel("\(label) \(value)")
    }
}

func gb(_ b: Double) -> String { String(format: "%.1f GB", b / 1_073_741_824) }

func clock(_ s: Double) -> String {
    let t = max(0, Int(s.rounded()))
    return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
}

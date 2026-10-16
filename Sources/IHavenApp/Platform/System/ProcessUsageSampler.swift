import Foundation

/// 进程占用采样：CPU% / 进程内存 / 系统内存压力（PRD F10 的「实时占用面板」）。
///
/// ⚠️ **CPU 必须用 `getrusage`，不能用 `proc_pid_rusage`**。后者的 `ri_user_time` /
/// `ri_system_time` 在 `sys/resource.h:423` 注释里写的是纳秒，**在 Apple Silicon 上实际是
/// mach_absolute_time tick**（实测 timebase 125/3，1 tick = 41.67ns）。按纳秒解释会把 CPU%
/// 缩小 41.7 倍：单线程烧满 1.5 秒，按 tick 换算得 100.0%，按纳秒算只得 2.4%。
/// `getrusage` 的 `ru_utime` / `ru_stime` 是 `timeval`（微秒），单位正确且最便宜（实测 0.0004ms/次）。
///
/// ⚠️ **`MACH_TASK_VM_INFO` / `MACH_TASK_VM_INFO_COUNT` 宏没有导入 Swift**，要手写
/// `task_flavor_t(TASK_VM_INFO)`（值 22）与 `MemoryLayout<task_vm_info_data_t>` 算 count。
///
/// ⚠️ **不做「显存」那一格**：Apple Silicon 是统一内存架构，实测 `IOServiceGetMatchingServices
/// ("IOAccelerator")` 只有一条 `Apple M4`、属性里没有任何 VRAM 字段。没有可测量的独立显存，
/// 硬做一格只能填假数据。改成「帧序列磁盘占用」——它才真正解释「动态壁纸为什么费资源」。
struct ProcessUsageSampler {
    private var lastCPUSeconds: Double?
    private var lastSampleTime = Date()

    /// 采样一次；`elapsed` 为距上次采样的墙钟秒数，用于把 CPU 时间差折算成百分比。
    mutating func sample(elapsed: Double) -> ProcessUsage {
        let cpu = cpuSeconds()
        defer { lastCPUSeconds = cpu; lastSampleTime = Date() }
        let previous = lastCPUSeconds
        let cpuPercent: Double
        if let previous, elapsed > 0 {
            // 多核可超过 100%（实测 4 线程各烧 2s 得 399.7%，理论 400%）——这不是 bug，
            // 「占用了几颗核」本来就该这么表达。
            cpuPercent = min(1000, (cpu - previous) / elapsed * 100)
        } else {
            cpuPercent = 0
        }
        return ProcessUsage(cpuPercent: max(0, cpuPercent),
                            processBytes: processFootprintBytes(),
                            systemPressurePercent: systemPressurePercent())
    }

    // MARK: - 私有

    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    /// `phys_footprint`：与活动监视器「内存」列同口径。
    /// （`mach_task_basic_info.resident_size` 偏大，含共享与压缩页，实测 5.93MB vs 1.88MB。）
    private func processFootprintBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    /// 系统内存压力：`1 - (free + inactive) / total`。Apple 未公开「内存压力百分比」API，
    /// 这是可用公开 vm statistics 推出的最接近量。
    private func systemPressurePercent() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(host, Int32(HOST_VM_INFO64), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        var pageSize = vm_size_t()
        host_page_size(host, &pageSize)
        let page = UInt64(pageSize)
        let total = UInt64(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        let available = (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * page
        return min(100, max(0, (1 - Double(available) / Double(total)) * 100))
    }
}

/// 一次占用读数。
struct ProcessUsage: Sendable, Equatable {
    var cpuPercent: Double
    var processBytes: Int64
    var systemPressurePercent: Double
}

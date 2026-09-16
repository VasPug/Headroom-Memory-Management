import Foundation
import HeadroomCore

func printLiveState() {
let s = PressureMonitor.currentSample()
let r = PressureMonitor.evaluate(s)
    func gb(_ b: Int64) -> String { String(format: "%.1f GB", Double(b)/1_073_741_824) }
print("free now:      \(gb(s.availableBytes)) of \(gb(s.totalBytes))   used \(Int(s.usageRatio*100))%")
print("swap now:      \(gb(s.swapUsedBytes))")
print("level now:     \(r.level)")
print("")
let total = Double(s.totalBytes)
print("warns at:      free <= \(String(format: "%.1f GB", total*0.30/1_073_741_824)) or swap >= 1.0 GB")
print("critical at:   free <= \(String(format: "%.1f GB", total*0.15/1_073_741_824)) or swap >= 4.0 GB")
print("re-arms when:  free >  \(String(format: "%.1f GB", total*(1-NudgePolicy.rearmRatio)/1_073_741_824)) AND swap < 1.0 GB")
}

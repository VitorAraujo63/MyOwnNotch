//
//  BatteryDetails.swift
//  MyOwnNotch
//
//  Leitura detalhada da bateria (IOKit / AppleSmartBattery): saúde, ciclos, tensão,
//  potência, tempo restante, adaptador e modo econômico.
//

import SwiftUI
import IOKit
import IOKit.ps

struct BatteryDetails: Equatable {
    var isCharging = false          // carregando de fato
    var isPlugged = false           // na tomada
    var isFullyCharged = false
    var timeMinutes: Int? = nil     // até esvaziar ou até carregar
    var watts: Double = 0           // potência atual (entrada ou consumo)
    var healthPercent: Int? = nil   // capacidade máxima vs. projeto
    var cycles: Int? = nil
    var designCycles: Int? = nil
    var voltage: Double? = nil      // V
    var temperature: Double? = nil  // °C (nem todo Mac expõe)
    var adapterWatts: Int? = nil
    var currentMAh: Int? = nil
    var fullMAh: Int? = nil
    var lowPowerMode = false

    static func read() -> BatteryDetails {
        var d = BatteryDetails()
        d.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // Tempo restante estimado pelo sistema (segundos)
        let est = IOPSGetTimeRemainingEstimate()

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return d }
        defer { IOObjectRelease(service) }

        var cf: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &cf, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = cf?.takeRetainedValue() as? [String: Any] else { return d }

        func int(_ key: String, in dict: [String: Any]? = nil) -> Int? {
            ((dict ?? props)[key] as? NSNumber)?.intValue
        }
        func signed(_ key: String) -> Int64? {
            (props[key] as? NSNumber).map { Int64(bitPattern: $0.uint64Value) }
        }

        let battery = props["BatteryData"] as? [String: Any]
        d.isCharging = (props["IsCharging"] as? Bool) ?? false
        d.isPlugged = (props["ExternalConnected"] as? Bool) ?? false
        d.isFullyCharged = (props["FullyCharged"] as? Bool) ?? false
        d.cycles = int("CycleCount")
        d.designCycles = int("DesignCycleCount9C")

        if let mv = int("Voltage"), mv > 0 { d.voltage = Double(mv) / 1000 }
        if let ma = signed("Amperage"), let v = d.voltage { d.watts = abs(Double(ma) / 1000 * v) }

        let design = int("DesignCapacity", in: battery) ?? int("DesignCapacity")
        let nominal = int("NominalChargeCapacity", in: battery) ?? int("AppleRawMaxCapacity")
        if let design, design > 0, let nominal, nominal > 0 {
            d.healthPercent = min(100, Int((Double(nominal) / Double(design) * 100).rounded()))
        }
        d.fullMAh = int("FullChargeCapacity", in: battery) ?? nominal
        d.currentMAh = int("RemainingCapacity", in: battery) ?? int("AppleRawCurrentCapacity")

        // Temperatura (centésimos de °C); em alguns modelos a chave não existe
        if let t = int("Temperature"), t > 0 { d.temperature = Double(t) / 100 }

        if let adapter = props["AdapterDetails"] as? [String: Any], let w = int("Watts", in: adapter), w > 0 {
            d.adapterWatts = w
        }

        // Tempo: carregando → AvgTimeToFull; na bateria → estimativa do sistema
        if d.isCharging, let m = int("AvgTimeToFull"), m > 0, m < 65535 { d.timeMinutes = m }
        else if !d.isPlugged, est > 0 { d.timeMinutes = Int(est / 60) }
        return d
    }
}

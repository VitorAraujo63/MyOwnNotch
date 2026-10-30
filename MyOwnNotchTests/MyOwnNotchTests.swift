import XCTest
@testable import MyOwnNotch

final class NotchMetricsTests: XCTestCase {
    let notch = NotchMetrics(hardwareWidth: 200, hardwareHeight: 32, hasNotch: true)

    func testIdleSemAtividadeEhOTamanhoDoHardware() {
        let s = notch.islandSize(for: .idle, hasActivity: false)
        XCTAssertEqual(s, CGSize(width: 200, height: 32))
    }
    func testIdleComAtividadeAdicionaDuasAsas() {
        let s = notch.islandSize(for: .idle, hasActivity: true)
        XCTAssertEqual(s.width, 200 + 2 * NotchMetrics.wingWidth)
    }
    func testCompactTemLarguraMinima() {
        let small = NotchMetrics(hardwareWidth: 100, hardwareHeight: 24, hasNotch: false)
        XCTAssertEqual(small.islandSize(for: .compact, hasActivity: false).width, 260)
        XCTAssertEqual(notch.islandSize(for: .compact, hasActivity: false).height, 32 + NotchMetrics.compactStripHeight)
    }
    func testExpandedLarguras() {
        XCTAssertEqual(notch.islandSize(for: .expanded, hasActivity: false, module: .media).width, 640)
        XCTAssertEqual(notch.islandSize(for: .expanded, hasActivity: false, module: .terminal).width, 660)
        XCTAssertEqual(notch.islandSize(for: .expanded, hasActivity: false, module: .agent).height,
                       32 + NotchMetrics.terminalContentHeight)
    }
    func testExpandedCabeEmTela1280() {
        let wide = NotchMetrics(hardwareWidth: 250, hardwareHeight: 38, hasNotch: true)
        for m in NotchModule.userModules {
            let w = wide.islandSize(for: .expanded, hasActivity: true, module: m).width + 2 * NotchMetrics.windowPadding
            XCTAssertLessThanOrEqual(w, 1280, "\(m)")
        }
    }
    func testRaiosCrescemComOEstado() {
        XCTAssertLessThan(notch.bottomRadius(for: .idle), notch.bottomRadius(for: .expanded))
        XCTAssertLessThan(notch.topRadius(for: .idle), notch.topRadius(for: .expanded))
    }
}

final class WeatherTests: XCTestCase {
    func testSymbols() {
        XCTAssertEqual(NotchViewModel.weatherSymbol("Sunny", isDay: true), "sun.max.fill")
        XCTAssertEqual(NotchViewModel.weatherSymbol("Clear", isDay: false), "moon.stars.fill")
        XCTAssertEqual(NotchViewModel.weatherSymbol("Light rain shower", isDay: true), "cloud.rain.fill")
        XCTAssertEqual(NotchViewModel.weatherSymbol("Thundery outbreaks", isDay: true), "cloud.bolt.rain.fill")
        XCTAssertEqual(NotchViewModel.weatherSymbol("Heavy snow", isDay: true), "snowflake")
        XCTAssertEqual(NotchViewModel.weatherSymbol("Mist", isDay: true), "cloud.fog.fill")
        XCTAssertEqual(NotchViewModel.weatherSymbol("Overcast", isDay: true), "cloud.fill")
        XCTAssertEqual(NotchViewModel.weatherSymbol("???", isDay: true), "cloud.sun.fill")
        XCTAssertEqual(NotchViewModel.weatherSymbol("???", isDay: false), "cloud.moon.fill")
    }

    static let fixture = """
    {"current_condition":[{"temp_C":"23","FeelsLikeC":"25","humidity":"70","windspeedKmph":"11",
      "isdaytime":"yes","weatherDesc":[{"value":"Partly cloudy"}]}],
     "nearest_area":[{"areaName":[{"value":"Sao Paulo"}]}],
     "weather":[{"date":"2026-10-24","maxtempC":"28","mintempC":"18","hourly":[{},{},{},{},{"weatherDesc":[{"value":"Sunny"}]}]},
                {"date":"2026-10-25","maxtempC":"26","mintempC":"17","hourly":[{"weatherDesc":[{"value":"Light rain"}]}]}]}
    """

    func testParseOK() throws {
        let w = try XCTUnwrap(NotchViewModel.parseWeather(Data(Self.fixture.utf8)))
        XCTAssertEqual(w.temp, "23°C")
        XCTAssertEqual(w.feelsLike, "25°")
        XCTAssertEqual(w.humidity, "70%")
        XCTAssertEqual(w.wind, "11 km/h")
        XCTAssertEqual(w.high, "28°")
        XCTAssertEqual(w.low, "18°")
        XCTAssertTrue(w.isDay)
        XCTAssertEqual(w.locationName, "Sao Paulo")
        XCTAssertEqual(w.forecast.count, 2)
        XCTAssertEqual(w.forecast[0].label, "Hoje")
        XCTAssertEqual(w.forecast[0].icon, "sun.max.fill")
        XCTAssertEqual(w.forecast[1].icon, "cloud.rain.fill")
    }
    func testParseMalformado() {
        XCTAssertNil(NotchViewModel.parseWeather(Data("not json".utf8)))
        XCTAssertNil(NotchViewModel.parseWeather(Data("{}".utf8)))
        XCTAssertNil(NotchViewModel.parseWeather(Data(#"{"current_condition":[]}"#.utf8)))
    }
    func testParseCamposAusentesUsaPlaceholders() throws {
        let w = try XCTUnwrap(NotchViewModel.parseWeather(Data(#"{"current_condition":[{}]}"#.utf8)))
        XCTAssertEqual(w.temp, "--°C")
        XCTAssertEqual(w.desc, "Desconhecido")
        XCTAssertTrue(w.forecast.isEmpty)
    }
    func testWeatherURLCodificaLocal() throws {
        let u = try XCTUnwrap(NotchViewModel.weatherURL(location: "São Paulo/../x?y=1"))
        XCTAssertEqual(u.host, "wttr.in")
        XCTAssertEqual(URLComponents(url: u, resolvingAgainstBaseURL: false)?.percentEncodedPath.filter { $0 == "/" }.count, 1)   // só a barra inicial
        XCTAssertEqual(URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.count, 1)
        XCTAssertNotNil(NotchViewModel.weatherURL(location: ""))
    }
}

final class GitHubTests: XCTestCase {
    func testUsername() {
        for ok in ["octocat", "a", "Vitor-Araujo63", String(repeating: "a", count: 39)] {
            XCTAssertTrue(GitHubService.isValidUsername(ok), ok)
        }
        for bad in ["", " ", "a b", "a/b", "a?b=1", "../x", "user\n", String(repeating: "a", count: 40), "é"] {
            XCTAssertFalse(GitHubService.isValidUsername(bad), bad)
        }
    }
    func testParse() {
        let html = """
        <td data-date="2026-01-05" id="contribution-day-component-0-1" data-level="2" class="x"></td>
        <td data-date="2026-01-04" id="contribution-day-component-0-0" data-level="0" class="x"></td>
        <tool-tip for="contribution-day-component-0-1" class="y">16 contributions on January 5th.</tool-tip>
        <tool-tip for="contribution-day-component-0-0" class="y">No contributions on January 4th.</tool-tip>
        """
        let days = GitHubService.parse(html)
        XCTAssertEqual(days, [GitHubDay(date: "2026-01-04", count: 0, level: 0),
                              GitHubDay(date: "2026-01-05", count: 16, level: 2)])
    }
    func testParseLixo() {
        XCTAssertTrue(GitHubService.parse("").isEmpty)
        XCTAssertTrue(GitHubService.parse("<html>404</html>").isEmpty)
    }
}

final class ContractsTests: XCTestCase {
    func testLiveActivityPrioridade() {
        let shuffled: [LiveActivity] = [.charging, .media, .timer, .privacy, .meeting, .timerEnding]
        XCTAssertEqual(shuffled.sorted(), [.privacy, .timerEnding, .meeting, .timer, .media, .charging])
        XCTAssertEqual(LiveActivity.allCases.count, 6)
    }
    func testLiveActivityModulo() {
        XCTAssertEqual(LiveActivity.timerEnding.module, .timer)
        XCTAssertEqual(LiveActivity.timer.module, .timer)
        XCTAssertEqual(LiveActivity.meeting.module, .calendar)
        XCTAssertEqual(LiveActivity.charging.module, .battery)
    }
    func testStorageKeyUnicoEEstavel() {
        let all = NotchModule.userModules + [.none, .volume]
        let keys = all.map(\.storageKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        let roundTrip = Set(NotchModule.userModules.filter { Set(keys).contains($0.storageKey) })
        XCTAssertEqual(roundTrip, Set(NotchModule.userModules))
        XCTAssertEqual(NotchModule.systemMonitor.storageKey, "systemMonitor")
    }
    func testLoadStateEquatable() {
        XCTAssertEqual(LoadState.failed("x"), .failed("x"))
        XCTAssertNotEqual(LoadState.failed("x"), .failed("y"))
    }
}

final class ViewModelHiddenModulesTests: XCTestCase {
    func testVisibleModulesRespeitaOcultos() {
        let vm = NotchViewModel()
        let saved = vm.hiddenModules
        defer { vm.hiddenModules = saved }
        vm.hiddenModules = [.media, .timer]
        XCTAssertFalse(vm.visibleModules.contains(.media))
        XCTAssertFalse(vm.isModuleVisible(.timer))
        XCTAssertTrue(vm.isModuleVisible(.battery))
        vm.hiddenModules = Set(NotchModule.userModules)
        XCTAssertTrue(vm.visibleModules.isEmpty)
    }
}

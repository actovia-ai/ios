import Foundation
import Models
import Testing

private typealias F = ToolResultFixtures

private func json(_ text: String) -> JSONValue { F.json(text) }

@Suite("Tool results: files")
struct FileToolResultTests {
    @Test("read_file's details decode with the desktop's fields; unknown keys are ignored")
    func readFile() throws {
        let file = try #require(ReadFileResult(json: json(F.readmeShort)))
        #expect(file.path == "/Users/me/Code/actovia/README.md")
        #expect(file.size == 612)
        #expect(file.content.hasPrefix("# Actovia\n\nA desktop AI chat app"))
        #expect(ReadFileResult(json: json(#"{"path":"/a","content":"x","extra":{"n":1}}"#))?.size == nil)
        #expect(ReadFileResult(json: json(#"{"path":"/a"}"#)) == nil)
        #expect(ReadFileArguments(json: json(#"{"path":"/a","encoding":"base64"}"#))?.encoding == "base64")
    }

    @Test("write_file's arguments and details, including an append")
    func writeFile() throws {
        let arguments = try #require(WriteFileArguments(json: json(F.writeArguments)))
        #expect(arguments.path.hasSuffix("trip-plan.md"))
        #expect(arguments.content.hasPrefix("# Kyoto, 3 days"))
        #expect(!arguments.append)
        let written = try #require(WriteFileResult(json: json(F.writeDetails)))
        #expect(written.bytes == 284)
        #expect(!written.appended)
        #expect(WriteFileResult(json: json(F.appendDetails))?.appended == true)
        #expect(WriteFileResult(json: json(#"{"bytes":3}"#)) == nil)
    }

    @Test("edit_file reads old_string / new_string / replace_all, and the result's counts")
    func editFile() throws {
        let arguments = try #require(EditFileArguments(json: json(F.editArguments)))
        #expect(arguments.oldString.contains("var maxAttempts = 3"))
        #expect(arguments.newString.contains("var backoff = 2.0"))
        #expect(!arguments.replaceAll)
        let result = try #require(EditFileResult(json: json(F.editDetails)))
        #expect(result.replacements == 1)
        #expect(result.linesBefore == 42)
        #expect(result.linesAfter == 43)
        #expect(EditFileArguments(json: json(F.replaceAllArguments))?.replaceAll == true)
        #expect(EditFileResult(json: json(F.replaceAllDetails))?.replacements == 4)
    }
}

@Suite("Tool results: computer_use and deep_research")
struct SessionToolResultTests {
    @Test("a live frame, a frame waiting for the user, the end and an error are told apart")
    func computerUse() throws {
        guard case .frame(let running)? = ComputerUseDetails(json: json(F.computerRunning)) else {
            Issue.record("not a frame")
            return
        }
        #expect(running.step == 4)
        #expect(running.sessionId == "cu_7f3a")
        #expect(running.action == "click File ▸ Export To ▸ PDF…")
        #expect(running.thumbnail == "<base64 png>")
        #expect(running.awaitingHumanQuestion == nil)
        guard case .frame(let asking)? = ComputerUseDetails(json: json(F.computerAsking)) else {
            Issue.record("not a frame")
            return
        }
        #expect(asking.awaitingHumanQuestion?.hasPrefix("Numbers asks for a password") == true)
        guard case .finished(let done)? = ComputerUseDetails(json: json(F.computerDone)) else {
            Issue.record("not finished")
            return
        }
        #expect(done.outcome == "success")
        #expect(done.steps == 9)
        #expect(done.summary.hasPrefix("Exported"))
        guard case .finished(let stuck)? = ComputerUseDetails(json: json(F.computerStuck)) else {
            Issue.record("not finished")
            return
        }
        #expect(stuck.outcome == "stuck")
        #expect(stuck.steps == 25)
        #expect(ComputerUseDetails(json: json(F.computerError)) == .failed("not-allowed"))
        #expect(ComputerUseDetails(json: json("{}")) == nil)
    }

    @Test("a last frame that carries an outcome is still a frame")
    func frameWithOutcome() {
        guard case .frame(let frame)? = ComputerUseDetails(json: json(#"{"step":9,"outcome":"success"}"#)) else {
            Issue.record("not a frame")
            return
        }
        #expect(frame.step == 9)
    }

    @Test("computer_use arguments name the task and the target app")
    func computerArguments() throws {
        let arguments = try #require(ComputerUseArguments(json: json(#"{"task":"Export","target":"Numbers"}"#)))
        #expect(arguments.task == "Export")
        #expect(arguments.target == "Numbers")
    }

    @Test("deep_research's result is the job id, or the error it failed with")
    func deepResearch() {
        #expect(DeepResearchResult(json: json(F.researchStarted)) == .started(id: "dr_42"))
        #expect(DeepResearchResult(json: json(#"{"error":"No Serper key"}"#)) == .failed("No Serper key"))
        #expect(DeepResearchResult(json: json(#"{"id":""}"#)) == nil)
        #expect(DeepResearchArguments(json: json(#"{"subject":"Cities"}"#))?.subject == "Cities")
    }
}

@Suite("Tool results: weather")
struct WeatherResultTests {
    @Test("the prototype's week decodes: now, seven days of 24 hours, ISO local times")
    func week() throws {
        let weather = try #require(WeatherResult(json: json(F.weather(location: "Shanghai, China", isDay: true))))
        #expect(weather.location == "Shanghai, China")
        #expect(weather.current.tempC == "22")
        #expect(weather.current.windDir == "SW")
        #expect(weather.current.observedAt == "2026-09-24T14:15")
        #expect(weather.current.isDay == true)
        #expect(weather.forecast.count == 7)
        #expect(weather.forecast.allSatisfy { $0.hourly.count == 24 })
        #expect(weather.forecast[1].weatherCode == "63")
        #expect(weather.forecast[0].hourly[6].time == "2026-09-24T06:00")
        #expect(weather.forecast[0].sunrise == "2026-09-24T06:02")
    }

    @Test("numbers sent as numbers read as the strings the desktop sends; a missing isDay reads as day")
    func lenientNumbers() throws {
        let weather = try #require(
            WeatherResult(json: json(#"{"location":"X","current":{"tempC":22,"precipMM":0.5,"weatherCode":63},"forecast":[{"date":"2026-09-24","hourly":[{"time":"2026-09-24T03:00","tempC":9}]}]}"#)))
        #expect(weather.current.tempC == "22")
        #expect(weather.current.precipMM == "0.5")
        #expect(weather.current.weatherCode == "63")
        #expect(weather.current.isDay == true)
        #expect(weather.forecast.first?.hourly.first?.tempC == "9")
    }

    @Test("without a current reading it is not a weather result")
    func needsCurrent() {
        #expect(WeatherResult(json: json(#"{"location":"X","forecast":[]}"#)) == nil)
        #expect(WeatherResult(json: .string("Sunny")) == nil)
    }
}

@Suite("Tool results: image_generation")
struct ImageGenerationResultTests {
    @Test("the prototype rows read their media file and revised prompt")
    func prototypeRows() throws {
        let one = try #require(ImageGenerationResult(json: json(F.imageOne)))
        #expect(one.images.count == 1)
        #expect(one.images[0].mediaId == "img-1.png")
        #expect(one.images[0].chatId == "c1")
        #expect(one.images[0].mimeType == "image/png")
        #expect(one.images[0].revisedPrompt?.hasPrefix("A flat vector poster") == true)
        #expect(ImageGenerationResult(json: json(F.imageTwo))?.images.map(\.revisedPrompt) == ["Variant one.", "Variant two."])
    }

    @Test("the size is kept; a row without a mediaId or chatId reads with them nil; no images array is no result")
    func rows() throws {
        let result = try #require(
            ImageGenerationResult(
                json: json(#"{"size":"1024x1536","images":[{"mediaId":"md_1","chatId":"c1","mimeType":"image/png"},{"mediaId":"b.png"},{"revisedPrompt":"lost"}]}"#)))
        #expect(result.size == "1024x1536")
        #expect(result.images.map(\.mediaId) == ["md_1", "b.png", nil])
        #expect(result.images.map(\.chatId) == ["c1", nil, nil])
        #expect(ImageGenerationResult(json: json(#"{"size":"auto"}"#)) == nil)
        #expect(ImageGenerationArguments(json: json(#"{"prompt":"A lighthouse"}"#))?.prompt == "A lighthouse")
    }

    @Test("width and height are read when positive")
    func size() throws {
        let result = try #require(
            ImageGenerationResult(
                json: json(
                    #"{"images":[{"mediaId":"a.png","chatId":"c1","mimeType":"image/png","width":1024,"height":1536},{"mediaId":"b.png","width":0,"height":"x"}]}"#
                )))
        #expect(result.images[0].width == 1024)
        #expect(result.images[0].height == 1536)
        #expect(result.images[1].width == nil)
        #expect(result.images[1].height == nil)
    }
}

@Suite("Tool results: map_itinerary")
struct MapItineraryResultTests {
    @Test("the Kyoto fixture: two days of 9 and 3 stops, enrichment fields and the notice")
    func kyoto() throws {
        let map = try #require(MapItineraryDetails(json: json(F.kyoto)))
        #expect(map.title == "Kyoto in two days")
        #expect(map.days.map(\.places.count) == [9, 3])
        #expect(map.days.map(\.routeMode) == ["walking", "transit"])
        let first = map.days[0].places[0]
        #expect(first.name == "Fushimi Inari Taisha")
        #expect(first.lat == 34.9671)
        #expect(first.rating == 4.7)
        #expect(first.reviewCount == 61234)
        #expect(first.openNow == true)
        #expect(map.days[0].places[3].openNow == false)
        #expect(map.notice?.level == "warning")
        #expect(map.notice?.message.hasPrefix("The Places key has expired") == true)
    }

    @Test("a place without a readable position is kept with no coordinates; a place without a name is dropped")
    func lenient() throws {
        let map = try #require(
            MapItineraryDetails(
                json: json(
                    #"{"type":"mapItinerary","days":[{"label":"D1","places":[{"name":"A","lat":1,"lng":2},{"name":"B"},{"name":"C","lat":"x","lng":3},{"name":"D","lat":91,"lng":0},{"name":"E","lat":0,"lng":-181},{"name":"F","lat":"35.5","lng":"-120"},{"lat":1,"lng":1}]}]}"#
                )))
        let places = map.days[0].places
        #expect(places.map(\.name) == ["A", "B", "C", "D", "E", "F"])
        #expect(places.map { $0.lat != nil } == [true, false, false, false, false, true])
        #expect(places.allSatisfy { ($0.lat == nil) == ($0.lng == nil) })
        #expect(places[5].lat == 35.5)
        #expect(places[5].lng == -120)
        #expect(map.notice == nil)
        #expect(MapItineraryDetails(json: json(#"{"type":"mapItinerary"}"#)) == nil)
    }

    @Test("a day with no positions at all, a day without places, and an info notice with no level")
    func daysWithoutCoordinates() throws {
        let map = try #require(
            MapItineraryDetails(
                json: json(
                    #"{"type":"mapItinerary","days":[{"label":"Day 1","places":[{"name":"Somewhere"},{"name":"Elsewhere","note":"Ask at the desk."}]},{"label":"Rest"},{"places":[]}],"notice":{"message":"Live place data is unavailable."}}"#
                )))
        #expect(map.days.count == 2)
        #expect(map.days[0].places.map(\.name) == ["Somewhere", "Elsewhere"])
        #expect(map.days[0].places.allSatisfy { $0.lat == nil })
        #expect(map.days[0].places[1].note == "Ask at the desk.")
        #expect(map.days[1].label == "")
        #expect(map.days[1].places.isEmpty)
        #expect(map.notice?.level == "info")
        #expect(map.notice?.message == "Live place data is unavailable.")
    }

    @Test("the desktop's enriched place: hours, photos, reviews and contact fields")
    func enrichedPlace() throws {
        let map = try #require(MapItineraryDetails(json: json(F.enrichedPlace)))
        let place = try #require(map.days.first?.places.first)
        #expect(place.phone == "+81 75-561-1234")
        #expect(place.websiteUri == "https://www.kiyomizudera.or.jp/")
        #expect(place.googleMapsUri == "https://maps.google.com/?cid=1")
        #expect(place.openingHours.count == 2)
        #expect(place.photoNames == ["places/X/photos/A", "places/X/photos/B"])
        #expect(place.reviews.map(\.author) == ["Ann", nil])
        #expect(place.reviews[0].rating == 5)
        #expect(place.reviews[1].text == "Crowded but worth it.")
        #expect(map.notice?.level == "warning")
    }
}

@Suite("Tool results: memory")
struct MemoryChangeTests {
    @Test("update_memory's changes: create has no before, delete no after, the key follows the change")
    func changes() throws {
        let result = try #require(MemoryUpdateResult(json: json(#"{"changes":\#(F.memoryChanges)}"#)))
        #expect(result.changes.map(\.op) == [.update, .create, .delete])
        #expect(result.changes.map(\.key) == ["Classical Music", "Work setup", "Alex (old manager)"])
        #expect(result.changes[1].before == nil)
        #expect(result.changes[2].after == nil)
        #expect(result.changes[0].after?.details == ["Favourite: Mahler 2", "Learning Bach's Goldberg Variations"])
        #expect(result.changes[2].before?.section == "person")
    }

    @Test("a change with an unknown op is dropped; no changes key is not a result")
    func lenient() throws {
        let result = try #require(
            MemoryUpdateResult(json: json(#"{"changes":[{"op":"merge","id":"x"},{"op":"create","id":"y","after":{"key":"K"}}]}"#)))
        #expect(result.changes.map(\.id) == ["y"])
        #expect(result.changes[0].after == MemorySnapshot(section: "topic", key: "K", summary: "", details: []))
        #expect(MemoryUpdateResult(json: json(#"{"applied":0}"#)) == nil)
    }

    @Test("a change encodes back to the shape it came in, before/after null included (the undo route needs the keys)")
    func encodesForUndo() throws {
        let decoded = try JSONDecoder().decode([MemoryChange].self, from: Data(F.memoryChanges.utf8))
        let encoded = try JSONEncoder().encode(MemoryUndoBody(changes: decoded))
        let body = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let sent = try #require(body["changes"] as? NSArray)
        let original = try #require(try JSONSerialization.jsonObject(with: Data(F.memoryChanges.utf8)) as? NSArray)
        #expect(sent == original)
        let create = try #require(sent[1] as? [String: Any])
        #expect(create["before"] is NSNull)
    }

    @Test("an entry as it reads now becomes the snapshot a change is compared with")
    func snapshotOfEntry() {
        let entry = MemoryEntry(id: "m1", section: "topic", key: "K", summary: "s", details: ["d"], isActive: false)
        #expect(MemorySnapshot(entry: entry) == MemorySnapshot(section: "topic", key: "K", summary: "s", details: ["d"], isActive: false))
    }

    @Test("used memories decode through JSONDecoder, as the SSE event and the usage route send them")
    func usedMemories() throws {
        let used = try JSONDecoder().decode([UsedMemory].self, from: Data(F.usedMemories.utf8))
        #expect(used.map(\.id) == ["m2", "m1", "m9"])
        #expect(used[0] == UsedMemory(id: "m2", key: "Work setup", section: "profile"))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(UsedMemory.self, from: Data(#"{"key":"x"}"#.utf8))
        }
    }
}

@Suite("Tool results: search media and helpers")
struct SearchMediaTests {
    @Test("images and videos decode; an unknown kind or a missing url does not")
    func media() throws {
        let video = try #require(
            WebSearchMedia(
                json: json(
                    #"{"kind":"video","title":"T","url":"https://v.invalid","sourceUrl":"https://s.invalid","duration":"4:01","views":1200,"publisher":"YouTube"}"#
                )))
        #expect(video.kind == .video)
        #expect(video.views == 1200)
        #expect(video.publisher == "YouTube")
        #expect(WebSearchMedia(json: json(#"{"kind":"image","url":"https://i.invalid","width":640}"#))?.width == 640)
        #expect(WebSearchMedia(json: json(#"{"kind":"audio","url":"https://a.invalid"}"#)) == nil)
        #expect(WebSearchMedia(json: json(#"{"kind":"image"}"#)) == nil)
    }

    @Test("an object that arrived as JSON text is read like the object")
    func objectInText() {
        #expect(JSONValue.string(#"{"command":"pwd"}"#).objectValue == ["command": .string("pwd")])
        #expect(JSONValue.string("plain").objectValue == nil)
        #expect(TerminalResult(json: .string(#"{"command":"pwd","exitCode":0}"#))?.succeeded == true)
    }

    @Test("a value of the wrong type reads as absent, never as a crash")
    func wrongTypes() throws {
        let file = try #require(ReadFileResult(json: json(#"{"path":7,"content":"x","size":1e300}"#)))
        #expect(file.path == "")
        #expect(file.size == nil)
        #expect(EditFileResult(json: json(#"{"path":"/a","replacements":"many","linesBefore":1.5}"#))?.replacements == nil)
    }
}

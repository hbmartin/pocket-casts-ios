import SwiftUI

/// Beta-menu viewer for the MetricKit payload ring buffer: lists the stored
/// JSON payloads newest-first, shows their contents, and offers export.
struct MetricKitPayloadsView: View {
    @State private var files: [PayloadFile] = []
    @State private var selectedFile: PayloadFile?

    struct PayloadFile: Identifiable {
        let url: URL
        let sizeBytes: Int64

        var id: String { url.lastPathComponent }
        var name: String { url.lastPathComponent }
    }

    var body: some View {
        Group {
            if files.isEmpty {
                ContentUnavailableView(
                    "No MetricKit payloads yet",
                    systemImage: "waveform.path.ecg",
                    description: Text("iOS delivers metric payloads roughly once a day and diagnostics after crashes or hangs. Check back after the app has been used on device for a day.")
                )
            } else {
                List(files) { file in
                    Button {
                        selectedFile = file
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.callout.monospaced())
                                Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(item: file.url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("MetricKit Payloads")
        .onAppear(perform: reload)
        .sheet(item: $selectedFile) { file in
            NavigationStack {
                ScrollView {
                    Text(prettyJSON(at: file.url))
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
                .navigationTitle(file.name)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func reload() {
        let directory = MetricKitCollector.payloadDirectory
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        files = contents
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { url in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return PayloadFile(url: url, sizeBytes: Int64(size))
            }
    }

    private func prettyJSON(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "Unable to read payload." }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? "Unable to decode payload."
    }
}

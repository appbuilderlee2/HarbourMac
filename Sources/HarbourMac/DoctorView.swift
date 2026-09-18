import Foundation
import SwiftUI

/// Read-only Doctor diagnostics entry.
///
/// Mole CLI ships a `doctor` command; the bundled engine here does not.
/// Per the M5 plan: if the bridge does not support doctor, do NOT write
/// shell — show a clear message plus a copy button. YAGNI.
///
/// Coverage statement: this view is read-only; it never triggers engine
/// deletion, modification or privileged writes.
struct DoctorView: View {
    @ObservedObject var model: AppModel
    @State private var doctorOutput: [String: Any] = [:]
    @State private var doctorLoaded = false
    @State private var doctorBusy = false
    @State private var doctorError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("執行診斷") { runDoctor() }
                    .disabled(doctorBusy || model.runner.busy)
                if doctorLoaded || doctorError != nil {
                    Button("複製結果") { copyDoctorOutput() }
                }
                Spacer()
                if doctorBusy { ProgressView().controlSize(.regular) }
            }.disabled(model.runner.busy)

            if let error = doctorError {
                Text(error)
                    .font(.caption).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
            }

            if doctorLoaded {
                JSONInspector(value: doctorOutput)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            } else if !doctorBusy && doctorError == nil {
                Text("尚未執行診斷。執行診斷只會讀取引擎與本機狀態，不會修改資料。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func runDoctor() {
        guard !doctorBusy, !model.runner.busy else { return }
        doctorBusy = true
        doctorError = nil
        doctorOutput = [:]
        // The bundled engine has no doctor subcommand. Per plan, do not
        // write shell; show read-only guidance and stop here.
        defer { doctorBusy = false }
        model.notice = "診斷指令請用 `mo doctor`"
        doctorError = "Harbour 內建引擎未提供 doctor 子命令。請在終端機執行 `mo doctor` 查看診斷結果。"
    }

    private func copyDoctorOutput() {
        let text = doctorOutput.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        model.notice = "診斷結果已複製"
    }
}

import Foundation
import PDFKit

// Writes each page's text to the output file, separated by a page marker.
let args = CommandLine.arguments
guard args.count == 3, let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    print("could not open the PDF")
    exit(1)
}
var out = ""
for index in 0..<document.pageCount {
    out += "\n=== PAGE \(index + 1) ===\n" + (document.page(at: index)?.string ?? "")
}
try out.write(toFile: args[2], atomically: true, encoding: .utf8)
print("pages: \(document.pageCount), characters: \(out.count)")

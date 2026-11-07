// language: Swift, file: main.swift, target: a small CLI over GooseCore
import Foundation
import GooseCore

// A development helper: run a Goose file with the app's interpreter and print
// its output, so a test can be diffed against the reference compiler.
//
//   goosectl run file.goose
//   cat file.goose | goosectl

let arguments = Array(CommandLine.arguments.dropFirst())
let paths = arguments.first == "run" ? Array(arguments.dropFirst()) : arguments

let source: String
if let path = paths.first {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write(Data("goosectl: não consegui ler \(path)\n".utf8))
        exit(2)
    }
    source = text
} else {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    source = String(decoding: data, as: UTF8.self)
}

do {
    print(try GooseInterpreter().run(source), terminator: "")
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}

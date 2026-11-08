import SwiftUI
import UniformTypeIdentifiers

enum CodeLanguage: String, CaseIterable, Identifiable, Hashable {
    case goose
    case c
    case assembly

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .goose: return "goose"
        case .c: return "c"
        case .assembly: return "asm"
        }
    }

    var displayName: String {
        switch self {
        case .goose: return "Goose"
        case .c: return "C"
        case .assembly: return "Assembly NASM x86-64"
        }
    }

    var shortName: String {
        switch self {
        case .goose: return "Goose"
        case .c: return "C"
        case .assembly: return "NASM64"
        }
    }

    var pistonLanguage: String? {
        switch self {
        case .goose: return nil
        case .c: return "c"
        case .assembly: return "nasm64"
        }
    }

    static func detect(path: String) -> CodeLanguage? {
        let ext = (path as NSString).pathExtension.lowercased()
        return allCases.first { $0.fileExtension == ext }
    }
}

struct WorkspaceFile: Identifiable, Hashable {
    let path: String

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var language: CodeLanguage? { CodeLanguage.detect(path: path) }
}

struct WorkspaceNode: Identifiable {
    let name: String
    let path: String
    let isDirectory: Bool
    let children: [WorkspaceNode]?

    var id: String { path }
}

final class LocalWorkspaceStore: ObservableObject {
    @Published private(set) var nodes: [WorkspaceNode] = []
    @Published private(set) var errorMessage: String?

    let rootURL: URL
    private let fileManager = FileManager.default

    init(initialSource: String) {
        let manager = FileManager.default
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        rootURL = documents.appendingPathComponent("Workspace", isDirectory: true)

        do {
            try manager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let mainFile = rootURL.appendingPathComponent("main.goose")
            if !manager.fileExists(atPath: mainFile.path) {
                try Data(initialSource.utf8).write(to: mainFile, options: .atomic)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        refresh()
    }

    func refresh() {
        do {
            nodes = try makeNodes(in: rootURL)
            errorMessage = nil
        } catch {
            nodes = []
            errorMessage = error.localizedDescription
        }
    }

    func readFile(at path: String) throws -> String {
        try String(contentsOf: fileURL(for: path), encoding: .utf8)
    }

    func save(_ source: String, at path: String) throws {
        try Data(source.utf8).write(to: fileURL(for: path), options: .atomic)
    }

    func createFile(language: CodeLanguage = .goose) throws -> WorkspaceFile {
        var name = "novo.\(language.fileExtension)"
        var suffix = 2
        while fileManager.fileExists(atPath: rootURL.appendingPathComponent(name).path) {
            name = "novo-\(suffix).\(language.fileExtension)"
            suffix += 1
        }

        let path = name
        let source: String
        switch language {
        case .goose:
            source = """
            fn main() {
                print("Olá, Goose!");
            }
            """
        case .c:
            source = """
            #include <stdio.h>

            int main(void) {
                puts("Olá, C!");
                return 0;
            }
            """
        case .assembly:
            source = """
            global _start

            section .text
            _start:
                mov rax, 1
                mov rdi, 1
                mov rsi, message
                mov rdx, message_len
                syscall
                mov rax, 60
                xor rdi, rdi
                syscall

            section .data
            message db "Olá, Assembly!", 10
            message_len equ $ - message
            """
        }
        try Data(source.utf8).write(to: fileURL(for: path), options: .atomic)
        refresh()
        return WorkspaceFile(path: path)
    }

    func exampleFile(named name: String, source: String) throws -> WorkspaceFile {
        let folder = rootURL.appendingPathComponent("examples", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let slug = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
        let path = "examples/\(slug.isEmpty ? "exemplo" : slug).goose"
        let url = try fileURL(for: path)
        if !fileManager.fileExists(atPath: url.path) {
            try Data(source.utf8).write(to: url, options: .atomic)
        }
        refresh()
        return WorkspaceFile(path: path)
    }

    func importFile(from sourceURL: URL) throws {
        guard let language = CodeLanguage.detect(path: sourceURL.path) else {
            throw WorkspaceError.unsupportedFile
        }

        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: sourceURL)
        guard String(data: data, encoding: .utf8) != nil else {
            throw WorkspaceError.notUTF8
        }

        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        let stem = sourceName.isEmpty ? "importado" : sourceName
        var name = "\(stem).\(language.fileExtension)"
        var suffix = 2
        while fileManager.fileExists(atPath: rootURL.appendingPathComponent(name).path) {
            name = "\(stem)-\(suffix).\(language.fileExtension)"
            suffix += 1
        }

        try data.write(to: fileURL(for: name), options: .atomic)
        refresh()
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func clearError() {
        errorMessage = nil
    }

    private func fileURL(for path: String) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            throw WorkspaceError.invalidPath
        }

        let url = rootURL.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else {
            throw WorkspaceError.invalidPath
        }
        return url
    }

    private func makeNodes(in directory: URL) throws -> [WorkspaceNode] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        var result: [WorkspaceNode] = []
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { continue }
            let path = String(url.path.dropFirst(rootURL.path.count + 1))

            if values.isDirectory == true {
                result.append(WorkspaceNode(
                    name: url.lastPathComponent,
                    path: path,
                    isDirectory: true,
                    children: try makeNodes(in: url)
                ))
            } else if CodeLanguage.detect(path: url.path) != nil {
                result.append(WorkspaceNode(
                    name: url.lastPathComponent,
                    path: path,
                    isDirectory: false,
                    children: nil
                ))
            }
        }

        return result.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

private enum WorkspaceError: LocalizedError {
    case invalidPath
    case notUTF8
    case unsupportedFile

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "O caminho do arquivo não pertence ao workspace."
        case .notUTF8:
            return "O arquivo precisa ser texto UTF-8."
        case .unsupportedFile:
            return "O Explorer aceita arquivos .goose, .c e .asm."
        }
    }
}

struct WorkspaceExplorerView: View {
    @ObservedObject var workspace: LocalWorkspaceStore
    let activePath: String?
    let onOpen: (WorkspaceFile, String) -> Void
    let onNewFile: (CodeLanguage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var showingImporter = false

    private var visibleNodes: [WorkspaceNode] {
        guard !search.isEmpty else { return workspace.nodes }
        return workspace.nodes.compactMap { filtered($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = workspace.errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(VSCode.warning)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(VSCode.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            workspace.clearError()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                        }
                        .accessibilityLabel("Fechar aviso")
                    }
                    .listRowBackground(VSCode.activityBar)
                }

                Section {
                    if visibleNodes.isEmpty {
                        Text(search.isEmpty ? "Nenhum arquivo compatível neste workspace." : "Nenhum arquivo encontrado.")
                            .font(.footnote)
                            .foregroundStyle(VSCode.faintText)
                    } else {
                        OutlineGroup(visibleNodes, children: \.children) { node in
                            if node.isDirectory {
                                Label(node.name, systemImage: "folder.fill")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(VSCode.text)
                                    .listRowBackground(VSCode.sidebar)
                            } else {
                                fileRow(node)
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("WORKSPACE")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.5)
                        Spacer()
                        Text("\(workspaceFileCount)")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundStyle(VSCode.dimText)
                }

                Section {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Importar código-fonte", systemImage: "square.and.arrow.down")
                            .font(.subheadline)
                            .foregroundStyle(VSCode.text)
                    }
                    .listRowBackground(VSCode.sidebar)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(VSCode.sidebar)
            .searchable(text: $search, prompt: "Filtrar arquivos")
            .navigationTitle("Explorer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("Novo arquivo") {
                            ForEach(CodeLanguage.allCases) { language in
                                Button {
                                    onNewFile(language)
                                } label: {
                                    Text(language.displayName)
                                }
                            }
                        }
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Importar código-fonte", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            workspace.refresh()
                        } label: {
                            Label("Atualizar", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Ações do workspace")
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.sourceCode, .plainText],
                allowsMultipleSelection: true,
                onCompletion: importFiles
            )
            .task { workspace.refresh() }
        }
        .preferredColorScheme(.dark)
    }

    private var workspaceFileCount: Int {
        func count(_ nodes: [WorkspaceNode]) -> Int {
            nodes.reduce(0) { total, node in
                total + (node.isDirectory ? count(node.children ?? []) : 1)
            }
        }
        return count(workspace.nodes)
    }

    @ViewBuilder
    private func fileRow(_ node: WorkspaceNode) -> some View {
        Button {
            do {
                onOpen(WorkspaceFile(path: node.path), try workspace.readFile(at: node.path))
            } catch {
                workspace.report(error)
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(activePath == node.path ? VSCode.keyword : VSCode.dimText)
                Text(node.name)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(activePath == node.path ? .white : VSCode.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if activePath == node.path {
                    Circle()
                        .fill(VSCode.statusBar)
                        .frame(width: 5, height: 5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(activePath == node.path ? VSCode.highlight.opacity(0.55) : VSCode.sidebar)
    }

    private func filtered(_ node: WorkspaceNode) -> WorkspaceNode? {
        if node.name.localizedCaseInsensitiveContains(search) { return node }
        guard node.isDirectory else { return nil }
        let children = (node.children ?? []).compactMap { filtered($0) }
        guard !children.isEmpty else { return nil }
        return WorkspaceNode(
            name: node.name,
            path: node.path,
            isDirectory: true,
            children: children
        )
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            for url in try result.get() {
                try workspace.importFile(from: url)
            }
        } catch {
            workspace.report(error)
        }
    }
}
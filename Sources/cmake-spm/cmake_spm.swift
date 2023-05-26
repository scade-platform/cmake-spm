import Foundation
import ArgumentParser
import TSCBasic

// SwiftPM
import Basics
import PackageModel
import PackageGraph
import Workspace

extension String: Error { }

@main
struct Generate: ParsableCommand {
  @Option(name: .shortAndLong, help: "Output path", transform: get_abs_path)
  var output: AbsolutePath = localFileSystem.currentWorkingDirectory!

  @Option(name: .customLong("workspace"), help: "Workspace path", transform: get_abs_path)
  var workspacePath: AbsolutePath = localFileSystem.currentWorkingDirectory!

  @Option(name: .customLong("scope"), help: "Scope name for workspace")
  var scopeName: String?

  @Argument(help: "Swift packages URLs")
  var urls: [String]

  func run() throws {
    let workspace = try Workspace(forRootPackage: self.workspacePath)

    let observability = ObservabilitySystem({ scope, diag in
      switch diag.severity {
      case .error:
        print("ERROR: when parsing SPM manifest: \(diag.message)")
      case .warning:
        print("WARNING: when parsing SPM manifest: \(diag.message)")
      default:
        ()
      }
    })

    let deps: [PackageDependency] = try urls.compactMap(get_dependency)
    let input = PackageGraphRootInput(packages: [], dependencies: deps)

    try workspace.resolve(root: input, observabilityScope: observability.topScope)

    let graph = try workspace.loadPackageGraph(rootInput: input, observabilityScope: observability.topScope)

    let cmakeGen = CMakeGen(graph: graph, cmakeListsDir: self.output, scopeName: self.scopeName)

    try cmakeGen.generate()
  }
}

func get_abs_path(_ path: String) throws -> AbsolutePath {
  let path = AbsolutePath(path, relativeTo: localFileSystem.currentWorkingDirectory!)
  guard localFileSystem.exists(path, followSymlink: true) else {
    throw "Path does not exists"
  }
  return path
}

func get_dependency(_ url: String) throws -> PackageDependency? {
  let regex = #/(?<url>[^\#]+)(\#(branch=(?<branch>.+)|commit=(?<commit>.+)|version=(?<version>.+)))?/#

  guard let match = url.wholeMatch(of: regex),
        let url = URL(string: String(match.output.url)) else {
    return nil
  }

  if match.output.branch == nil && match.output.version == nil && match.output.commit == nil {
    // local file
    if url.scheme != nil && url.scheme != "file" {
      throw "Invalid remote URL without branch/version/revision specification: \(url)"
    }

    return PackageDependency.fileSystem(
      identity: PackageIdentity(url: url),
      nameForTargetDependencyResolutionOnly: nil,
      path: AbsolutePath(url.path),
      productFilter: .everything
    )
  } else {
    let req: PackageDependency.SourceControl.Requirement
    if let value = match.output.branch {
      req = PackageDependency.SourceControl.Requirement.branch(String(value))
    } else if let value = match.output.version {
      req = PackageDependency.SourceControl.Requirement.exact(Version(stringLiteral: String(value)))
    } else if let value = match.output.commit {
      req = PackageDependency.SourceControl.Requirement.revision(String(value))
    } else {
      throw "Unknown dependency requirement"
    }

    return PackageDependency.sourceControl(
      identity: PackageIdentity(url: url),
      nameForTargetDependencyResolutionOnly: nil,
      location: .remote(url),
      requirement: req,
      productFilter: .everything)
    }
}

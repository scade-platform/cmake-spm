//
//  Generator.swift
//  
//
//  Created by Grigory Markin on 01.03.23.
//

import TSCBasic
import PackageGraph
import PackageModel

protocol GenContext {
  var rootPath: AbsolutePath { get }
}

class CMakeGen: GenContext {
  let graph: PackageGraph
  let rootPath: AbsolutePath

  init(graph: PackageGraph, cmakeListsDir: AbsolutePath) {
    self.graph = graph
    self.rootPath = cmakeListsDir
  }

  func generate() throws {
    var out = TemplatePrinter()

    for pkg in graph.packages {
      pkg.generate(self, out: &out)
    }

    let outputFile = rootPath.appending(RelativePath("CMakeLists.txt"))
    try localFileSystem.writeFileContents(outputFile, string: out.content)
  }
}


// -------------Package -------------

fileprivate extension ResolvedPackage {
  func generate(_ ctx: GenContext, out: inout TemplatePrinter) {
    targets.forEach{$0.generate(ctx, pkg: self.identity, out: &out)}
    products.forEach{$0.generate(ctx, pkg: self.identity, out: &out)}
}
}


// -------------Target -------------

fileprivate extension Target {
  func gen_name(_ pkg: PackageIdentity) -> String {
    return "\(pkg.description)__\(name)"
  }
}

fileprivate extension Target.ProductReference {
  func gen_name(_ pkg: PackageIdentity) -> String {
    return self.name
  }
}

fileprivate func generateModuleName(targetName: String,
                                    moduleName: String,
                                    out: inout TemplatePrinter) {
  let fixedModuleName = moduleName.replacingOccurrences(of: "-", with: "_")

  out <| "set_target_properties(\(targetName) PROPERTIES"
  out <| { out in
    out <| "Swift_MODULE_NAME \(fixedModuleName)"
  }
  out <| ")"
}

fileprivate extension ResolvedTarget {
  func generate(_ ctx: GenContext, pkg: PackageIdentity, out: inout TemplatePrinter) {
    let name = self.underlyingTarget.gen_name(pkg)

    out <| "add_library(\(name) STATIC"
    out <| { out in
      underlyingTarget.sources.paths.forEach {
        let srcPath = $0.relative(to: ctx.rootPath).pathString
          .replacingOccurrences(of: " ", with: "\\ ")
          .replacingOccurrences(of: ">", with: "_")
        out <| "${CMAKE_CURRENT_LIST_DIR}/\(srcPath)"
      }
    }
    out <| ")"

    generateModuleName(targetName: name, moduleName: self.name, out: &out)

    if !underlyingTarget.dependencies.isEmpty {
      out <| "target_link_libraries(\(name) PRIVATE"
      out <| { out in
        underlyingTarget.dependencies.forEach{
          switch $0 {
          case .target(let t, _):
            out <| "\(t.gen_name(pkg))"
          case .product(let p, _):
            out <| p.gen_name(pkg)
          }
        }
      }
      out <| ")"
    }
  }
}


// ------------- Product -------------

fileprivate extension Product {
  func gen_name(_ pkg: PackageIdentity) -> String {
    return name
  }
}


fileprivate extension ResolvedProduct {
  func generate(_ ctx: GenContext, pkg: PackageIdentity, out: inout TemplatePrinter) {
    let name = self.underlyingProduct.gen_name(pkg)

    switch(self.type) {
    case .library(.dynamic):
      out <| "add_library(\(name) SHARED empty.swift"
      out <| {
        generate_targets(&$0, pkg: pkg, use_objs: true)
      }
      out <| ")"

      out <| ("target_include_directories(\(name) PUBLIC ${CMAKE_CURRENT_BINARY_DIR})")

      generateModuleName(targetName: name, moduleName: name + "_product", out: &out)

    case .library(_):
      out <| "add_library(\(name) INTERFACE)"
      out <| "target_link_libraries(\(name) INTERFACE"
      out <| {
        generate_targets(&$0, pkg: pkg)
      }
      out <| ")"

      out <| ("target_include_directories(\(name) INTERFACE ${CMAKE_CURRENT_BINARY_DIR})")
    case .executable:
      out <| ("add_executable(\(name)")
      out <| {
        generate_targets(&$0, pkg: pkg)
      }
      out <| ")"

      out <| ("target_include_directories(\(name) PUBLIC ${CMAKE_CURRENT_BINARY_DIR})")
    default:
      break
    }
  }

  private func generate_targets(_ out: inout TemplatePrinter, pkg: PackageIdentity, use_objs: Bool = false) {
    self.underlyingProduct.targets.forEach{
      let name = $0.gen_name(pkg)
      out <| (use_objs ? "$<TARGET_OBJECTS:\(name)>" : name)
    }
  }
}

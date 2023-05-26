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
  func nameWithScope(_ name: String) -> String;
  func getScopeName() -> String?;
}

class CMakeGen: GenContext {
  let graph: PackageGraph
  let rootPath: AbsolutePath
  let scopeName: String?

  init(graph: PackageGraph, cmakeListsDir: AbsolutePath, scopeName: String?) {
    self.graph = graph
    self.rootPath = cmakeListsDir
    self.scopeName = scopeName
  }

  func generate() throws {
    var out = TemplatePrinter()

    for pkg in graph.packages {
      pkg.generate(self, out: &out)
    }

    let outputFile = rootPath.appending(RelativePath("CMakeLists.txt"))
    try localFileSystem.writeFileContents(outputFile, string: out.content)
  }

  // Returns name with scope for specified name
  public func nameWithScope(_ name: String) -> String {
    if let scName = scopeName {
      return scName + "-" + name
    } else {
      return name
    }
  }

  // Returns scope name
  public func getScopeName() -> String? {
    return self.scopeName
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

fileprivate func generateLibraryAlias(ctx: GenContext,
                                      targetName: String,
                                      out: inout TemplatePrinter) {
  guard let scopeName = ctx.getScopeName() else { return }

  let nameWithScope = ctx.nameWithScope(targetName) 
  out <| "add_library(\(scopeName)::\(targetName) ALIAS \(nameWithScope))"
}

fileprivate extension ResolvedTarget {
  func generate(_ ctx: GenContext, pkg: PackageIdentity, out: inout TemplatePrinter) {
    let nameWithScope = ctx.nameWithScope(self.underlyingTarget.gen_name(pkg))

    out <| "add_library(\(nameWithScope) STATIC"

    if underlyingTarget.sources.paths.isEmpty {
      // add empty swift source for targets without source files. This
      // is required for correct detection of language in cmake
      out <| "empty.swift"
    }

    out <| { out in
      underlyingTarget.sources.paths.forEach {
        let srcPath = $0.relative(to: ctx.rootPath).pathString
          .replacingOccurrences(of: " ", with: "\\ ")
          .replacingOccurrences(of: ">", with: "_")
        out <| "${CMAKE_CURRENT_LIST_DIR}/\(srcPath)"
      }
    }
    out <| ")"

    out <| ("target_include_directories(\(nameWithScope) PUBLIC ${CMAKE_CURRENT_BINARY_DIR})")

    generateModuleName(targetName: nameWithScope, moduleName: self.name, out: &out)

    if !underlyingTarget.dependencies.isEmpty {
      out <| "target_link_libraries(\(nameWithScope) PRIVATE"
      out <| { out in
        underlyingTarget.dependencies.forEach{
          switch $0 {
          case .target(let t, _):
            out <| "\(ctx.nameWithScope(t.gen_name(pkg)))"
          case .product(let p, _):
            out <| ctx.nameWithScope(p.gen_name(pkg))
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
    let targetName = self.underlyingProduct.gen_name(pkg)
    let nameWithScope = ctx.nameWithScope(targetName)

    switch(self.type) {
    case .library(.dynamic):
      out <| "add_library(\(nameWithScope) SHARED empty.swift"
      out <| {
        generate_targets(ctx: ctx, &$0, pkg: pkg, use_objs: true)
      }
      out <| ")"

      out <| ("target_include_directories(\(nameWithScope) PUBLIC ${CMAKE_CURRENT_BINARY_DIR})")

      generateModuleName(targetName: nameWithScope, moduleName: nameWithScope + "_product", out: &out)
      generateLibraryAlias(ctx: ctx, targetName: targetName, out: &out)

    case .library(_):
      out <| "add_library(\(nameWithScope) INTERFACE)"
      out <| "target_link_libraries(\(nameWithScope) INTERFACE"
      out <| {
        generate_targets(ctx: ctx, &$0, pkg: pkg)
      }
      out <| ")"

      out <| ("target_include_directories(\(nameWithScope) INTERFACE ${CMAKE_CURRENT_BINARY_DIR})")
      generateLibraryAlias(ctx: ctx, targetName: targetName, out: &out)

    case .executable:
      out <| ("add_executable(\(nameWithScope) empty.swift")
      out <| {
        generate_targets(ctx: ctx, &$0, pkg: pkg, use_objs: true)
      }
      out <| ")"

      out <| ("target_include_directories(\(nameWithScope) PUBLIC ${CMAKE_CURRENT_BINARY_DIR})")
    default:
      break
    }
  }

  private func generate_targets(ctx: GenContext,
                                _ out: inout TemplatePrinter,
                                pkg: PackageIdentity,
                                use_objs: Bool = false) {
    self.underlyingProduct.targets.forEach{
      let nameWithScope = ctx.nameWithScope($0.gen_name(pkg))
      out <| (use_objs ? "$<TARGET_OBJECTS:\(nameWithScope)>" : nameWithScope)
    }
  }
}

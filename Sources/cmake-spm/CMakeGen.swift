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

fileprivate func generateSystemLibraryTarget(ctx: GenContext,
                                             pkg: PackageIdentity,
                                             target: ResolvedTarget,
                                             out: inout TemplatePrinter) {
  // source directory for a system library target contains modulemap file

  let targetName = target.underlyingTarget.gen_name(pkg)
  let nameWithScope = ctx.nameWithScope(target.underlyingTarget.gen_name(pkg))
  
  out <| "add_library(\(nameWithScope) INTERFACE)"
  out <| "target_include_directories(\(nameWithScope) INTERFACE \(target.underlyingTarget.path))"

  generateLibraryAlias(ctx: ctx, targetName: targetName, out: &out)
}

fileprivate extension ResolvedTarget {
  func generate(_ ctx: GenContext, pkg: PackageIdentity, out: inout TemplatePrinter) {
    let nameWithScope = ctx.nameWithScope(self.underlyingTarget.gen_name(pkg))

    // special case for system libraries
    if self.type == .systemModule {
      generateSystemLibraryTarget(ctx: ctx, pkg: pkg, target: self, out: &out)
      return
    }

    if self.type == .executable {
      out <| "add_executable(\(nameWithScope)"
    } else {
      out <| "add_library(\(nameWithScope) STATIC"
    }

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

    // define SWIFT_PACKAGE macro for building all targets
    if underlyingTarget is ClangTarget {
      out <| "target_compile_definitions(\(nameWithScope) PRIVATE SWIFT_PACKAGE=1)"
    } else {
      out <| "target_compile_definitions(\(nameWithScope) PRIVATE SWIFT_PACKAGE)"
    }

    if let clangTarget = underlyingTarget as? ClangTarget {
      out <| "target_include_directories(\(nameWithScope) PUBLIC \(clangTarget.includeDir))"

      if clangTarget.isCXX, let cxxStandard = clangTarget.cxxLanguageStandard {
        let cmakeCxxStandard = cxxStandard.dropFirst(3)
        out <| "set_target_properties(\(nameWithScope) PROPERTIES CXX_STANDARD \(cmakeCxxStandard))"
      }
    } else {
      // For swift targets which depend on C/C++ targets, we have to add include directories
      // from C/C++ targets into C compile flags
      let includeDirs = getClangIncludeDirectories(target: self)
      if !includeDirs.isEmpty {
        out <| "target_compile_options(\(nameWithScope) PRIVATE"
        out <| { out in
          for includeDir in includeDirs {
            out <| "\"SHELL:-Xcc -I -Xcc \(includeDir.pathString)\""
          }
        }
        out <| ")"
      }
    }

    // adding path to system frameworks
    out <| "target_compile_options(\(nameWithScope) PRIVATE -F${CMAKE_OSX_SYSROOT}/../../Library/Frameworks)"
    out <| "target_include_directories(\(nameWithScope) PRIVATE ${CMAKE_OSX_SYSROOT}/../../usr/lib)"

    // generating flags
    for (declaration, assignments) in underlyingTarget.buildSettings.assignments {
      if (declaration == .SWIFT_ACTIVE_COMPILATION_CONDITIONS) {
        for assignment in assignments {
          // TODO: implement conditions
          out <| "target_compile_definitions(\(nameWithScope) PRIVATE"
          out <| { out in
            for value in assignment.values {
              out <| value
            }
          }
          out <| ")"
        }
      } else if declaration == .LINK_LIBRARIES {
        for assignment in assignments {
          // TODO: implement conditions
          out <| "target_link_libraries(\(nameWithScope) PUBLIC"
          out <| { out in
            for value in assignment.values {
              out <| value
            }
          }
          out <| ")"
        }
      } else if declaration == .OTHER_SWIFT_FLAGS {
        for assignment in assignments {
          // TODO: implement conditions
          out <| "target_compile_options(\(nameWithScope) PRIVATE"
          out <| { out in
            for value in assignment.values {
              out <| value
            }
          }
          out <| ")"
        }
      }
    }

    if !underlyingTarget.dependencies.isEmpty {
      out <| "target_link_libraries(\(nameWithScope) PUBLIC "
      out <| { out in
        underlyingTarget.dependencies.forEach{
          switch $0 {
          case .target(let t, _):
            if (t.type == .executable) {
              out <| "$<TARGET_OBJECTS:\(ctx.nameWithScope(t.gen_name(pkg)))>"
            } else {
              out <| "\(ctx.nameWithScope(t.gen_name(pkg)))"
            }
          case .product(let p, _):
            out <| ctx.nameWithScope(p.gen_name(pkg))
          }
        }
      }
      out <| ")"
    }

    
  }

  // Recursively iterates all target dependnecies and returns array of include directories
  // for C and C++ targets
  func getClangIncludeDirectories(target: ResolvedTarget) -> [AbsolutePath] {
    var res: [AbsolutePath] = []
    if let clangTarget = target.underlyingTarget as? ClangTarget {
      res.append(clangTarget.includeDir)
    }

    for dependency in target.dependencies {
      switch dependency {
      case .target(let depTarget, _):
        res += getClangIncludeDirectories(target: depTarget)
      case .product(let depProduct, _):
        for depProductTarget in depProduct.targets {
          res += getClangIncludeDirectories(target: depProductTarget)
        }
      }
    }

    return Set(res).sorted()
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
    self.targets.forEach { depTarget in
      let nameWithScope = ctx.nameWithScope(depTarget.underlyingTarget.gen_name(pkg))
      if (use_objs || depTarget.type == .executable) {
        out <| "$<TARGET_OBJECTS:\(nameWithScope)>"
      } else {
        out <| nameWithScope
      }
    }
  }
}

//
//  TemplatePrinter.swift
//  
//
//  Created by Grigory Markin on 10.03.23.
//

import Foundation


struct TemplatePrinter {
  private var indent: Int = 0
  private let indentLength: Int = 2

  private(set) var content: String = ""

  mutating func inc() {
    indent += 1
  }

  mutating func dec() {
    if indent > 0 {
      indent -= 1
    }
  }

  mutating func put(_ str: String) {
    print("\(String(repeating: " ", count: indentLength*indent))\(str)", to: &content)
  }
}

infix operator <|
func <| (_ printer: inout TemplatePrinter, _ str: String) {
  printer.put(str)
}

func <| (_ printer: inout TemplatePrinter, _ generator: (inout TemplatePrinter) -> ()) {
  printer.inc()
  generator(&printer)
  printer.dec()
}

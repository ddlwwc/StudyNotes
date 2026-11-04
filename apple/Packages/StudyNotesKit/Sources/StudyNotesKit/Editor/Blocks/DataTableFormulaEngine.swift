import Foundation

public enum FormulaValue: Equatable, Sendable {
    case number(Double)
    case string(String)
    case boolean(Bool)
    case empty

    init(json: JSONValue?) {
        switch json {
        case let .number(value):
            self = .number(value)
        case let .string(value):
            self = .string(value)
        case let .bool(value):
            self = .boolean(value)
        case .null, nil:
            self = .empty
        case let .array(value):
            self = .string(
                value.compactMap(\.stringValue).joined(separator: ", ")
            )
        case let .object(value):
            self = .string(
                value.keys.sorted().joined(separator: ", ")
            )
        }
    }

    var number: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    var string: String {
        switch self {
        case let .number(value):
            value.formatted(.number.grouping(.never))
        case let .string(value):
            value
        case let .boolean(value):
            value ? "true" : "false"
        case .empty:
            ""
        }
    }

    var boolean: Bool {
        switch self {
        case let .boolean(value):
            value
        case let .number(value):
            value != 0
        case let .string(value):
            !value.isEmpty
        case .empty:
            false
        }
    }
}

public struct FormulaDiagnostic: Equatable, Sendable, LocalizedError {
    public let fieldID: String
    public let recordID: String?
    public let offset: Int
    public let message: String

    public init(
        fieldID: String,
        recordID: String? = nil,
        offset: Int,
        message: String
    ) {
        self.fieldID = fieldID
        self.recordID = recordID
        self.offset = offset
        self.message = message
    }

    public var errorDescription: String? {
        let record = recordID.map { "，记录 \($0)" } ?? ""
        return "字段 \(fieldID)\(record)，位置 \(offset)：\(message)"
    }
}

public struct DataTableFormulaEngine: Sendable {
    public init() {}

    public func evaluate(
        fieldID: String,
        document: DataTableDocument,
        recordID: String
    ) throws -> FormulaValue {
        try validateDependencies(in: document)
        return try evaluateGraph(
            fieldID: fieldID,
            document: document,
            recordID: recordID,
            cache: [:],
            stack: []
        )
    }

    public func filteredRecords(
        viewID: String,
        document: DataTableDocument
    ) throws -> [DataTableRecord] {
        guard let view = document.views.first(where: { $0.id == viewID }) else {
            return document.records
        }
        var records = document.records.filter { record in
            view.filters.allSatisfy { filter in
                matches(filter, record: record, document: document)
            }
        }
        for sort in view.sorts.reversed() {
            records.sort { left, right in
                let lhs = value(
                    for: sort.fieldID,
                    record: left,
                    document: document
                )
                let rhs = value(
                    for: sort.fieldID,
                    record: right,
                    document: document
                )
                switch order(lhs, rhs) {
                case .orderedAscending:
                    return sort.ascending
                case .orderedDescending:
                    return !sort.ascending
                case .orderedSame:
                    return false
                }
            }
        }
        return records
    }

    public func validateDependencies(
        in document: DataTableDocument
    ) throws {
        let byID = document.schema.fieldByID
        let byName = document.schema.fieldByName
        var visiting = Set<String>()
        var visited = Set<String>()

        func visit(_ fieldID: String, offset: Int) throws {
            if visited.contains(fieldID) {
                return
            }
            guard !visiting.contains(fieldID) else {
                throw FormulaDiagnostic(
                    fieldID: fieldID,
                    offset: offset,
                    message: "公式存在循环依赖。"
                )
            }
            guard let field = byID[fieldID] else {
                throw FormulaDiagnostic(
                    fieldID: fieldID,
                    offset: offset,
                    message: "字段不存在。"
                )
            }
            visiting.insert(fieldID)
            if let formula = field.formula {
                for (dependency, dependencyOffset) in
                    referencedFieldIDs(in: formula) {
                    guard let dependencyField = byName[dependency] else {
                        throw FormulaDiagnostic(
                            fieldID: fieldID,
                            offset: dependencyOffset,
                            message: "引用了不存在的字段 \(dependency)。"
                        )
                    }
                    try visit(
                        dependencyField.id,
                        offset: dependencyOffset
                    )
                }
            }
            visiting.remove(fieldID)
            visited.insert(fieldID)
        }

        for field in document.schema.fields {
            try visit(field.id, offset: 0)
        }
    }

    private func evaluateGraph(
        fieldID: String,
        document: DataTableDocument,
        recordID: String,
        cache: [String: FormulaValue],
        stack: Set<String>
    ) throws -> FormulaValue {
        if let cached = cache[fieldID] {
            return cached
        }
        guard !stack.contains(fieldID) else {
            throw FormulaDiagnostic(
                fieldID: fieldID,
                recordID: recordID,
                offset: 0,
                message: "公式存在循环依赖。"
            )
        }
        guard let field = document.schema.fieldByID[fieldID],
              let record = document.records.first(where: { $0.id == recordID })
        else {
            throw FormulaDiagnostic(
                fieldID: fieldID,
                recordID: recordID,
                offset: 0,
                message: "字段或记录不存在。"
            )
        }
        guard let formula = field.formula else {
            return FormulaValue(json: record.values[field.id])
        }
        var resolved: [String: FormulaValue] = [:]
        for (dependency, _) in referencedFieldIDs(in: formula) {
            guard let dependencyField = document.schema.fieldByName[dependency]
            else {
                continue
            }
            resolved[dependency] = try evaluateGraph(
                fieldID: dependencyField.id,
                document: document,
                recordID: recordID,
                cache: cache,
                stack: stack.union([fieldID])
            )
        }
        var parser = try FormulaParser(expression: formula)
        return try parser.parse(
            fieldID: field.id,
            recordID: recordID,
            recordValues: record.values,
            fieldsByName: document.schema.fieldByName,
            resolvedFormulaValues: resolved
        )
    }

    private func referencedFieldIDs(
        in expression: String
    ) -> [(String, Int)] {
        let pattern = #"\{([^{}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return regex.matches(
            in: expression,
            range: NSRange(expression.startIndex..., in: expression)
        ).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: expression) else {
                return nil
            }
            return (String(expression[nameRange]), match.range.location)
        }
    }

    private func matches(
        _ filter: DataTableViewFilter,
        record: DataTableRecord,
        document: DataTableDocument
    ) -> Bool {
        let lhs = value(for: filter.fieldID, record: record, document: document)
        let rhs = FormulaValue(json: filter.value)
        let ordering = order(lhs, rhs)
        switch filter.operator {
        case .equals:
            return ordering == .orderedSame
        case .notEquals:
            return ordering != .orderedSame
        case .contains:
            return lhs.string.localizedCaseInsensitiveContains(rhs.string)
        case .greaterThan:
            return ordering == .orderedDescending
        case .greaterThanOrEqual:
            return ordering != .orderedAscending
        case .lessThan:
            return ordering == .orderedAscending
        case .lessThanOrEqual:
            return ordering != .orderedDescending
        case .isEmpty:
            return lhs == .empty || lhs.string.isEmpty
        case .isNotEmpty:
            return lhs != .empty && !lhs.string.isEmpty
        }
    }

    private func value(
        for fieldID: String,
        record: DataTableRecord,
        document: DataTableDocument
    ) -> FormulaValue {
        guard let field = document.schema.fieldByID[fieldID] else {
            return .empty
        }
        if field.type == .formula,
           let formulaValue = try? evaluateGraph(
               fieldID: field.id,
               document: document,
               recordID: record.id,
               cache: [:],
               stack: []
           ) {
            return formulaValue
        }
        return FormulaValue(json: record.values[fieldID])
    }

    private func order(
        _ lhs: FormulaValue,
        _ rhs: FormulaValue
    ) -> ComparisonResult {
        if let left = lhs.number, let right = rhs.number {
            if left < right {
                return .orderedAscending
            }
            if left > right {
                return .orderedDescending
            }
            return .orderedSame
        }
        return lhs.string.localizedStandardCompare(rhs.string)
    }
}

private enum FormulaToken: Equatable {
    case number(Double)
    case string(String)
    case field(String)
    case identifier(String)
    case plus
    case minus
    case multiply
    case divide
    case equal
    case notEqual
    case greater
    case greaterEqual
    case less
    case lessEqual
    case leftParen
    case rightParen
    case comma
    case end
}

private struct FormulaParser {
    private let expression: String
    private let tokens: [FormulaToken]
    private let offsets: [Int]
    private var index = 0

    init(expression: String) throws {
        self.expression = expression
        var lexer = FormulaLexer(expression)
        let lexed = try lexer.lex()
        tokens = lexed.tokens
        offsets = lexed.offsets
    }

    mutating func parse(
        fieldID: String,
        recordID: String,
        recordValues: [String: JSONValue],
        fieldsByName: [String: DataTableField],
        resolvedFormulaValues: [String: FormulaValue]
    ) throws -> FormulaValue {
        do {
            return try parseExpression(
                fieldID: fieldID,
                recordID: recordID,
                recordValues: recordValues,
                fieldsByName: fieldsByName,
                resolvedFormulaValues: resolvedFormulaValues
            )
        } catch let diagnostic as FormulaDiagnostic {
            throw diagnostic
        } catch {
            throw FormulaDiagnostic(
                fieldID: fieldID,
                recordID: recordID,
                offset: currentOffset,
                message: error.localizedDescription
            )
        }
    }

    private mutating func parseExpression(
        fieldID: String,
        recordID: String,
        recordValues: [String: JSONValue],
        fieldsByName: [String: DataTableField],
        resolvedFormulaValues: [String: FormulaValue]
    ) throws -> FormulaValue {
        var value = try parseTerm(
            fieldID: fieldID,
            recordID: recordID,
            recordValues: recordValues,
            fieldsByName: fieldsByName,
            resolvedFormulaValues: resolvedFormulaValues
        )
        while let token = current {
            switch token {
            case .plus, .minus, .equal, .notEqual, .greater,
                 .greaterEqual, .less, .lessEqual:
                advance()
                let rhs = try parseTerm(
                    fieldID: fieldID,
                    recordID: recordID,
                    recordValues: recordValues,
                    fieldsByName: fieldsByName,
                    resolvedFormulaValues: resolvedFormulaValues
                )
                value = try apply(token, lhs: value, rhs: rhs)
            default:
                return value
            }
        }
        return value
    }

    private mutating func parseTerm(
        fieldID: String,
        recordID: String,
        recordValues: [String: JSONValue],
        fieldsByName: [String: DataTableField],
        resolvedFormulaValues: [String: FormulaValue]
    ) throws -> FormulaValue {
        var value = try parsePrimary(
            fieldID: fieldID,
            recordID: recordID,
            recordValues: recordValues,
            fieldsByName: fieldsByName,
            resolvedFormulaValues: resolvedFormulaValues
        )
        while let token = current {
            switch token {
            case .multiply, .divide:
                advance()
                let rhs = try parsePrimary(
                    fieldID: fieldID,
                    recordID: recordID,
                    recordValues: recordValues,
                    fieldsByName: fieldsByName,
                    resolvedFormulaValues: resolvedFormulaValues
                )
                value = try apply(token, lhs: value, rhs: rhs)
            default:
                return value
            }
        }
        return value
    }

    private mutating func parsePrimary(
        fieldID: String,
        recordID: String,
        recordValues: [String: JSONValue],
        fieldsByName: [String: DataTableField],
        resolvedFormulaValues: [String: FormulaValue]
    ) throws -> FormulaValue {
        guard let token = current else {
            throw FormulaDiagnostic(
                fieldID: fieldID,
                recordID: recordID,
                offset: currentOffset,
                message: "公式意外结束。"
            )
        }
        switch token {
        case let .number(value):
            advance()
            return .number(value)
        case let .string(value):
            advance()
            return .string(value)
        case let .field(name):
            advance()
            if let resolved = resolvedFormulaValues[name] {
                return resolved
            }
            guard let field = fieldsByName[name] else {
                throw FormulaDiagnostic(
                    fieldID: fieldID,
                    recordID: recordID,
                    offset: currentOffset,
                    message: "引用了不存在的字段 \(name)。"
                )
            }
            return FormulaValue(json: recordValues[field.id])
        case let .identifier(name):
            advance()
            if current == .leftParen {
                return try parseFunction(
                    name: name,
                    fieldID: fieldID,
                    recordID: recordID,
                    recordValues: recordValues,
                    fieldsByName: fieldsByName,
                    resolvedFormulaValues: resolvedFormulaValues
                )
            }
            switch name.lowercased() {
            case "true":
                return .boolean(true)
            case "false":
                return .boolean(false)
            case "empty", "null":
                return .empty
            default:
                throw FormulaDiagnostic(
                    fieldID: fieldID,
                    recordID: recordID,
                    offset: currentOffset,
                    message: "未知标识符 \(name)。"
                )
            }
        case .leftParen:
            advance()
            let value = try parseExpression(
                fieldID: fieldID,
                recordID: recordID,
                recordValues: recordValues,
                fieldsByName: fieldsByName,
                resolvedFormulaValues: resolvedFormulaValues
            )
            guard current == .rightParen else {
                throw FormulaDiagnostic(
                    fieldID: fieldID,
                    recordID: recordID,
                    offset: currentOffset,
                    message: "缺少右括号。"
                )
            }
            advance()
            return value
        default:
            throw FormulaDiagnostic(
                fieldID: fieldID,
                recordID: recordID,
                offset: currentOffset,
                message: "此处需要数值、字符串或字段引用。"
            )
        }
    }

    private mutating func parseFunction(
        name: String,
        fieldID: String,
        recordID: String,
        recordValues: [String: JSONValue],
        fieldsByName: [String: DataTableField],
        resolvedFormulaValues: [String: FormulaValue]
    ) throws -> FormulaValue {
        advance()
        var arguments: [FormulaValue] = []
        if current != .rightParen {
            while true {
                arguments.append(
                    try parseExpression(
                        fieldID: fieldID,
                        recordID: recordID,
                        recordValues: recordValues,
                        fieldsByName: fieldsByName,
                        resolvedFormulaValues: resolvedFormulaValues
                    )
                )
                if current == .comma {
                    advance()
                    continue
                }
                break
            }
        }
        guard current == .rightParen else {
            throw FormulaDiagnostic(
                fieldID: fieldID,
                recordID: recordID,
                offset: currentOffset,
                message: "函数缺少右括号。"
            )
        }
        advance()
        switch name.uppercased() {
        case "SUM":
            return .number(arguments.compactMap(\.number).reduce(0, +))
        case "MIN":
            return .number(arguments.compactMap(\.number).min() ?? 0)
        case "MAX":
            return .number(arguments.compactMap(\.number).max() ?? 0)
        case "ROUND":
            let value = arguments.first?.number ?? 0
            let digits = Int(arguments.dropFirst().first?.number ?? 0)
            let scale = pow(10, Double(digits))
            return .number((value * scale).rounded() / scale)
        case "CONCAT":
            return .string(arguments.map(\.string).joined())
        default:
            throw FormulaDiagnostic(
                fieldID: fieldID,
                recordID: recordID,
                offset: currentOffset,
                message: "不支持函数 \(name)。"
            )
        }
    }

    private func apply(
        _ token: FormulaToken,
        lhs: FormulaValue,
        rhs: FormulaValue
    ) throws -> FormulaValue {
        switch token {
        case .plus:
            if let left = lhs.number, let right = rhs.number {
                return .number(left + right)
            }
            return .string(lhs.string + rhs.string)
        case .minus:
            return .number((lhs.number ?? 0) - (rhs.number ?? 0))
        case .multiply:
            return .number((lhs.number ?? 0) * (rhs.number ?? 0))
        case .divide:
            guard let denominator = rhs.number, denominator != 0 else {
                throw FormulaDiagnostic(
                    fieldID: "",
                    recordID: nil,
                    offset: currentOffset,
                    message: "除数不能为 0。"
                )
            }
            return .number((lhs.number ?? 0) / denominator)
        case .equal:
            return .boolean(lhs == rhs)
        case .notEqual:
            return .boolean(lhs != rhs)
        case .greater:
            return .boolean((lhs.number ?? 0) > (rhs.number ?? 0))
        case .greaterEqual:
            return .boolean((lhs.number ?? 0) >= (rhs.number ?? 0))
        case .less:
            return .boolean((lhs.number ?? 0) < (rhs.number ?? 0))
        case .lessEqual:
            return .boolean((lhs.number ?? 0) <= (rhs.number ?? 0))
        default:
            return lhs
        }
    }

    private var current: FormulaToken? {
        tokens.indices.contains(index) ? tokens[index] : nil
    }

    private var currentOffset: Int {
        offsets.indices.contains(index) ? offsets[index] : expression.count
    }

    private mutating func advance() {
        index += 1
    }
}

private struct FormulaLexer {
    private let scalars: [Character]
    private var index = 0

    init(_ expression: String) {
        scalars = Array(expression)
    }

    mutating func lex() throws -> (tokens: [FormulaToken], offsets: [Int]) {
        var tokens: [FormulaToken] = []
        var offsets: [Int] = []
        while index < scalars.count {
            let character = scalars[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            let start = index
            switch character {
            case "+":
                tokens.append(.plus)
                index += 1
            case "-":
                tokens.append(.minus)
                index += 1
            case "*":
                tokens.append(.multiply)
                index += 1
            case "/":
                tokens.append(.divide)
                index += 1
            case "(":
                tokens.append(.leftParen)
                index += 1
            case ")":
                tokens.append(.rightParen)
                index += 1
            case ",":
                tokens.append(.comma)
                index += 1
            case "=":
                if peek(1) == "=" {
                    index += 2
                } else {
                    index += 1
                }
                tokens.append(.equal)
            case "!":
                guard peek(1) == "=" else {
                    throw FormulaDiagnostic(
                        fieldID: "",
                        offset: start,
                        message: "未知运算符 !。"
                    )
                }
                tokens.append(.notEqual)
                index += 2
            case ">":
                if peek(1) == "=" {
                    tokens.append(.greaterEqual)
                    index += 2
                } else {
                    tokens.append(.greater)
                    index += 1
                }
            case "<":
                if peek(1) == "=" {
                    tokens.append(.lessEqual)
                    index += 2
                } else {
                    tokens.append(.less)
                    index += 1
                }
            case "{":
                index += 1
                var name = ""
                while index < scalars.count, scalars[index] != "}" {
                    name.append(scalars[index])
                    index += 1
                }
                guard index < scalars.count else {
                    throw FormulaDiagnostic(
                        fieldID: "",
                        offset: start,
                        message: "字段引用缺少右花括号。"
                    )
                }
                index += 1
                tokens.append(.field(name))
            case "\"", "'":
                let quote = character
                index += 1
                var value = ""
                while index < scalars.count, scalars[index] != quote {
                    value.append(scalars[index])
                    index += 1
                }
                guard index < scalars.count else {
                    throw FormulaDiagnostic(
                        fieldID: "",
                        offset: start,
                        message: "字符串缺少结束引号。"
                    )
                }
                index += 1
                tokens.append(.string(value))
            default:
                if character.isNumber
                    || (character == "." && peek(1)?.isNumber == true) {
                    var value = ""
                    while index < scalars.count,
                          scalars[index].isNumber
                            || scalars[index] == "." {
                        value.append(scalars[index])
                        index += 1
                    }
                    guard let number = Double(value) else {
                        throw FormulaDiagnostic(
                            fieldID: "",
                            offset: start,
                            message: "无效数字 \(value)。"
                        )
                    }
                    tokens.append(.number(number))
                } else if character.isLetter || character == "_" {
                    var identifier = ""
                    while index < scalars.count,
                          scalars[index].isLetter
                            || scalars[index].isNumber
                            || scalars[index] == "_" {
                        identifier.append(scalars[index])
                        index += 1
                    }
                    tokens.append(.identifier(identifier))
                } else {
                    throw FormulaDiagnostic(
                        fieldID: "",
                        offset: start,
                        message: "不支持的字符 \(character)。"
                    )
                }
            }
            offsets.append(start)
        }
        tokens.append(.end)
        offsets.append(scalars.count)
        return (tokens, offsets)
    }

    private func peek(_ offset: Int) -> Character? {
        let position = index + offset
        return scalars.indices.contains(position) ? scalars[position] : nil
    }
}

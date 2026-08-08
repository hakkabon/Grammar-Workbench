let tree = try ArithmeticParser.parse("10 + 20")
let value = tree.evaluate(
    terminal: { Int($0.lexeme ?? "") ?? 0 },
    reduce: { _, symbol, children, _ in
        symbol == "Sum" ? children.reduce(0, +) : (children.first ?? 0)
    }
)
guard tree.symbol == "Sum", value == 30 else { fatalError("Unexpected generated parser output") }
print("plugin-consumer-ok")

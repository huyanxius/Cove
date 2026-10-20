/// 按 API key 计费口径估算花费。每百万 token 的美元价格，只区分模型家族；
/// 缓存读写按输入价的 0.1 / 1.25 倍折算。价格随官方调整会变，这里是 2026-09 的公开价。
public enum PriceTable {
    public struct Price: Equatable, Sendable {
        public let input: Double
        public let output: Double
    }

    public static func price(forModel id: String) -> Price? {
        let id = id.lowercased()
        if id.contains("opus") { return Price(input: 5, output: 25) }
        if id.contains("sonnet") { return Price(input: 3, output: 15) }
        if id.contains("haiku") { return Price(input: 1, output: 5) }
        if id.contains("fable") { return Price(input: 10, output: 50) }
        return nil
    }

    public static func estimate(model: String, input: Int, output: Int, cacheRead: Int = 0, cacheWrite: Int = 0) -> Double? {
        guard let p = price(forModel: model) else { return nil }
        let inputCost = Double(input) * p.input + Double(cacheRead) * p.input * 0.1 + Double(cacheWrite) * p.input * 1.25
        return (inputCost + Double(output) * p.output) / 1_000_000
    }
}

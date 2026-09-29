import Foundation

/// claude 每次重绘状态栏时交给 statusLine 命令的那份 JSON，Cove 关心的部分。
///
/// 这是 CLI 唯一对外暴露额度数据的地方：5 小时 / 7 天窗口的已用百分比和重置时间、
/// 上下文占用、累计 token。Cove 经 `--settings` 挂一个转发脚本把它落盘，再在这里解析。
/// 字段可能缺失（API key 用户没有 rate_limits，第一轮回复前没有 context_window），缺了就是 nil。
public struct UsageSnapshot: Equatable, Sendable {
    public var modelID: String?
    public var modelName: String?
    public var contextPercent: Double?
    public var fiveHourPercent: Double?
    public var fiveHourResetsAt: Date?
    public var sevenDayPercent: Double?
    public var sevenDayResetsAt: Date?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cacheReadTokens: Int?
    public var cacheWriteTokens: Int?
    /// CLI 自己算的累计花费（API key 计费口径）；订阅用户也会有，只是不真正扣钱。
    public var reportedCostUSD: Double?
    /// 模型实际在生成的累计秒数，用作「工作时长」。
    public var apiDuration: TimeInterval?

    public init() {}

    public static func parse(_ data: Data) -> UsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var usage = UsageSnapshot()
        let model = object["model"] as? [String: Any]
        usage.modelID = model?["id"] as? String
        usage.modelName = model?["display_name"] as? String
        let context = object["context_window"] as? [String: Any]
        usage.contextPercent = number(context?["used_percentage"])
        usage.inputTokens = number(context?["total_input_tokens"]).map { Int($0) }
        usage.outputTokens = number(context?["total_output_tokens"]).map { Int($0) }
        let current = context?["current_usage"] as? [String: Any]
        usage.cacheReadTokens = number(current?["cache_read_input_tokens"]).map { Int($0) }
        usage.cacheWriteTokens = number(current?["cache_creation_input_tokens"]).map { Int($0) }
        let limits = object["rate_limits"] as? [String: Any]
        let five = limits?["five_hour"] as? [String: Any]
        let seven = limits?["seven_day"] as? [String: Any]
        usage.fiveHourPercent = number(five?["used_percentage"])
        usage.fiveHourResetsAt = date(five?["resets_at"])
        usage.sevenDayPercent = number(seven?["used_percentage"])
        usage.sevenDayResetsAt = date(seven?["resets_at"])
        let cost = object["cost"] as? [String: Any]
        usage.reportedCostUSD = number(cost?["total_cost_usd"])
        usage.apiDuration = number(cost?["total_api_duration_ms"]).map { $0 / 1000 }
        return usage
    }

    /// claude 有时推来不带 rate_limits 的快照（比如刚重绘、还没收到 API 响应头），
    /// 用新值覆盖旧值，但缺失的字段沿用上一次的读数，圆环不会闪回「—」。
    public func merged(over previous: UsageSnapshot?) -> UsageSnapshot {
        guard let previous else { return self }
        var m = self
        m.modelID = modelID ?? previous.modelID
        m.modelName = modelName ?? previous.modelName
        m.contextPercent = contextPercent ?? previous.contextPercent
        m.fiveHourPercent = fiveHourPercent ?? previous.fiveHourPercent
        m.fiveHourResetsAt = fiveHourResetsAt ?? previous.fiveHourResetsAt
        m.sevenDayPercent = sevenDayPercent ?? previous.sevenDayPercent
        m.sevenDayResetsAt = sevenDayResetsAt ?? previous.sevenDayResetsAt
        m.inputTokens = inputTokens ?? previous.inputTokens
        m.outputTokens = outputTokens ?? previous.outputTokens
        m.cacheReadTokens = cacheReadTokens ?? previous.cacheReadTokens
        m.cacheWriteTokens = cacheWriteTokens ?? previous.cacheWriteTokens
        m.reportedCostUSD = reportedCostUSD ?? previous.reportedCostUSD
        m.apiDuration = apiDuration ?? previous.apiDuration
        return m
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    /// 重置时间有两种写法：ISO 8601 字符串，或 Unix 秒。
    private static func date(_ value: Any?) -> Date? {
        if let n = value as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        guard let s = value as? String else { return nil }
        if let seconds = Double(s) { return Date(timeIntervalSince1970: seconds) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: s) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: s)
    }
}

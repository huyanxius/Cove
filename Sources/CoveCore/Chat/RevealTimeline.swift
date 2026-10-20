/// 流式输出里每个字「开始浮现」的时间，像打字机一样严格按顺序排。
///
/// 不能每批字各自错开：前一批的最后几个字还排在后面，下一批已经到了，它的第一个字就会抢在
/// 前面冒出来。这里把所有字排成一条时间线：每个字 = max(它所在那批的到达时间, 前一个字 + 间隔)。
/// 排队积压超过 `backlogLimit` 时把间隔压到 `catchUpStep`，显示不会越来越落后于实际输出。
public enum RevealTimeline {
    public static func reveal(batches: [(count: Int, arrived: Double)],
                              step: Double = 0.02, catchUpStep: Double = 0.004,
                              backlogLimit: Double = 0.25) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(batches.reduce(0) { $0 + $1.count })
        var cursor = -Double.infinity
        for batch in batches {
            for _ in 0..<batch.count {
                let backlog = cursor - batch.arrived
                let next = max(batch.arrived, cursor + (backlog > backlogLimit ? catchUpStep : step))
                result.append(next)
                cursor = next
            }
        }
        return result
    }
}

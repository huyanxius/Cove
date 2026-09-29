/// 拖进输入框或粘贴进来的文件，写成什么样的文字交给 CLI。
///
/// 就是绝对路径：claude、codex、agy 都能从消息里的路径读文件，图片路径 claude 会当图片看。
/// 带空格的路径加双引号，不然 CLI 会在空格处截断；前后补空格，免得和已有的字粘在一起。
public enum AttachmentReference {
    public static func text(for paths: [String]) -> String {
        guard !paths.isEmpty else { return "" }
        return " " + paths.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ") + " "
    }
}

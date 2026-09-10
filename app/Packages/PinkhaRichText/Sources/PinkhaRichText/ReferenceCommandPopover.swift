import UIKit

public enum ReferenceCommandParseResult: Equatable, Sendable {
    case inactive
    case active(query: String)
    case cancelled
}

public func parseReferenceCommand(text: String, selection: NSRange) -> ReferenceCommandParseResult {
    let ns = text as NSString
    guard selection.length == 0, selection.location == ns.length,
          ns.length > 0, ns.substring(with: NSRange(location: 0, length: 1)) == "/"
    else { return .inactive }
    let query = ns.substring(from: 1)
    if query.contains("  ") || query.contains("\n") || query.contains("\t") { return .cancelled }
    return .active(query: query)
}

final class ReferenceCommandPopoverController: UITableViewController {
    var onPick: ((ReferenceCommandCandidate) -> Void)?
    private var candidates: [ReferenceCommandCandidate] = []

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "reference")
        tableView.rowHeight = 44
        tableView.keyboardDismissMode = .none
    }

    func update(_ values: [ReferenceCommandCandidate]) {
        candidates = values
        tableView.reloadData()
        preferredContentSize = CGSize(width: 320, height: min(CGFloat(max(values.count, 1)) * 44 + 16, 308))
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { candidates.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "reference", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = candidates[indexPath.row].title
        content.textProperties.numberOfLines = 2
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onPick?(candidates[indexPath.row])
    }
}

extension UIView {
    var nearestViewController: UIViewController? {
        sequence(first: next, next: { $0?.next }).first { $0 is UIViewController } as? UIViewController
    }
}

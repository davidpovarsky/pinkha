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

public struct ReferenceCommandPreviewData: Sendable {
    public let canonicalRef: String
    public let labelHe: String
    public let previewText: String
    public let isEmbeddable: Bool

    public init(
        canonicalRef: String,
        labelHe: String,
        previewText: String,
        isEmbeddable: Bool = true
    ) {
        self.canonicalRef = canonicalRef
        self.labelHe = labelHe
        self.previewText = previewText
        self.isEmbeddable = isEmbeddable
    }
}

public enum ReferenceCommandPickAction: Sendable {
    case insertFull(candidate: ReferenceCommandCandidate)
    case insertExcerpt(candidate: ReferenceCommandCandidate, selectedText: String, range: NSRange)
    case openInspector(candidate: ReferenceCommandCandidate)
}

final class ReferenceCommandPopoverController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextViewDelegate {
    var onPick: ((ReferenceCommandCandidate) -> Void)?
    var onAction: ((ReferenceCommandPickAction) -> Void)?
    var onPreview: ((ReferenceCommandCandidate) async -> ReferenceCommandPreviewData?)?

    private var candidates: [ReferenceCommandCandidate] = []
    private var activeCandidate: ReferenceCommandCandidate?
    private var activePreview: ReferenceCommandPreviewData?
    private var previewTask: Task<Void, Never>?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let previewPane = UIView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let previewTitleLabel = UILabel()
    private let previewTextView = UITextView()
    private let broadNoticeLabel = UILabel()
    private let topActionBar = UIStackView()
    private let openInspectorButton = UIButton(type: .system)
    private let insertAllButton = UIButton(type: .system)
    private let insertExcerptButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupTableView()
        setupPreviewPane()
        setupLayout()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "reference")
        tableView.rowHeight = 44
        tableView.keyboardDismissMode = .none
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
    }

    private func setupPreviewPane() {
        previewPane.translatesAutoresizingMaskIntoConstraints = false
        previewPane.backgroundColor = .secondarySystemBackground
        previewPane.layer.cornerRadius = 10
        previewPane.layer.masksToBounds = true
        view.addSubview(previewPane)

        // Title
        previewTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        previewTitleLabel.font = .preferredFont(forTextStyle: .headline)
        previewTitleLabel.textAlignment = .right
        previewTitleLabel.numberOfLines = 1
        previewPane.addSubview(previewTitleLabel)

        // Top actions
        topActionBar.translatesAutoresizingMaskIntoConstraints = false
        topActionBar.axis = .horizontal
        topActionBar.spacing = 8
        topActionBar.alignment = .center

        openInspectorButton.setTitle("עיון", for: .normal)
        openInspectorButton.setImage(UIImage(systemName: "sidebar.right"), for: .normal)
        openInspectorButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        openInspectorButton.addTarget(self, action: #selector(didTapOpenInspector), for: .touchUpInside)

        insertAllButton.setTitle("הוסף הכל", for: .normal)
        insertAllButton.setImage(UIImage(systemName: "arrow.down.doc"), for: .normal)
        insertAllButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        insertAllButton.addTarget(self, action: #selector(didTapInsertAll), for: .touchUpInside)

        topActionBar.addArrangedSubview(openInspectorButton)
        topActionBar.addArrangedSubview(insertAllButton)
        previewPane.addSubview(topActionBar)

        // Text preview
        previewTextView.translatesAutoresizingMaskIntoConstraints = false
        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.font = .preferredFont(forTextStyle: .subheadline)
        previewTextView.textAlignment = .right
        previewTextView.backgroundColor = .clear
        previewTextView.delegate = self
        previewPane.addSubview(previewTextView)

        // Broad reference notice
        broadNoticeLabel.translatesAutoresizingMaskIntoConstraints = false
        broadNoticeLabel.font = .preferredFont(forTextStyle: .callout)
        broadNoticeLabel.textAlignment = .center
        broadNoticeLabel.textColor = .secondaryLabel
        broadNoticeLabel.numberOfLines = 0
        broadNoticeLabel.text = "מקור רחב (כגון מסכת שלמה)\nלחץ לפתיחה בעיון וניווט"
        broadNoticeLabel.isHidden = true
        previewPane.addSubview(broadNoticeLabel)

        // Bottom excerpt button
        insertExcerptButton.translatesAutoresizingMaskIntoConstraints = false
        insertExcerptButton.setTitle("הוסף קטע נבחר", for: .normal)
        insertExcerptButton.setImage(UIImage(systemName: "selection.pin.in.out"), for: .normal)
        insertExcerptButton.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        insertExcerptButton.isEnabled = false
        insertExcerptButton.addTarget(self, action: #selector(didTapInsertExcerpt), for: .touchUpInside)
        previewPane.addSubview(insertExcerptButton)

        // Loading
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        previewPane.addSubview(loadingIndicator)
    }

    private func setupLayout() {
        let isWide = traitCollection.horizontalSizeClass == .regular || view.bounds.width >= 500

        if isWide {
            NSLayoutConstraint.activate([
                tableView.topAnchor.constraint(equalTo: view.topAnchor),
                tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tableView.widthAnchor.constraint(equalToConstant: 240),

                previewPane.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
                previewPane.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
                previewPane.leadingAnchor.constraint(equalTo: tableView.trailingAnchor, constant: 8),
                previewPane.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            ])
        } else {
            NSLayoutConstraint.activate([
                tableView.topAnchor.constraint(equalTo: view.topAnchor),
                tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                tableView.heightAnchor.constraint(equalToConstant: 130),

                previewPane.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 4),
                previewPane.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
                previewPane.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                previewPane.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            ])
        }

        NSLayoutConstraint.activate([
            previewTitleLabel.topAnchor.constraint(equalTo: previewPane.topAnchor, constant: 8),
            previewTitleLabel.trailingAnchor.constraint(equalTo: previewPane.trailingAnchor, constant: -8),
            previewTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: topActionBar.trailingAnchor, constant: 8),

            topActionBar.centerYAnchor.constraint(equalTo: previewTitleLabel.centerYAnchor),
            topActionBar.leadingAnchor.constraint(equalTo: previewPane.leadingAnchor, constant: 8),

            previewTextView.topAnchor.constraint(equalTo: previewTitleLabel.bottomAnchor, constant: 6),
            previewTextView.leadingAnchor.constraint(equalTo: previewPane.leadingAnchor, constant: 8),
            previewTextView.trailingAnchor.constraint(equalTo: previewPane.trailingAnchor, constant: -8),
            previewTextView.bottomAnchor.constraint(equalTo: insertExcerptButton.topAnchor, constant: -4),

            broadNoticeLabel.centerXAnchor.constraint(equalTo: previewPane.centerXAnchor),
            broadNoticeLabel.centerYAnchor.constraint(equalTo: previewPane.centerYAnchor),
            broadNoticeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: previewPane.leadingAnchor, constant: 16),
            broadNoticeLabel.trailingAnchor.constraint(lessThanOrEqualTo: previewPane.trailingAnchor, constant: -16),

            insertExcerptButton.bottomAnchor.constraint(equalTo: previewPane.bottomAnchor, constant: -6),
            insertExcerptButton.centerXAnchor.constraint(equalTo: previewPane.centerXAnchor),
            insertExcerptButton.heightAnchor.constraint(equalToConstant: 28),

            loadingIndicator.centerXAnchor.constraint(equalTo: previewPane.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: previewPane.centerYAnchor),
        ])
    }

    func update(_ values: [ReferenceCommandCandidate]) {
        candidates = values
        tableView.reloadData()

        let isWide = traitCollection.horizontalSizeClass == .regular || UIScreen.main.bounds.width >= 600
        if isWide {
            preferredContentSize = CGSize(width: 580, height: min(CGFloat(max(values.count, 1)) * 44 + 40, 360))
        } else {
            preferredContentSize = CGSize(width: 360, height: 350)
        }

        if let first = values.first, activeCandidate == nil {
            selectCandidate(first)
            tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .top)
        }
    }

    private func selectCandidate(_ candidate: ReferenceCommandCandidate) {
        activeCandidate = candidate
        previewTitleLabel.text = candidate.title
        previewTask?.cancel()
        insertExcerptButton.isEnabled = false

        guard let onPreview else {
            previewTextView.text = ""
            return
        }

        loadingIndicator.startAnimating()
        previewTask = Task { @MainActor in
            let preview = await onPreview(candidate)
            guard !Task.isCancelled else { return }
            self.loadingIndicator.stopAnimating()
            self.activePreview = preview

            if let preview {
                self.previewTitleLabel.text = preview.labelHe
                if preview.isEmbeddable {
                    self.broadNoticeLabel.isHidden = true
                    self.previewTextView.isHidden = false
                    self.insertAllButton.isHidden = false
                    self.previewTextView.text = preview.previewText
                } else {
                    self.broadNoticeLabel.isHidden = false
                    self.previewTextView.isHidden = true
                    self.insertAllButton.isHidden = true
                    self.insertExcerptButton.isHidden = true
                }
            } else {
                self.previewTextView.text = ""
            }
        }
    }

    // MARK: - Actions

    @objc private func didTapOpenInspector() {
        guard let candidate = activeCandidate else { return }
        if let onAction {
            onAction(.openInspector(candidate: candidate))
        } else {
            onPick?(candidate)
        }
    }

    @objc private func didTapInsertAll() {
        guard let candidate = activeCandidate else { return }
        if let onAction {
            onAction(.insertFull(candidate: candidate))
        } else {
            onPick?(candidate)
        }
    }

    @objc private func didTapInsertExcerpt() {
        guard let candidate = activeCandidate else { return }
        let selectedRange = previewTextView.selectedRange
        guard selectedRange.length > 0,
              let text = previewTextView.text,
              let range = Range(selectedRange, in: text) else { return }
        let excerpt = String(text[range])
        onAction?(.insertExcerpt(candidate: candidate, selectedText: excerpt, range: selectedRange))
    }

    // MARK: - Table view

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { candidates.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "reference", for: indexPath)
        let candidate = candidates[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = candidate.title
        content.textProperties.numberOfLines = 2
        content.image = UIImage(systemName: "book.closed")
        cell.contentConfiguration = content

        // iPad pointer hover support
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        cell.addGestureRecognizer(hover)
        return cell
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        guard recognizer.state == .began,
              let cell = recognizer.view as? UITableViewCell,
              let indexPath = tableView.indexPath(for: cell),
              indexPath.row < candidates.count else { return }
        tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
        selectCandidate(candidates[indexPath.row])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.row < candidates.count else { return }
        selectCandidate(candidates[indexPath.row])
    }

    // MARK: - UITextViewDelegate (Excerpt Selection)

    func textViewDidChangeSelection(_ textView: UITextView) {
        let hasSelection = textView.selectedRange.length > 0
        insertExcerptButton.isEnabled = hasSelection
        if hasSelection {
            insertExcerptButton.setTitle("הוסף קטע (\(textView.selectedRange.length) תווים)", for: .normal)
        } else {
            insertExcerptButton.setTitle("הוסף קטע נבחר", for: .normal)
        }
    }
}

extension UIView {
    var nearestViewController: UIViewController? {
        sequence(first: next, next: { $0?.next }).first { $0 is UIViewController } as? UIViewController
    }
}

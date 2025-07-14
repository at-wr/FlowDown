//
//  Created by ktiays on 2025/2/28.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import GlyphixTextFx
import RichEditor
import SnapKit
import UIKit

final class ToolHintView: MessageListRowView {
    enum State {
        case running
        case suceeded
        case failed
    }

    var text: String? {
        didSet {
            updateContent()
        }
    }

    var toolName: String = .init() {
        didSet {
            updateContent()
        }
    }

    var state: State = .running {
        didSet {
            updateState()
        }
    }

    var clickHandler: (() -> Void)?

    private let label: GlyphixTextLabel = .init().with {
        $0.isBlurEffectEnabled = false
    }

    private let symbolView: UIImageView = .init()
    private let decoratedView: UIImageView = .init(image: richEditorIcon(named: "tools"))
    private var isClickable: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        decoratedView.contentMode = .scaleAspectFit
        decoratedView.tintColor = .label

        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.addSubview(decoratedView)
        contentView.addSubview(symbolView)
        contentView.addSubview(label)

        symbolView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.equalToSuperview().offset(12)
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        contentView.addGestureRecognizer(tapGesture)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let labelSize = label.intrinsicContentSize
        label.frame = .init(
            x: symbolView.frame.maxX + 8,
            y: (contentView.bounds.height - labelSize.height) / 2,
            width: labelSize.width,
            height: labelSize.height
        )

        contentView.frame.size.width = label.frame.maxX + 18
        decoratedView.frame = .init(x: contentView.bounds.width - 12, y: -4, width: 16, height: 16)
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        label.font = theme.fonts.body
    }

    private func updateState() {
        let configuration = UIImage.SymbolConfiguration(scale: .small)
        switch state {
        case .suceeded:
            contentView.backgroundColor = .systemGreen.withAlphaComponent(0.05)
            let image = UIImage(systemName: "checkmark.seal", withConfiguration: configuration)
            symbolView.image = image
            symbolView.tintColor = .systemGreen
        default:
            contentView.backgroundColor = .systemRed.withAlphaComponent(0.05)
            let image = UIImage(systemName: "xmark.seal", withConfiguration: configuration)
            symbolView.image = image
            symbolView.tintColor = .systemRed
        }
        setNeedsLayout()
    }

    private func updateContent() {
        isClickable = true
        label.text = .init(localized: "Tool call for \(toolName) completed.")
        label.invalidateIntrinsicContentSize()
        label.sizeToFit()
        setNeedsLayout()
    }

    @objc
    private func handleTap(_ sender: UITapGestureRecognizer) {
        if isClickable, sender.state == .ended {
            clickHandler?()
        }
    }
}

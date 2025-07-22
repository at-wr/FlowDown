//
//  BlockButton.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/17.
//

import UIKit

class BlockButton: UIView {
    let borderView = UIView()
    let iconView = UIImageView()
    let titleLabel = UILabel()
    private let tapGesture = UITapGestureRecognizer()

    var actionBlock: () -> Void = {}
    var contextMenuChecker: (() -> Bool)?

    let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
    let spacing: CGFloat = 8
    let inset: CGFloat = 8
    let iconSize: CGFloat = 16

    var tapGestureRecognizer: UITapGestureRecognizer {
        tapGesture
    }

    init(text: String, icon: String) {
        super.init(frame: .zero)

        addSubview(borderView)
        addSubview(iconView)
        addSubview(titleLabel)
        iconView.image = UIImage(named: icon, in: .module, with: nil)?
            .withRenderingMode(.alwaysTemplate)
        titleLabel.text = text
        applyDefaultAppearance()

        tapGesture.addTarget(self, action: #selector(onTapped))
        addGestureRecognizer(tapGesture)
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: CGSize {
        .init(
            width: ceil(inset + iconSize + spacing + titleLabel.intrinsicContentSize.width + inset),
            height: ceil(max(iconSize, titleLabel.intrinsicContentSize.height) + inset * 2)
        )
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyDefaultAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        borderView.frame = bounds
        iconView.frame = .init(
            x: inset,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        titleLabel.frame = .init(
            x: iconView.frame.maxX + spacing,
            y: inset,
            width: bounds.width - iconView.frame.maxX - spacing - inset,
            height: bounds.height - inset * 2
        )
    }

    @objc private func onTapped() {
        if let checker = contextMenuChecker, checker() {
            return
        }
        puddingAnimate()
        actionBlock()
    }

    func applyDefaultAppearance() {
        borderView.backgroundColor = .clear
        borderView.layer.borderColor = UIColor.label.withAlphaComponent(0.1).cgColor
        borderView.layer.borderWidth = 1
        borderView.layer.cornerRadius = 8
        borderView.layer.cornerCurve = .continuous
        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit
        titleLabel.font = font
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.textAlignment = .center
    }
}

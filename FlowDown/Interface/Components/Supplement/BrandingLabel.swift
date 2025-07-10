//
//  BrandingLabel.swift
//  FlowDown
//
//  Created by 秋星桥 on 2024/12/31.
//

import AlertController
import ConfigurableKit
import UIKit

class BrandingLabel: UILabel {
    static let configurableObject = ConfigurableObject(
        icon: "pencil",
        title: String(localized: "Edit Branding Name"),
        explain: String(localized: "Change the branding name display in the app. Leave it empty to use FlowDown."),
        key: "BrandingLabel.Text",
        defaultValue: .init(String(localized: "FlowDown")),
        annotation: .action { controller in
            let alert = AlertInputViewController(
                title: String(localized: "Edit Branding Name"),
                message: String(localized: "Change the branding name display in the app. Leave it empty to use FlowDown."),
                placeholder: String(localized: "FlowDown"),
                text: BrandingLabel.readBrandingValue(),
                cancelButtonText: String(localized: "Cancel"),
                doneButtonText: String(localized: "Set"),
            ) { text in
                BrandingLabel.setBrandingValue(text)
                NotificationCenter.default.post(name: .brandingLabelNeedsUpdate, object: nil)
            }
            controller?.present(alert, animated: true)
        }
    )

    static func setBrandingValue(_ value: String) {
        UserDefaults.standard.set(value, forKey: BrandingLabel.configurableObject.key)
    }

    static func readBrandingValue() -> String {
        if let value = UserDefaults.standard.string(forKey: BrandingLabel.configurableObject.key),
           !value.isEmpty
        { return value }
        return String(localized: "FlowDown")
    }

    init() {
        super.init(frame: .zero)
        text = String(localized: "FlowDown")
        textColor = .label
        font = .systemFont(ofSize: UIFont.labelFontSize, weight: .semibold)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateBrandingLabel),
            name: .brandingLabelNeedsUpdate,
            object: nil
        )
        updateBrandingLabel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func updateBrandingLabel() {
        text = BrandingLabel.readBrandingValue()
        sizeToFit() // Ensure the label resizes to fit the new text
    }
}

extension Notification.Name {
    static let brandingLabelNeedsUpdate = Notification.Name("BrandingLabelNeedsUpdate")
}

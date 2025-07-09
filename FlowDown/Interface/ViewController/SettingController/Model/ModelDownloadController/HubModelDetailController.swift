//
//  HubModelDetailController.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/28/25.
//

import AlertController
import ConfigurableKit
import MarkdownParser
import MarkdownView
import UIKit

class HubModelDetailController: StackScrollController {
    let model: HubModelDownloadController.RemoteModel
    init(model: HubModelDownloadController.RemoteModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Model Detail")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    let card = ModelCardView()
    let markdownContainerView = UIView()
    let indicator = UIActivityIndicatorView(style: .medium)
    var task: Task<Void, Error>?

    @BareCodableStorage(key: "ModelDownloadController.disableWarnings", defaultValue: false)
    var disableWarnings

    override func viewDidLoad() {
        super.viewDidLoad()

        let url = URL(string: "https://huggingface.co/")!
            .appendingPathComponent(model.id)
            .appendingPathComponent("resolve/main")
            .appendingPathComponent("README.md")

        markdownContainerView.clipsToBounds = true

        let task = Task.detached {
            assert(!Thread.isMainThread)
            let data = try await URLSession.shared.data(from: url).0
            assert(!Thread.isMainThread)
            guard var markdown = String(data: data, encoding: .utf8) else { return }
            // remove embedded yaml tags
            let yamlBlockPattern = #"(?m)(?s)^(?:---)(.*?)(?:---|\.\.\.)"#
            markdown = markdown.replacingOccurrences(of: yamlBlockPattern, with: "", options: .regularExpression)

            DispatchQueue.global().async {
                self.setMarkdownContent(markdown)
            }
        }
        self.task = task
    }

    func setMarkdownContent(_ markdown: String) {
        let result = MarkdownParser().parse(markdown)
        var theme = MarkdownTheme()
        theme.align(to: UIFont.preferredFont(forTextStyle: .subheadline).pointSize)
        let package = MarkdownTextView.PreprocessContent(parserResult: result, theme: theme)
        DispatchQueue.main.async {
            let markdownView = MarkdownTextView()
            markdownView.theme = theme
            markdownView.setMarkdownManually(package)
            markdownView.alpha = 0
            markdownView.codePreviewHandler = { [weak self] language, code in
                let viewer = CodeEditorController(language: language, text: code.string)
                #if targetEnvironment(macCatalyst)
                    let nav = UINavigationController(rootViewController: viewer)
                    nav.view.backgroundColor = .background
                    let holder = AlertBaseController(
                        rootViewController: nav,
                        preferredWidth: 555,
                        preferredHeight: 555
                    )
                    holder.shouldDismissWhenTappedAround = true
                    holder.shouldDismissWhenEscapeKeyPressed = true
                #else
                    let holder = UINavigationController(rootViewController: viewer)
                    holder.preferredContentSize = .init(width: 555, height: 555 - holder.navigationBar.frame.height)
                    holder.modalTransitionStyle = .coverVertical
                    holder.modalPresentationStyle = .formSheet
                    holder.view.backgroundColor = .background
                #endif
                self?.present(holder, animated: true)
            }
            self.view.doWithAnimation {
                self.markdownContainerView.addSubview(markdownView)
                markdownView.snp.makeConstraints { make in
                    make.edges.equalToSuperview()
                }
                self.requiresUpdateHeight = true
            } completion: {
                self.indicator.stopAnimating()
                UIView.animate(withDuration: 0.3) {
                    markdownView.alpha = 1
                }
            }
        }
    }

    private var requiresUpdateHeight: Bool = false
    private var requiresMatchingWidth: CGFloat = 0
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let markdownView = markdownContainerView.subviews.first as? MarkdownTextView
        if let markdownView {
            let layoutWidth = markdownContainerView.bounds.width
            if requiresUpdateHeight || layoutWidth != requiresMatchingWidth {
                let size = markdownView.boundingSize(for: markdownContainerView.bounds.width)
                markdownView.snp.remakeConstraints { make in
                    make.edges.equalToSuperview()
                    make.height.equalTo(size.height).priority(.required)
                }
                requiresUpdateHeight = false
                requiresMatchingWidth = layoutWidth
            }
        }
    }

    override func setupContentViews() {
        super.setupContentViews()

        view.addSubview(indicator)
        indicator.startAnimating()

        card.icon.image = .modelLocal
        card.label.text = model.id
        stackView.addArrangedSubviewWithMargin(card)
        card.snp.makeConstraints { make in
            make.height.equalTo(card.snp.width).multipliedBy(0.35)
        }

        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(markdownContainerView)
        stackView.addArrangedSubview(SeparatorView())

        let openHuggingFace = ConfigurableActionView { _ in
            guard let url = URL(string: "https://huggingface.co/\(self.model.id)") else {
                return
            }
            UIApplication.shared.open(url)
        }
        openHuggingFace.configure(icon: UIImage(systemName: "safari"))
        openHuggingFace.configure(title: String(localized: "Open in Hugging Face"))
        openHuggingFace.configure(description: model.id)
        stackView.addArrangedSubviewWithMargin(openHuggingFace)
        stackView.addArrangedSubview(SeparatorView())

        indicator.snp.makeConstraints { make in
            make.center.equalTo(markdownContainerView)
        }
        markdownContainerView.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(200).priority(.high)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateBarItems()
    }

    func updateBarItems() {
        if ModelManager.shared.localModelExists(repoIdentifier: model.id) {
            navigationItem.rightBarButtonItem = .init(
                image: .init(systemName: "checkmark"),
                style: .done,
                target: self,
                action: #selector(download)
            )
        } else {
            navigationItem.rightBarButtonItem = .init(
                title: String(localized: "Download"),
                style: .plain,
                target: self,
                action: #selector(download)
            )
        }
    }

    @objc func download() {
        let model = model
        let downloadController = HubModelDownloadProgressController(model: model)
        downloadController.onDismiss = { [weak self] in
            self?.updateBarItems()
        }

        if ModelManager.shared.localModelExists(repoIdentifier: model.id) {
            navigationController?.popViewController()
            return
        }

        if disableWarnings {
            present(downloadController, animated: true)
        } else if model.id.lowercased().hasPrefix("mlx-community/") {
            let alert = AlertViewController(
                title: String(localized: "Download Model"),
                message: String(localized: "We are not responsible for the model you are about to download. If we are unable to load this model, the app may crash. Do you want to continue?")
            ) { context in
                context.addAction(title: String(localized: "Cancel")) {
                    context.dispose()
                }
                context.addAction(title: String(localized: "Download"), attribute: .dangerous) {
                    context.dispose { [weak self] in
                        self?.present(downloadController, animated: true)
                    }
                }
            }
            present(alert, animated: true)
        } else {
            let alert = AlertViewController(
                title: String(localized: "Unverified Model"),
                message: String(localized: "Even if you download this model, it may not work or even crash the app. Do you still want to download this model?")
            ) { context in
                context.addAction(title: String(localized: "Cancel")) {
                    context.dispose()
                }
                context.addAction(title: String(localized: "Download"), attribute: .dangerous) {
                    context.dispose { [weak self] in
                        self?.present(downloadController, animated: true)
                    }
                }
            }
            present(alert, animated: true)
        }
    }
}

extension HubModelDetailController {
    class ModelCardView: UIView {
        let background = UIView().with {
            $0.backgroundColor = .accent
            let img = UIImageView()
            img.contentMode = .scaleAspectFill
            img.image = .circularTexture
            img.alpha = 0.05
            $0.addSubview(img)
            img.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        }

        let icon = UIImageView().with {
            $0.image = .modelLocal
            $0.contentMode = .scaleAspectFit
            $0.tintColor = .white
        }

        let label = UILabel().with {
            $0.text = String(localized: "Model Card")
            $0.font = .preferredFont(forTextStyle: .body)
            $0.textColor = .white
            $0.numberOfLines = 0
        }

        let stackView = UIStackView().with {
            $0.axis = .vertical
            $0.spacing = 16
            $0.alignment = .center
            $0.distribution = .fill
        }

        init() {
            super.init(frame: .zero)

            clipsToBounds = true
            layer.cornerRadius = 16
            layer.cornerCurve = .continuous

            backgroundColor = .black

            addSubview(background)
            background.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }

            addSubview(stackView)
            stackView.snp.makeConstraints { make in
                make.left.right.equalToSuperview().inset(20)
                make.center.equalToSuperview()
                make.top.greaterThanOrEqualToSuperview().inset(20)
                make.bottom.lessThanOrEqualToSuperview().inset(20)
            }

            stackView.addArrangedSubview(icon)
            stackView.addArrangedSubview(label)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }
    }
}

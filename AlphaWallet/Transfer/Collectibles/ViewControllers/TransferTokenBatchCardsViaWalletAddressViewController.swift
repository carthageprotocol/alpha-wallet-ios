//
//  TransferTokenBatchCardsViaWalletAddressViewController.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 07.09.2021.
//

import UIKit

protocol TransferTokenBatchCardsViaWalletAddressViewControllerDelegate: class, CanOpenURL {
    func didEnterWalletAddress(tokenHolders: [TokenHolder], to recipient: AlphaWallet.Address, paymentFlow: PaymentFlow, in viewController: TransferTokenBatchCardsViaWalletAddressViewController)
    func didPressViewInfo(in viewController: TransferTokenBatchCardsViaWalletAddressViewController)
    func openQRCode(in controller: TransferTokenBatchCardsViaWalletAddressViewController)

    func some(tokenHolder: TokenHolder, in viewController: TransferTokenBatchCardsViaWalletAddressViewController)
}

class TransferTokenBatchCardsViaWalletAddressViewController: UIViewController, TokenVerifiableStatusViewController {
    private let analyticsCoordinator: AnalyticsCoordinator
    private let token: TokenObject
    private lazy var targetAddressTextField: AddressTextField = {
        let textField = AddressTextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.delegate = self
        textField.returnKeyType = .done

        return textField
    }()

    private lazy var recipientHeaderView: SendViewSectionHeader = {
        let view = SendViewSectionHeader()
        view.configure(viewModel: .init(text: R.string.localizable.sendRecipient().uppercased(), showTopSeparatorLine: false))

        return view
    }()

    private lazy var amountHeaderView: SendViewSectionHeader = {
        let view = SendViewSectionHeader()
        view.configure(viewModel: .init(text: R.string.localizable.sendAmount().uppercased()))

        return view
    }()

    private lazy var selectedTokenCardsHeaderView: SendViewSectionHeader = {
        let view = SendViewSectionHeader()
        view.configure(viewModel: .init(text: "Selected tokens".uppercased()))

        return view
    }()

    private lazy var selectTokenCardAmountView: SelectTokenCardAmountView = {
        let view = SelectTokenCardAmountView(viewModel: .init(availableAmount: 20, selectedAmount: 0))
        view.delegate = self

        return view
    }()

    private let buttonsBar = ButtonsBar(configuration: .green(buttons: 1))
    private var viewModel: TransferTokenBatchCardsViaWalletAddressViewControllerViewModel
    var tokenHolders: [TokenHolder] {
        viewModel.tokenHolders
    }
    private(set) var paymentFlow: PaymentFlow

    var contract: AlphaWallet.Address {
        return token.contractAddress
    }
    var server: RPCServer {
        return token.server
    }
    let assetDefinitionStore: AssetDefinitionStore
    weak var delegate: TransferTokenBatchCardsViaWalletAddressViewControllerDelegate?

    lazy var containerView: ScrollableStackView = {
        let view = ScrollableStackView()
        return view
    }()

    // swiftlint:disable function_body_length
    init(analyticsCoordinator: AnalyticsCoordinator, token: TokenObject, paymentFlow: PaymentFlow, viewModel: TransferTokenBatchCardsViaWalletAddressViewControllerViewModel, assetDefinitionStore: AssetDefinitionStore) {
        self.analyticsCoordinator = analyticsCoordinator
        self.token = token
        self.paymentFlow = paymentFlow
        self.viewModel = viewModel
        self.assetDefinitionStore = assetDefinitionStore

        super.init(nibName: nil, bundle: nil)

        updateNavigationRightBarButtons(withTokenScriptFileStatus: nil)

        let footerBar = ButtonsBarBackgroundView(buttonsBar: buttonsBar)
        view.addSubview(footerBar)
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: footerBar.topAnchor),

            footerBar.anchorsConstraint(to: view),
        ])

        generateSubviews(viewModel: viewModel)
    }
    // swiftlint:enable function_body_length

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    private func generateSubviews(viewModel: TransferTokenBatchCardsViaWalletAddressViewControllerViewModel) {
        containerView.stackView.removeAllArrangedSubviews()
        let subViews: [UIView] = [
            recipientHeaderView,
            targetAddressTextField.defaultLayout(edgeInsets: .init(top: 16, left: 16, bottom: 16, right: 16)),
            amountHeaderView,
            selectTokenCardAmountView,
            selectedTokenCardsHeaderView
        ] + [selectedTokenCardsHeaderView] + generateViewsForSelectedTokenHolders(viewModel: viewModel)

        containerView.stackView.addArrangedSubviews(subViews)
    }

    private lazy var factory: TokenCardTableViewCellFactory = {
        TokenCardTableViewCellFactory(tokenObject: token, assetDefinitionStore: assetDefinitionStore, analyticsCoordinator: analyticsCoordinator, server: server)
    }()
    private var cachedCellsCardRowViews: [Int: UIView & TokenCardRowViewProtocol] = [:]

    private func generateViewsForSelectedTokenHolders(viewModel: TransferTokenBatchCardsViaWalletAddressViewControllerViewModel) -> [UIView] {
        var subviews: [UIView] = []
        for (index, each) in viewModel.tokenHolders.enumerated() {
            subviews += [
                generateViewFor(tokenHolder: each, index: index),
                .separator()
            ]
        }

        return subviews
    }

    private func generateViewFor(tokenHolder: TokenHolder, index: Int) -> UIView {
        let subview: UIView & TokenCardRowViewProtocol
        if let value = cachedCellsCardRowViews[index] {
            subview = value
        } else {
            subview = factory.create(for: tokenHolder)

            cachedCellsCardRowViews[index] = subview
        }

        configureToAllowSelection(subview, tokenHolder: tokenHolder, index: index)
        configure(subview: subview, tokenId: tokenHolder.tokenId, tokenHolder: tokenHolder)

        return subview
    }

    private func configureToAllowSelection(_ subview: UIView, tokenHolder: TokenHolder, index: Int) {
        subview.isUserInteractionEnabled = true
        UITapGestureRecognizer(addToView: subview) { [weak self] in
            guard let strongSelf = self else { return }

            strongSelf.delegate.flatMap { $0.some(tokenHolder: tokenHolder, in: strongSelf) }
        }
    }

    private func configure(subview: UIView & TokenCardRowViewProtocol, tokenId: TokenId, tokenHolder: TokenHolder) {
        subview.configure(tokenHolder: tokenHolder, tokenId: tokenId, tokenView: .viewIconified, areDetailsVisible: false, width: containerView.stackView.frame.size.width, assetDefinitionStore: assetDefinitionStore)
    }

    @objc func nextButtonTapped() {
        targetAddressTextField.errorState = .none

        if let address = AlphaWallet.Address(string: targetAddressTextField.value.trimmed) {
            delegate?.didEnterWalletAddress(tokenHolders: viewModel.tokenHolders, to: address, paymentFlow: paymentFlow, in: self)
        } else {
            targetAddressTextField.errorState = .error(Errors.invalidAddress.prettyError)
        }
    }

    func configure(viewModel newViewModel: TransferTokenBatchCardsViaWalletAddressViewControllerViewModel? = nil) {
        if let newViewModel = newViewModel {
            viewModel = newViewModel
        }

        title = viewModel.navigationTitle
        updateNavigationRightBarButtons(withTokenScriptFileStatus: tokenScriptFileStatus)

        view.backgroundColor = viewModel.backgroundColor

        targetAddressTextField.label.attributedText = viewModel.targetAddressAttributedString
        targetAddressTextField.configureOnce()

        selectTokenCardAmountView.configure(viewModel: .init(availableAmount: 10, selectedAmount: 0))

        buttonsBar.configure()
        let nextButton = buttonsBar.buttons[0]
        nextButton.setTitle(R.string.localizable.aWalletNextButtonTitle(), for: .normal)
        nextButton.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)

        amountHeaderView.isHidden = viewModel.isAmountSelectionHidden
        selectTokenCardAmountView.isHidden = viewModel.isAmountSelectionHidden
    }
}

extension TransferTokenBatchCardsViaWalletAddressViewController: VerifiableStatusViewController {
    func showInfo() {
        delegate?.didPressViewInfo(in: self)
    }

    func showContractWebPage() {
        delegate?.didPressViewContractWebPage(forContract: contract, server: server, in: self)
    }

    func open(url: URL) {
        delegate?.didPressViewContractWebPage(url, in: self)
    }
}

extension TransferTokenBatchCardsViaWalletAddressViewController: AddressTextFieldDelegate {
    func didScanQRCode(_ result: String) {
        switch QRCodeValueParser.from(string: result) {
        case .address(let address):
            targetAddressTextField.value = address.eip55String
        case .eip681, .none:
            break
        }
    }

    func displayError(error: Error, for textField: AddressTextField) {
        targetAddressTextField.errorState = .error(Errors.invalidAddress.prettyError)
    }

    func openQRCodeReader(for textField: AddressTextField) {
        delegate?.openQRCode(in: self)
    }

    func didPaste(in textField: AddressTextField) {
        //Do nothing
    }

    func shouldReturn(in textField: AddressTextField) -> Bool {
        view.endEditing(true)
        return true
    }

    func didChange(to string: String, in textField: AddressTextField) {

    }
}

extension TransferTokenBatchCardsViaWalletAddressViewController: SelectTokenCardAmountViewDelegate {
    func valueDidChange(in view: SelectTokenCardAmountView) {
        viewModel.updateSelectedAmount(view.viewModel.counter)
    }
}


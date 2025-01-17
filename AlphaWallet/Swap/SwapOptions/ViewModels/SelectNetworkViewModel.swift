//
//  SelectNetworkViewModel.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 14.03.2022.
//

import UIKit
import AlphaWalletFoundation

class SelectNetworkViewModel {
    let session: WalletSession
    let isSelected: Bool
    let isAvailableToSelect: Bool
    var networkImage: Subscribable<Image> { session.server.walletConnectIconImage }

    var selectionImage: UIImage? {
        isSelected ? R.image.iconsSystemRadioOn() : R.image.iconsSystemRadioOff()
    }
    var highlightedBackgroundColor: UIColor = R.color.dove()!.withAlphaComponent(0.1)
    var normalBackgroundColor: UIColor = Colors.appBackground

    var titleAttributedString: NSAttributedString {
        NSAttributedString(string: session.server.name, attributes: [
            .font: Fonts.regular(size: 20),
            .foregroundColor: Colors.black
        ])
    }

    var subTitleAttributedString: NSAttributedString {
        NSAttributedString(string: R.string.localizable.chainIDWithPrefix(session.server.chainID), attributes: [
            .font: Fonts.regular(size: 15),
            .foregroundColor: R.color.dove()!
        ])
    }

    init(session: WalletSession, isSelected: Bool, isAvailableToSelect: Bool) {
        self.session = session
        self.isSelected = isSelected
        self.isAvailableToSelect = isAvailableToSelect
    }
}

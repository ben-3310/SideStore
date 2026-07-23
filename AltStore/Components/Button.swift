//
//  Button.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

extension UIButton
{
    func alt_setContentInsets(_ contentInsets: NSDirectionalEdgeInsets)
    {
        if #available(iOS 15, *), self.configuration != nil
        {
            self.configuration?.contentInsets = contentInsets
        }
        else
        {
            let edgeInsets = UIEdgeInsets(top: contentInsets.top, left: contentInsets.leading, bottom: contentInsets.bottom, right: contentInsets.trailing)
            self.alt_setLegacyContentEdgeInsets(edgeInsets)
        }
    }

    private func alt_setLegacyContentEdgeInsets(_ contentEdgeInsets: UIEdgeInsets)
    {
        typealias ContentEdgeInsetsSetter = @convention(c) (AnyObject, Selector, UIEdgeInsets) -> Void

        let selector = NSSelectorFromString("setContentEdgeInsets:")
        guard let method = class_getInstanceMethod(UIButton.self, selector) else { return }
        let implementation = method_getImplementation(method)
        let setter = unsafeBitCast(implementation, to: ContentEdgeInsetsSetter.self)
        setter(self, selector, contentEdgeInsets)
    }
}

final class Button: UIButton
{
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width += 20
        size.height += 10
        return size
    }

    override func awakeFromNib()
    {
        super.awakeFromNib()

        self.setTitleColor(.white, for: .normal)

        self.layer.masksToBounds = true
        self.layer.cornerRadius = 8

        self.update()
    }

    override func tintColorDidChange()
    {
        super.tintColorDidChange()

        self.update()
    }

    override var isHighlighted: Bool {
        didSet {
            self.update()
        }
    }

    override var isEnabled: Bool {
        didSet {
            self.update()
        }
    }
}

private extension Button
{
    func update()
    {
        if self.isEnabled
        {
            self.backgroundColor = self.tintColor
        }
        else
        {
            self.backgroundColor = .lightGray
        }
    }
}

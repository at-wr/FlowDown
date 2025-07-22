//
//  UIView.swift
//  FlowDown
//
//  Created by 秋星桥 on 2025/1/2.
//

import UIKit

extension UIView {
    func doWithAnimation(duration: TimeInterval = 0.5, _ execute: @escaping () -> Void, completion: @escaping () -> Void = {}) {
        layoutIfNeeded()
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 1.0,
            options: .curveEaseInOut
        ) {
            execute()
            self.layoutIfNeeded()
        } completion: { _ in
            completion()
        }
    }

    func puddingAnimate() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        transform = CGAffineTransform(scaleX: 0.975, y: 0.975)
        layoutIfNeeded()
        doWithAnimation { self.transform = .identity }
    }

    func shake() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.duration = 0.5
        animation.values = [-10, 10, -8, 8, -6, 6, -4, 4, 0]
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: "shake")
    }
}

extension UIView {
    func hideKeyboardWhenTappedAround() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(UIView.dismissKeyboard))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    @objc func dismissKeyboard() {
        endEditing(true)
    }
}

extension UIView {
    var nearestScrollView: UIScrollView? {
        var look: UIView = self
        while let superview = look.superview {
            look = superview
            if let scrollView = superview as? UIScrollView {
                return scrollView
            }
        }
        return nil
    }
}

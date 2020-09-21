//
//  ViewController.swift
//  PageDemo
//
//  Created by 吴哲 on 2020/9/21.
//  Copyright © 2020 wuzhe. All rights reserved.
//

import UIKit
import PageboyKit
import Pageboy

final class PageViewController: UIViewController {

	private lazy var label = UILabel()
	var page: Int? {
		didSet {
			label.text = "\(page ?? -1)"
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		view.addSubview(label)
		label.textColor = .black
		label.font = UIFont.boldSystemFont(ofSize: 85)
		view.backgroundColor = UIColor(
			red: CGFloat.random(in: 100..<150)/255.0,
			green: CGFloat.random(in: 100..<150)/255.0,
			blue: CGFloat.random(in: 100..<150)/255.0,
			alpha: 1
		)
		debugPrint("\(String(describing: page)): \(#function)")
	}

	override func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()
		if isViewLoaded {
			label.sizeToFit()
			label.center = view.center
		}
	}

	deinit {
		debugPrint("\(String(describing: page)): \(#function)")
	}
}

class ViewController: PageboyViewController {
	class Key {
		let value: Int
		init(_ value: Int) {
			self.value = value
		}
	}

	let cache = PageCache()

	var keys = Array(0..<20).map(Key.init)

	override func viewDidLoad() {
		super.viewDidLoad()
		navigationOrientation = .vertical
		cache.countLimit = 10
		dataSource = self
	}
}

extension ViewController: PageboyViewControllerDataSource {

	func numberOfViewControllers(in pageboyViewController: PageboyViewController) -> Int {
		return keys.count
	}

	func viewController(
		for pageboyViewController: PageboyViewController,
		at index: PageboyViewController.PageIndex
	) -> UIViewController? {
		return cache.viewController(forKey: keys[index]) {
			let page = PageViewController()
			page.page = index
			return page
		}
	}

	func defaultPage(for pageboyViewController: PageboyViewController) -> PageboyViewController.Page? {
		return .first
	}
}

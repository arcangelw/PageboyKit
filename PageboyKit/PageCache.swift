//
//  PageCache.swift
//  PageboyKit
//
//  Created by 吴哲 on 2020/9/21.
//  Copyright © 2020 wuzhe. All rights reserved.
//

import Foundation
import UIKit

@inline(__always)
func bridge<T: AnyObject>(_ obj: T) -> UnsafeRawPointer! {
	return UnsafeRawPointer(Unmanaged.passUnretained(obj).toOpaque())
}

extension LinkedMap {
	class Node {
		unowned(unsafe) var prev: Node!
		unowned(unsafe) var next: Node!
		var key: AnyObject!
		var value: UIViewController!
		var time: TimeInterval = 0.0
	}
}

final class LinkedMap {

	private var keyCallBack = kCFTypeDictionaryKeyCallBacks
	private var valueCallBack = kCFTypeDictionaryValueCallBacks
	private(set) var map: CFMutableDictionary

	var totalCount: UInt = 0

	private(set) var head: Node!
	private(set) var tail: Node!

	var releaseAsynchronously = true

	init() {
		self.map = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallBack, &valueCallBack)
	}

	func node<K: AnyObject>(forKey key: K) -> Node? {
		guard
			let ptr = CFDictionaryGetValue(map, bridge(key))
		else { return nil }
		return Unmanaged<Node>.fromOpaque(ptr).takeUnretainedValue()
	}

	/// 添加头部
	func insertAtHead(_ node: Node) {
		CFDictionarySetValue(map, bridge(node.key), bridge(node))
		totalCount += 1
		if head != nil {
			node.next = head
			head.prev = node
			head = node
		} else {
			head = node
			tail = node
		}
	}

	/// 配置到头部
	func bringToHead(_ node: Node) {
		guard head !== node else { return }
		if tail === node {
			tail = node.prev
			tail.next = nil
		} else {
			node.next.prev = node.prev
			node.prev.next = node.next
		}
		node.next = head
		node.prev = nil
		head.prev = node
		head = node
	}

	/// 移除
	func remove(_ node: Node) {
		CFDictionaryRemoveValue(map, &node.key)
		totalCount -= 1
		if node.next != nil {
			node.next.prev = node.prev
		}
		if node.prev != nil {
			node.prev.next = node.next
		}
		if head === node {
			head = node.next
		}
		if tail === node {
			tail = node.prev
		}
	}

	/// 移除尾节点
	func removeTail() -> Node? {
		guard let `tail` = self.tail  else { return nil }
		CFDictionaryRemoveValue(map, bridge(tail.key))
		totalCount -= 1
		if head === tail {
			head = nil
			self.tail = nil
		} else {
			self.tail = tail.prev
			self.tail.next = nil
		}
		return tail
	}

	/// 移除所有节点
	func removeAll() {
		totalCount = 0
		head = nil
		tail = nil
		guard CFDictionaryGetCount(map) > 0 else { return }
		let holder: CFMutableDictionary = map
		self.map = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &keyCallBack, &valueCallBack)
		if releaseAsynchronously || pthread_main_np() == 0 {
			DispatchQueue.main.async {
				CFDictionaryRemoveAllValues(holder)
			}
		}
	}
}

/// 提供一个LRU算法的UIViewController缓存
/// 因为列表中有insert、delete操作，不推荐使用索引位置来作为Key
public class PageCache {

	/// lru linked
	private let lru = LinkedMap()

	// MARK: - Limit

	/// 最大缓存数
	public var countLimit: UInt = .max

	/// 最大缓存时长
	public var ageLimit: TimeInterval = .greatestFiniteMagnitude

	/// 自动清除
	public var autoTrimInterval: TimeInterval = 30.0 * 60.0

	/// 告警处理
	public var didReceiveMemoryWarningBlock: ((PageCache) -> Void)?

	/// 进入后台处理
	public var didEnterBackgroundBlock: ((PageCache) -> Void)?

	/// releaseAsynchronously
	public var releaseAsynchronously: Bool {
		get { return lru.releaseAsynchronously }
		set { lru.releaseAsynchronously = newValue }
	}

	public init() {
		let center = NotificationCenter.default
		center.addObserver(
			self, selector: #selector(appDidReceiveMemoryWarning),
			name: UIApplication.didReceiveMemoryWarningNotification, object: nil
		)
		center.addObserver(
			self, selector: #selector(appDidEnterBackground),
			name: UIApplication.didEnterBackgroundNotification, object: nil
		)
		trimRecursively()
	}

	deinit {
		let center = NotificationCenter.default
		center.removeObserver(
			self,
			name: UIApplication.didReceiveMemoryWarningNotification, object: nil
		)
		center.removeObserver(
			self,
			name: UIApplication.didEnterBackgroundNotification, object: nil
		)
		lru.removeAll()
	}

	// MARK: -

	private func trimRecursively() {
		DispatchQueue(label: "com.pagekit.trimRecursively", qos: .utility)
			.asyncAfter(deadline: .now() + autoTrimInterval) { [weak self] in
			guard let `self` = self else { return }
			self.trimInBackground()
			self.trimRecursively()
		}
	}

	private func trimInBackground() {
		DispatchQueue.main.async {
			self.trim(toCount: self.countLimit)
			self.trim(toAge: self.ageLimit)
		}
	}

	@objc private func appDidReceiveMemoryWarning() {
		didReceiveMemoryWarningBlock?(self)
	}

	@objc private func appDidEnterBackground() {
		didEnterBackgroundBlock?(self)
	}

	// MARK: - Access Methods

	public func contains<K: AnyObject>(forKey key: K) -> Bool {
		return CFDictionaryContainsKey(lru.map, bridge(key))
	}

	public func viewController<K: AnyObject>(
		forKey key: K,
		initialValue: (() -> UIViewController)
	) -> UIViewController {
		let value: UIViewController
		if let node = lru.node(forKey: key) {
			node.time = CACurrentMediaTime()
			value = node.value
			lru.bringToHead(node)
		} else {
			value = initialValue()
			set(value, forKey: key)
		}
		return value
	}

	public func set<K: AnyObject>(_ viewController: UIViewController?, forKey key: K) {
		guard let viewController = viewController else {
			return remove(forKey: key)
		}
		let now = CACurrentMediaTime()
		if let node = lru.node(forKey: key) {
			node.time = now
			node.value = viewController
			lru.bringToHead(node)
		} else {
			let node = LinkedMap.Node()
			node.time = now
			node.key = key
			node.value = viewController
			lru.insertAtHead(node)
		}
		if lru.totalCount > countLimit, let node = lru.removeTail() {
			if lru.releaseAsynchronously || pthread_main_np() == 0 {
				DispatchQueue.main.async {
					_ = node.self
				}
			}
		}
	}

	public func remove<K: AnyObject>(forKey key: K) {
		if let node = lru.node(forKey: key) {
			lru.remove(node)
			if lru.releaseAsynchronously || pthread_main_np() == 0 {
				DispatchQueue.main.async {
					_ = node.self
				}
			}
		}
	}

	public func removeAll() {
		lru.removeAll()
	}

	public func trim(toCount count: UInt) {
		var finish = false
		if count == 0 {
			lru.removeAll()
			finish = true
		} else if lru.totalCount <= count {
			finish = true
		}
		guard !finish else { return }

		var holder: [LinkedMap.Node] = []
		while !finish {
			if lru.totalCount > count {
				if let node = lru.removeTail() {
					holder.append(node)
				}
			} else {
				finish = true
			}
		}
		guard !holder.isEmpty else { return }
		if lru.releaseAsynchronously || pthread_main_np() == 0 {
			DispatchQueue.main.async {
				holder.removeAll()
			}
		}
	}

	public func trim(toAge age: TimeInterval) {
		var finish = false
		let now = CACurrentMediaTime()
		if age <= 0.0 {
			lru.removeAll()
			finish = true
		} else if let tail = lru.tail, now - tail.time <= age {
			finish = true
		}
		guard !finish else { return }

		var holder: [LinkedMap.Node] = []
		while !finish {
			if let tail = lru.tail, now - tail.time > age {
				if let node = lru.removeTail() {
					holder.append(node)
				}
			} else {
				finish = true
			}
		}
		guard !holder.isEmpty else { return }
		if lru.releaseAsynchronously || pthread_main_np() == 0 {
			DispatchQueue.main.async {
				holder.removeAll()
			}
		}
	}
}

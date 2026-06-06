//
//  ErrorAlertItem.swift
//  LocalPackage
//
//  Created by Taichi Sato on 2026/06/06.
//

import SwiftUI

@MainActor
@Observable
public class ErrorAlertStore {
    var isPresented: Bool
    var item: ErrorAlertItem?
    
    var errorTitle: String {
        guard let error = item?.error else { return "" }
        return switch error {
        case .failedLoadVideo: "再生に失敗しました"
        case .other: "不明なエラーが発生しました"
        }
    }
    
    var errorMessage: String? {
        guard let error = item?.error else { return nil }
        return switch error {
        case .failedLoadVideo: "再度再生したい動画を選択してください"
        case .other: nil
        }
    }
        
    public init(isPresented: Bool = false, item: ErrorAlertItem? = nil) {
        self.isPresented = isPresented
        self.item = item
    }
    
    public func setItem(_ item: ErrorAlertItem) {
        self.item = item
        isPresented = true
    }
}

public struct ErrorAlertItem: Equatable {
    public let error: AppDomainError
    
    public init(error: AppDomainError) {
        self.error = error
    }
}

public extension View {
    func errorAlert(_ store: ErrorAlertStore, onClose: @escaping () -> Void) -> some View {
        @Bindable var store = store
        return self.alert(
            store.errorTitle,
            isPresented: $store.isPresented) {
                Button("閉じる") {
                    onClose()
                }
            } message: {
                if let message = store.errorMessage {
                    Text(message)
                }
            }
    }
}

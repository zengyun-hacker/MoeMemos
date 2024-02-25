//
//  ShareViewController.swift
//  MoeMemosShareExtension
//
//  Created by Mudkip on 2022/12/1.
//

import UIKit
import Social
import SwiftUI
import KeychainSwift
import UniformTypeIdentifiers
import Markdown

class ShareViewController: SLComposeServiceViewController {
    
    let shareViewHostingController = UIHostingController(rootView: MoeMemosShareView())
    
    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        if let item = self.extensionContext!.inputItems.first as? NSExtensionItem, let attachments = item.attachments {
            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    return true
                }
                
                if attachment.canLoadObject(ofClass: NSURL.self) {
                    return true
                }
            }
        }
        
        return !contentText.isEmpty
    }

    override func didSelectPost() {
        // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
        Task {
            do {
                shareViewHostingController.view.translatesAutoresizingMaskIntoConstraints = false
                self.addChild(shareViewHostingController)
                self.view.addSubview(shareViewHostingController.view)
                NSLayoutConstraint.activate([
                    shareViewHostingController.view.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                    shareViewHostingController.view.centerYAnchor.constraint(equalTo: self.view.centerYAnchor)
                ])
                try await handleShare()
                
                self.shareViewHostingController.rootView = MoeMemosShareView(alertType: .systemImage("checkmark.circle", NSLocalizedString("share.memo-saved", comment: "")))
                try await Task.sleep(nanoseconds: 2_000_000_000)
                self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
            } catch {
                self.shareViewHostingController.rootView = MoeMemosShareView(alertType: .systemImage("xmark.circle", error.localizedDescription))
                try await Task.sleep(nanoseconds: 2_000_000_000)
                self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }

    private func handleShare() async throws {
        let memos = try await getMemos()
        do {
            try await memos.loadStatus()
        } catch {
            print(error)
        }
        var resourceList = [Resource]()
        var contentTextList = [String]()
        contentTextList.append(contentText)
        
        if let item = self.extensionContext!.inputItems.first as? NSExtensionItem, let attachments = item.attachments {
            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    let result = try await attachment.loadItem(forTypeIdentifier: UTType.image.identifier)
                    var image = result as? UIImage
                    if image == nil, let url = result as? URL {
                        let data = try Data(contentsOf: url)
                        image = UIImage(data: data)
                    }
                    guard let image = image else { throw MemosError.invalidParams }
                    guard let data = image.jpegData(compressionQuality: 0.8) else { throw MemosError.invalidParams }
                    let response = try await memos.uploadResource(imageData: data, filename: "\(UUID().uuidString).jpg", contentType: "image/jpeg")
                    resourceList.append(response)
                }
                
                if attachment.canLoadObject(ofClass: NSURL.self),
                   let url = try await attachment.loadObject(ofClass: NSURL.self),
                   let address = url.absoluteString {
                    contentTextList.append(address)
                }
            }
        }
        
        let content = contentTextList.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
        if content.isEmpty && resourceList.isEmpty {
            throw MemosError.invalidParams
        }
        
        let tags = extractCustomTags(from: content)
        for name in tags {
            _ = try await memos.upsertTag(name: name)
        }
        _ = try await memos.createMemo(data: MemosCreate.Input(content: content, visibility: nil, resourceIdList: resourceList.map { $0.id }))
    }
    
    private func getMemos() async throws -> Memos {
        guard let host = UserDefaults(suiteName: groupContainerIdentifier)?.string(forKey: memosHostKey) else {
            throw MemosError.notLogin
        }
        guard let hostURL = URL(string: host) else {
            throw MemosError.notLogin
        }
        
        let keychain = KeychainSwift()
        keychain.accessGroup = keychainAccessGroupName
        let accessToken = keychain.get(memosAccessTokenKey)
        
        let openId = UserDefaults(suiteName: groupContainerIdentifier)?.string(forKey: memosOpenIdKey)
        return try await Memos.create(host: hostURL, accessToken: accessToken, openId: openId)
    }
    
    private func extractCustomTags(from markdownText: String) -> [String] {
        let document = Document(parsing: markdownText)
        var tagVisitor = TagVisitor()
        document.accept(&tagVisitor)
        return tagVisitor.tags
    }
}

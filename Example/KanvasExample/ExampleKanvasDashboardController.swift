//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import UIKit
import Photos
import Kanvas
import Photos

private enum PhotoLibraryAccessError: Error {
    case notDetermined, restricted, denied, add(Error)
}

/// Protocol for the KanvasDashboardController to delegate events to
public protocol KanvasDashboardControllerDelegate: class {

    /// Called when the dismiss button is pressed in the camera
    func kanvasDashboardDismissRequest()

    /// Called when a user doesn't have a full account
    func kanvasDashboardNeedsAccount()

    /// Called to open the post compose form
    func kanvasDashboardOpenComposeRequest()

    /// Called to post
    func kanvasDashboardCreatePostRequest()

    func kanvasDashboardOpenPostingOptionsRequest()
    
    func kanvasDashboardConfirmPostingOptionsRequest()
}

/// Protocol for the KanvasDashboardController to get state from
/// This is an alternative to passing this state in through a constructor
public protocol KanvasDashboardStateDelegate: class {

    /// The EventBuffering for Kanvas Dashboard to use
    var kanvasDashboardAnalyticsProvider: KanvasAnalyticsProvider { get }

    var kanvasDashboardUnloadStrategy: KanvasDashboardController.UnloadStrategy { get }
}

/// KanvasDashboardController: the view controller for Kanvas on the Dashboard
public class KanvasDashboardController: UIViewController {

    private struct Constants {
        static let pixelWidthKey = "PixelWidth"
        static let pixelHeightKey = "PixelHeight"
    }

    private let settings: CameraSettings

    public weak var delegate: KanvasDashboardControllerDelegate?

    public weak var stateDelegate: KanvasDashboardStateDelegate?

    private var kanvasCleanupTimer: Timer?

    public enum UnloadStrategy {
        case never
        case always
        case delay(delay: TimeInterval)
    }

    init(settings: CameraSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadView() {
        let view = UIView(frame: .zero)
        self.view = view
        self.loadKanvasView()
    }

    override public var childForStatusBarStyle: UIViewController? {
        return kanvasViewController
    }

    public func logOpen(withTap openedWithTap: Bool) {
        if !openedWithTap {
            stateDelegate?.kanvasDashboardAnalyticsProvider.logOpenFromDashboard(openAction: .swipe)
        }
        else {
            stateDelegate?.kanvasDashboardAnalyticsProvider.logOpenFromDashboard(openAction: .tap)
        }
    }

    public func logDismiss(withTap dismissedWithTap: Bool) {
        if !dismissedWithTap {
            stateDelegate?.kanvasDashboardAnalyticsProvider.logDismissFromDashboard(dismissAction: .swipe)
        }
        else {
            stateDelegate?.kanvasDashboardAnalyticsProvider.logDismissFromDashboard(dismissAction: .tap)
        }
    }

    private var _kanvasViewControllerBackingProperty: CameraController?
    private var kanvasViewController: CameraController {
        if let kanvasViewControllerInstance = _kanvasViewControllerBackingProperty {
            return kanvasViewControllerInstance
        }
        let kanvasViewControllerInstance = createCameraController()
        _kanvasViewControllerBackingProperty = kanvasViewControllerInstance
        return kanvasViewControllerInstance
    }
}

extension KanvasDashboardController: CameraControllerDelegate {
    public func editorDismissed() {

    }


    public func openAppSettings(completion: ((Bool) -> ())?) {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url, options: [:], completionHandler: completion)
        }
    }

    public func tagButtonPressed() {
        // Only supported in Orangina
    }
    
    public func getQuickPostButton() -> UIView {
        // Only supported in Orangina
        return UIView()
    }
    
    public func getBlogSwitcher() -> UIView {
        // Only supported in Orangina
        return UIView()
    }
    
    public func editorDismissed(_ cameraController: CameraController) {
        // Only supported in Orangina
    }

    public func didCreateMedia(_ cameraController: CameraController, media: [Result<KanvasMedia?, Error>], exportAction: KanvasExportAction) {
        media.forEach { result in
            switch result {
            case .failure(let error):
                assertionFailure("Error creating Kanvas media: \(error)")
            case .success(let media):
                guard let media = media else {
                    assertionFailure("No error, but no media!?")
                    return
                }

                save(media: media, moveFile: false) { error in
                    DispatchQueue.main.async {
                        guard error == nil else {
                            print("Error saving media to the photo library")
                            return
                        }

                        switch exportAction {
                        case .previewConfirm:
                            assertionFailure("The Preview screen should never be shown from the Kanvas Dashboard")
                        case .confirm:
                            self.kanvasViewController.resetState()
                            self.delegate?.kanvasDashboardOpenComposeRequest()
                        case .post:
                            self.kanvasViewController.resetState()
                            self.delegate?.kanvasDashboardCreatePostRequest()
                        case .save:
                            break
                        case .postOptions:
                            self.delegate?.kanvasDashboardOpenPostingOptionsRequest()
                        case .confirmPostOptions:
                            self.delegate?.kanvasDashboardConfirmPostingOptionsRequest()
                        }
                    }
                }
            }
        }
    }

    public func dismissButtonPressed(_ cameraController: CameraController) {
        delegate?.kanvasDashboardDismissRequest()
    }

    public func didDismissWelcomeTooltip() {

    }

    public func cameraShouldShowWelcomeTooltip() -> Bool {
        return false
    }

    public func didDismissColorSelectorTooltip() {

    }

    public func editorShouldShowColorSelectorTooltip() -> Bool {
        return false
    }

    public func didEndStrokeSelectorAnimation() {

    }

    public func editorShouldShowStrokeSelectorAnimation() -> Bool {
        return false
    }
    
    public func didBeginDragInteraction() {
        
    }
    
    public func didEndDragInteraction() {
        
    }

    func save(media: KanvasMedia, moveFile: Bool = true, completion: @escaping (Error?) -> ()) {
        let completionMainThread: (Error?) -> () = { (error) in
            DispatchQueue.main.async {
                completion(error)
            }
        }
        PHPhotoLibrary.requestAuthorization { authorizationStatus in
            switch authorizationStatus {
#if swift(>=5.3)
            case .limited:
                fallthrough
#endif
            case .notDetermined, .restricted, .denied:
                completionMainThread(nil)
            case .authorized:
                switch media.type {
                case .image:
                    self.addToLibrary(url: media.output, resourceType: .photo, moveFile: moveFile, completion: completionMainThread)
                case .video:
                    self.addToLibrary(url: media.output, resourceType: .video, moveFile: moveFile, completion: completionMainThread)
                case .frames:
                    self.addToLibrary(url: media.output, resourceType: .photo, moveFile: moveFile, completion: completionMainThread)
                }
            @unknown default:
                completionMainThread(nil)
            }
        }
    }

    private func addToLibrary(url: URL, resourceType: PHAssetResourceType, moveFile: Bool, completion: @escaping (Error?) -> ()) {
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = moveFile
            req.addResource(with: resourceType, fileURL: url, options: options)
        }, completionHandler: { (success, error) in
            if let error = error {
                completion(PhotoLibraryAccessError.add(error))
            }
            else {
                completion(nil)
            }
        })
    }
}

private extension KanvasDashboardController {

    func createCameraController() -> CameraController {
        let kanvasAnalyticsProvider = stateDelegate?.kanvasDashboardAnalyticsProvider
        let stickerProvider = ExperimentalStickerProvider()
        let saveDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        let kanvasViewController = CameraController(settings: settings, mediaPicker: nil, stickerProvider: stickerProvider, analyticsProvider: kanvasAnalyticsProvider, quickBlogSelectorCoordinator: nil, tagCollection: nil, saveDirectory: saveDirectory)
        kanvasViewController.delegate = self
        return kanvasViewController
    }

    func loadKanvasView() {
        if !children.contains(kanvasViewController), let kanvasView = kanvasViewController.view {
            kanvasView.translatesAutoresizingMaskIntoConstraints = false
            addChild(kanvasViewController)
            view.addSubview(kanvasView)
            NSLayoutConstraint.activate([
                kanvasView.topAnchor.constraint(equalTo: view.topAnchor),
                kanvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                kanvasView.leftAnchor.constraint(equalTo: view.leftAnchor),
                kanvasView.rightAnchor.constraint(equalTo: view.rightAnchor),
            ])
        }
    }

    func unloadKanvasView() {
        if let kanvasViewController = _kanvasViewControllerBackingProperty, let kanvasView = kanvasViewController.view {
            kanvasView.removeFromSuperview()
            kanvasViewController.removeFromParent()
        }
    }

}

extension KanvasDashboardController {

    public func pageWillBecomeVisible(tapped: Bool) {
        if let kanvasCleanupTimer = kanvasCleanupTimer {
            kanvasCleanupTimer.invalidate()
            self.kanvasCleanupTimer = nil
        }
        else {
            loadKanvasView()
        }
    }

    public func pageDidBecomeHidden(tapped: Bool) {
        unloadKanvas()
        logDismiss(withTap: tapped)
    }

    private func unloadKanvas() {
        let unload = { [weak self] in
            if let kanvasViewControllerInstance = self?._kanvasViewControllerBackingProperty {
                kanvasViewControllerInstance.cleanup()
                self?.unloadKanvasView()
                self?._kanvasViewControllerBackingProperty = nil
            }
        }
        let unloadStrategy = stateDelegate?.kanvasDashboardUnloadStrategy ?? .always
        switch unloadStrategy {
        case .never:
            break
        case .always:
            unload()
        case .delay(let delay):
            let kanvasCleanupTimer = Timer(fire: .init(timeIntervalSinceNow: delay), interval: 0, repeats: false) { [weak self] timer in
                unload()
                self?.kanvasCleanupTimer?.invalidate()
                self?.kanvasCleanupTimer = nil
            }
            kanvasCleanupTimer.tolerance = 1.0
            RunLoop.current.add(kanvasCleanupTimer, forMode: .common)
            self.kanvasCleanupTimer = kanvasCleanupTimer
        }
    }

    public func pageGainedFocus(tapped: Bool) {
        logOpen(withTap: tapped)
    }
}

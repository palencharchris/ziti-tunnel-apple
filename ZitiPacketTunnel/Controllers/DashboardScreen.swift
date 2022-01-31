//
// Copyright 2019-2020 NetFoundry, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import Cocoa
import NetworkExtension
import CZiti
import CoreImage.CIFilterBuiltins
import CryptoKit

extension NSTextField {
    open override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}

extension String {
    func indexOf(string: String) -> String.Index? {
        return range(of: string, options: .literal, range: nil, locale: nil)?.lowerBound;
    }
}

class DashboardScreen: NSViewController, NSWindowDelegate, ZitiIdentityStoreDelegate, NSComboBoxDelegate, NSTextFieldDelegate {
    
    /**
     Ziti SDK Variables
     */
    let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Ziti"
    var tunnelMgr = TunnelMgr.shared;
    var zidMgr = ZidMgr();
    var identity = ZitiIdentity();
    var enrollingIds:[ZitiIdentity] = [];
    
    /**
     Cursor UI variables
     */
    private var pointingHand: NSCursor?
    private var arrow : NSCursor?
    
    /**
     Timer and values for updating speed labels
     */
    var timer = Timer();
    var timeLaunched:Int = 0;
    private var bytesDown:Float = 0.0;
    private var bytesUp:Float = 0.0;
    
    /**
     The Screens of the application controlled by the state
     */
    var state = "dashboard";
    var prevState = "dashboard";
    @IBOutlet var DashboardBox: NSBox!
    @IBOutlet var MenuBox: NSBox!
    @IBOutlet var AdvancedBox: NSBox!
    @IBOutlet var AboutBox: NSBox!
    @IBOutlet var LogLevelBox: NSBox!
    @IBOutlet var ConfigBox: NSBox!
    @IBOutlet var RecoveryBox: NSBox!
    @IBOutlet var AuthBox: NSBox!
    @IBOutlet var MFASetupBox: NSBox!
    @IBOutlet var ServiceBox: NSBox!
    @IBOutlet var DetailsBox: NSBox!
    @IBOutlet var MultiAuthBox: NSBox!
    var allViews:[NSBox] = [];
    
    
    
    
    
    
    
    
    @IBOutlet var ParentView: NSView!
    
    
    
    /**
     Main Dashboard Screen Functionality
     */
    @IBOutlet var AddButton: NSStackView!
    @IBOutlet var AddIdButton: NSTextField!
    @IBOutlet var ConnectButton: NSImageView!
    @IBOutlet var ConnectedButton: NSBox!
    @IBOutlet weak var MenuButton: NSStackView!
    @IBOutlet var Background: NSImageView!
    @IBOutlet var TimerLabel: NSTextField!
    @IBOutlet var UpSpeed: NSTextField!
    @IBOutlet var UpSpeedSize: NSTextField!
    @IBOutlet var DownSpeed: NSTextField!
    @IBOutlet var DownSpeedSize: NSTextField!
    @IBOutlet var SpeedArea: NSStackView!
    @IBOutlet var LogoArea: NSStackView!
    @IBOutlet var DoConnectGesture: NSClickGestureRecognizer!
    @IBOutlet var TimerSubLabel: NSTextField!
    @IBOutlet var AddIdGesture: NSClickGestureRecognizer!
    @IBOutlet var IdList: NSStackView!
    @IBOutlet var IdListScroll: NSScrollView!
    var isConnecting = false;
    var isConnected = false;
    var totalMfa = 0;
    var mfaIndex = 0;
    
    override func viewWillAppear() {
        self.view.window?.titleVisibility = .hidden;
        self.view.window?.titlebarAppearsTransparent = true;
        self.view.window?.styleMask.insert(.fullSizeContentView);
        self.view.window?.styleMask.remove(.closable);
        self.view.window?.styleMask.remove(.fullScreen);
        self.view.window?.styleMask.remove(.miniaturizable);
        self.view.window?.styleMask.remove(.resizable);
        self.view.window?.isOpaque = false;
        self.view.window?.hasShadow = false;
        self.view.window?.backgroundColor = NSColor.clear;
        self.view.window?.invalidateShadow();
        self.view.window?.isMovable = true;
        self.view.window?.isMovableByWindowBackground = true;
        self.view.window?.makeKeyAndOrderFront(self);
        /*
        self.view.shadow = NSShadow();
        self.view.layer?.shadowOpacity = 0.6;
        self.view.layer?.shadowColor = NSColor.black.cgColor;
        self.view.layer?.shadowOffset = NSMakeSize(0, 0);
        let rect = self.view.layer?.bounds.insetBy(dx: 30, dy: 30);
        self.view.layer?.shadowPath = CGPath(rect: rect!, transform: nil);
        self.view.layer?.shadowRadius = 12;
         */
        DashboardBox.wantsLayer = true;
        DashboardBox.layer?.borderWidth = 0;
        DashboardBox.layer?.cornerRadius = 12;
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        self.allViews =  [MenuBox,AdvancedBox,AboutBox,LogLevelBox,ConfigBox,RecoveryBox,AuthBox,MFASetupBox,MultiAuthBox,ServiceBox,DetailsBox];
        
        
        
        Logger.initShared(Logger.APP_TAG);
        zLog.info(Version.verboseStr);
        
        zidMgr.zidStore.delegate = self;
        // getMainWindow()?.delegate = self;
        
        SetLogIcon();
        SetupConfig();
        
        
        tunnelMgr.tsChangedCallbacks.append(self.tunnelStatusDidChange);
        tunnelMgr.loadFromPreferences(ViewController.providerBundleIdentifier);
        
        // Load previous identities
        if let err = zidMgr.loadZids() {
            zLog.error(err.errorDescription ?? "Error loading identities from store") // TODO: async alert dialog? just log it for now..
        }
        
        self.bytesDown = 0.0;
        self.bytesUp = 0.0;
        
        // SetupCursor();
        
        // Details Setup
        MFAToggle.layer?.backgroundColor = NSColor.red.cgColor;
        MFAToggle.layer?.masksToBounds = true;
        MFAToggle.layer?.cornerRadius = 10;
        
        self.HideAll();
        self.AuthCodeText.delegate = self;
        
        ProgressModal.isHidden = true;
        ProgressModal.alphaValue = 0;
        ProgressModal.shadow = .none;
        self.totalMfa = 0;
        self.mfaIndex = 0;
        
        // listen for Ziti IPC events
        NotificationCenter.default.addObserver(forName: .onZitiPollResponse, object: nil, queue: OperationQueue.main) { notification in
            guard let msg = notification.userInfo?["ipcMessage"] as? IpcMessage else {
                zLog.error("Unable to retrieve IPC message from event notification")
                return
            }
            
            let zidStr = msg.meta.zid;
            guard let zid = self.zidMgr.zids.first(where: { $0.id == zidStr }) else {
                return;
            }
            
            if (msg.meta.msgType == .MfaAuthQuery) {
                zid.mfaEnabled = true;
                zid.mfaVerified = false;
                self.totalMfa = self.totalMfa + 1;
                if (self.MultiAuthBox.isHidden) {
                    self.mfaIndex = self.mfaIndex + 1;
                    self.MultiAuthTitle.stringValue = zid.name;
                    self.MultiAuthBox.isHidden = false;
                    self.MultiAuthBox.alphaValue = 1;
                }
                self.MultiAuthDescription.stringValue = "\(self.mfaIndex) of \(self.totalMfa) identities require authentication prior to starting.";
            }
            
            self.zidMgr.zidStore.store(zid);
            self.UpdateList();
            
            //zid.mfaEnabled = msg.meta.m
        }
            //DispatchQueue.main.async {
            //    self.doMfaAuth(zid)
            //}
        
        //}
        getMainWindow()?.orderFrontRegardless();
        
    }
    
    func tunnelStatusDidChange(_ status:NEVPNStatus) {
        ConnectButton.isHidden = true;
        ConnectedButton.isHidden = false;
        SpeedArea.alphaValue = 0.2;
        TimerSubLabel.stringValue = "";
        DoConnectGesture.isEnabled = false;
        ConnectedButton.alphaValue = 0.2;
        self.ClearList();
        timer.invalidate();
        HideProgress();
        self.isConnected = false;
        
        zLog.info("Tunnel Status: \(status)");
        
        switch status {
        case .connecting:
            self.isConnecting = true;
            TimerLabel.stringValue = "Connecting...";
            ShowProgress("Please Wait", "Connecting...");
            break
        case .disconnecting:
            TimerLabel.stringValue = "Disconnecting...";
            ShowProgress("Please Wait", "Disconnecting...");
            break
        case .disconnected:
            self.totalMfa = 0;
            self.mfaIndex = 0;
            if (self.isConnecting) {
                self.isConnecting = false;
                for zid in zidMgr.zids {
                    zid.mfaVerified = false;
                    zidMgr.zidStore.store(zid);
                }
            }
            ConnectButton.isHidden = false;
            ConnectedButton.isHidden = true;
            DoConnectGesture.isEnabled = true;
            IdentityListHeight.constant = CGFloat(0);
            IdListHeight.constant = CGFloat(0);
            SetWindowHeight(size: CGFloat(400));
            self.HideAll();
            break
        case .invalid:
            TimerLabel.stringValue = "Invalid!";
            break
        case .reasserting:
            TimerLabel.stringValue = "Reasserting...";
            break
        case .connected:
            self.isConnected = true;
            AddButton.alphaValue = 1.0;
            AddIdButton.alphaValue = 1.0;
            TimerLabel.stringValue = "00:00.00";
            TimerSubLabel.stringValue = "STOP";
            ConnectButton.isHidden = true;
            ConnectedButton.isHidden = false;
            SpeedArea.alphaValue = 1.0;
            DoConnectGesture.isEnabled = true;
            ConnectedButton.alphaValue = 1.0;
            IdListScroll.isHidden = false;
            timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: (#selector(self.UpdateTimer)), userInfo: nil, repeats: true);
            self.UpdateList();
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                DispatchQueue.main.async {
                    if self.zidMgr.zids.count > 0 {
                        self.UpdateList();
                    }
                }
            }
            break
        @unknown default:
            TimerLabel.stringValue = "Unknown Tunnel State";
            zLog.warn("Unknown tunnel status");
            break
        }
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if (commandSelector == #selector(NSResponder.insertNewline(_:))) {
            // Do something against ENTER key
            print("enter");
            self.DoAuthorize()
            return true
        } else if (commandSelector == #selector(NSResponder.insertTab(_:))) {
            // Do something against TAB key
            return true
        } else if (commandSelector == #selector(NSResponder.cancelOperation(_:))) {
            // Do something against ESCAPE key
            return true
        }
        
        // return true if the action was handled; otherwise false
        return false
    }
    
    func onNewOrChangedId(_ zid: ZitiIdentity) {
        DispatchQueue.main.async {
            if let match = self.zidMgr.zids.first(where: { $0.id == zid.id }) {
                zLog.info("\(zid.name):\(zid.id) CHANGED")
                
                // TUN will disable if unable to start for zid
                match.edgeStatus = zid.edgeStatus
                match.enabled = zid.enabled
                
                // always take new service from tunneler...
                match.services = zid.services
                match.controllerVersion = zid.controllerVersion
                match.czid?.name = zid.name
            } else {
                // new one.  generally zids are only added by this app (so will be matched above).
                // But possible somebody could load one manually or some day via MDM or somesuch
                zLog.info("\(zid.name):\(zid.id) NEW")
                self.zidMgr.zids.append(zid)
            }
            self.UpdateList();
            
            
            if zid.isEnabled && zid.isEnrolled {
                let needsRestart = zid.services.filter {
                    if let status = $0.status, let needsRestart = status.needsRestart {
                        return needsRestart
                    }
                    return false
                }
                if needsRestart.count > 0 {
                    self.tunnelMgr.restartTunnel()
                }
            }
            
        }
    }
    
    func onRemovedId(_ idString: String) {
        self.UpdateList();
    }
    
    @IBAction func AddId(_ sender: Any) {
        self.AddIdentity();
    }
    
    @IBAction func AddIdentity(_ sender: Any) {
        self.AddIdentity();
    }
    
    @IBAction func ShowMenuAction(_ sender: Any) {
        self.showArea(state: "menu");
    }
    
    func getMainWindow() -> NSWindow? {
        for window in NSApplication.shared.windows {
            //if window.className == "NSWindow" && window.title == appName {
                return window
            //}
        }
        return nil
    }
    
    @objc func showPanel(_ sender: Any?) {
        if let window = getMainWindow() {
            window.deminiaturize(self)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.hide(self)
        return false
    }
    
    @objc func showInDock(_ sender: Any?) {
        if NSApp.activationPolicy() == .regular {
            NSApp.setActivationPolicy(.accessory)
            if getMainWindow()?.isVisible ?? false {
                DispatchQueue.main.async { self.showPanel(self) }
            }
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }
    
    @objc func UpdateTimer() {
        let formatter = DateComponentsFormatter();
        formatter.allowedUnits = [.hour, .minute, .second];
        formatter.unitsStyle = .positional;
        formatter.zeroFormattingBehavior = .pad;
        
        let speedFormetter = NumberFormatter();
        speedFormetter.numberStyle = .decimal;
        speedFormetter.maximumFractionDigits = 1;
        speedFormetter.minimumFractionDigits = 1;
        
        bytesDown = bytesUp*100;
        
        var upSize = "bps";
        var upSpeed = bytesUp;
        let gigs:Float = (1024*1024);
        print("\(bytesUp) \(gigs)");
        if (upSpeed>gigs) {
            upSize = "gps";
            upSpeed = upSpeed/gigs;
        } else {
            if (upSpeed>1024) {
                upSize = "mps";
                upSpeed = upSpeed/1024;
            }
        }
        UpSpeed.stringValue = speedFormetter.string(from: NSNumber(value: upSpeed)) ?? "0.0";
        UpSpeedSize.stringValue = upSize;
        
        var downSize = "bps";
        var downSpeed = bytesDown;
        if (downSpeed>gigs) {
            downSize = "gps";
            downSpeed = downSpeed/gigs;
        } else {
            if (downSpeed>1024) {
                downSize = "mps";
                downSpeed = downSpeed/1024;
            }
        }
        DownSpeed.stringValue = speedFormetter.string(from: NSNumber(value: downSpeed)) ?? "0.0";
        DownSpeedSize.stringValue = downSize;

        TimerLabel.stringValue = formatter.string(from: TimeInterval(timeLaunched))!;
        timeLaunched += 1;
    }
    
    func ClearList() {
        IdList.subviews.forEach { subview in
            subview.removeFromSuperviewWithoutNeedingDisplay();
        }
        // IdList.constant = 20;
        // IdentityList.isHidden = true;
    }
    
    @IBOutlet var IdListHeight: NSLayoutConstraint!
    @IBOutlet var IdentityListHeight: NSLayoutConstraint!
    
    func UpdateList() {
        IdListScroll.horizontalScrollElasticity = .none;
        IdListScroll.horizontalScroller = .none;
        ClearList();
        var index = 0;
        if (self.isConnected) {
            for identity in zidMgr.zids {
                let identityItem = IdentityListitem();
                identityItem.setIdentity(identity: identity, vc: self)
                identityItem.frame = CGRect(x: 0, y: CGFloat(index*62), width: 340, height: 60);
                IdList.addArrangedSubview(identityItem);
                index = index + 1;
            }
        }
        let minSize = CGFloat(400);
        var listHeight = CGFloat(index*62);
        var innerListHeight = CGFloat(index*62);
        var dashHeight = CGFloat(listHeight+minSize);
        
        guard let mainScreen = NSScreen.main else {
            assertionFailure();
            return;
        }
        let mainScreenFrame = mainScreen.frame;
        let mainScreenVisibleFrame = mainScreen.visibleFrame;
        let maxSize = CGFloat(mainScreenVisibleFrame.height * 0.75);
        if (dashHeight>maxSize) {
            listHeight = maxSize-minSize;
        }
        
        IdentityListHeight.constant = listHeight;
        IdListHeight.constant = innerListHeight;
        SetWindowHeight(size: CGFloat(400+listHeight));
    }
    
    @IBOutlet var DashHeight: NSLayoutConstraint!
    
    public func SetWindowHeight(size: CGFloat) {
        /*
        guard let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
            dialogAlert("No", "No Windows");
            return;
        }
        var windowFrame = window.frame;
        let oldWidth = windowFrame.size.width;
        windowFrame.size = NSMakeSize(oldWidth, CGFloat(150));
        window.setFrame(windowFrame, display: true);
         */
        //ParentView.setFrameSize(NSSize(width: 380, height: 399))
        DashHeight.constant = size;
    }
    
    func AddIdentity() {
        guard let window = view.window else { return }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["jwt"]
        panel.title = "Select Enrollment JWT file"
        
        panel.beginSheetModal(for: window) { (result) in
            //DispatchQueue(label: "JwtLoader").async {
                if result == NSApplication.ModalResponse.OK {
                    do {
                        try self.zidMgr.insertFromJWT(panel.urls[0], at: 0)
                        DispatchQueue.main.async {
                            for zid in self.zidMgr.zids {
                                if (!zid.enrolled!) {
                                    self.identity = zid;
                                    self.DoEnroll();
                                }
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            panel.orderOut(nil)
                            self.dialogAlert("Unable to add identity", error.localizedDescription)
                        }
                    }
                }
            //}
        }
    }
    
    
    
    
    
    
    
    
    
    
    
    
    /**
     Detail Screen Functionality
     */
    @IBOutlet var IdDetailCloseButton: NSImageView!
    @IBOutlet var IdName: NSTextField!
    @IBOutlet var IdNetwork: NSTextField!
    @IBOutlet var IdServiceCount: NSTextField!
    @IBOutlet var EnrollButton: NSTextField!
    @IBOutlet var ServiceList: NSScrollView!
    @IBOutlet var ForgotButton: NSTextField!
    @IBOutlet var MFAOn: NSImageView!
    @IBOutlet var MFAOff: NSImageView!
    @IBOutlet var MFARecovery: NSImageView!
    @IBOutlet var MFAToggle: NSSwitch!
    @IBOutlet var MFAArea: NSStackView!
    @IBOutlet var IsOfflineButton: NSImageView!
    @IBOutlet var IsOnlineButton: NSImageView!
    @IBOutlet var SortHow: NSPopUpButton!
    @IBOutlet var SortBy: NSPopUpButton!
    @IBOutlet var ServiceListHeight: NSLayoutConstraint!
    @IBOutlet var SearchFor: NSTextField!
    @IBOutlet var FilterArea: NSStackView!
    @IBOutlet var ForgotButtonArea: NSBox!
    
    public func ShowIdentity(zid:ZitiIdentity) {
        self.identity = zid;
        self.ShowDetails();
    }
    
    @IBAction func FilterChanged(_ sender: NSTextField) {
        SetupServices();
    }
    
    @IBAction func SortHow(_ sender: NSPopUpButton) {
        SetupServices();
    }
    
    
    @IBAction func SortBy(_ sender: NSPopUpButton) {
        SetupServices();
    }
    
    @IBAction func DoFilter(_ sender: NSClickGestureRecognizer) {
        SetupServices();
    }
    /**
     Show the details view and fill in the UI elements
     */
    func ShowDetails() {
        
        SortBy.selectItem(at: 0);
        SortHow?.selectItem(at: 0);
        SearchFor?.stringValue = "";
        
        let status = tunnelMgr.status;
        ForgotButtonArea.isHidden = false;
        ServiceList.isHidden = false;
        IdServiceCount.isHidden = false;
        MFAArea.isHidden = false;
        IsOnlineButton.isHidden = true;
        IsOfflineButton.isHidden = true;
        ForgotButtonArea.alphaValue = 1;
        FilterArea.alphaValue = 1;
        FilterArea.isHidden = false;
        if (self.identity.isEnrolled) {
            if (self.identity.isEnabled) {
                IsOnlineButton.isHidden = false;
            } else {
                IsOfflineButton.isHidden = false;
            }
        } else {
            ForgotButtonArea.alphaValue = 0;
            ForgotButtonArea.isHidden = true;
            ServiceList.isHidden = true;
            IdServiceCount.isHidden = true;
            MFAArea.isHidden = true;
            FilterArea.alphaValue = 0;
            FilterArea.isHidden = true;
        }
        IdName.stringValue = self.identity.name;
        IdNetwork.stringValue = self.identity.czid?.ztAPI ?? "no network";
        IdServiceCount.stringValue = "\(self.identity.services.count) Services";
        
        MFAOn.isHidden = true;
        MFAOff.isHidden = true;
        MFARecovery.isHidden = true;
        MFAToggle.state = .off;
        
        if (self.identity.isMfaEnabled) {
            MFAToggle.state = .on;
            if (self.identity.isMfaVerified) {
                MFAOn.isHidden = false;
                MFARecovery.isHidden = false;
            } else {
                MFAOff.isHidden = false;
            }
        }
        
        SetupServices();
        showArea(state: "details");
    }
    
    func comboBoxSelectionDidChange(_ notification: NSNotification) {
        print("It changed");
    }
    
    func SetupServices() {
        
        let sortBy = SortBy.selectedItem?.title;
        let sortHow = SortHow.selectedItem?.title;
        var filterFor = SearchFor.stringValue;
        filterFor = filterFor.trimmingCharacters(in: .whitespacesAndNewlines);
        
        let serviceListView = NSStackView(frame: NSRect(x: 0, y: 0, width: self.view.frame.width-50, height: 70));
        serviceListView.orientation = .vertical;
        serviceListView.spacing = 0;
        var baseHeight = 480;
        var index = 0;
        
        if (self.identity.isEnrolled) {
            let rowHeight = 40;
            var index = 0;
            var services = self.identity.services;
            
            if (sortBy=="Name") {
                if (sortHow=="Desc") {
                    services = services.sorted(by: { ($0.name ?? "") > ($1.name ?? "") })
                } else {
                    services = services.sorted(by: { ($0.name ?? "") < ($1.name ?? "") })
                }
            } else if (sortBy=="Address") {
                if (sortHow=="Desc") {
                    services = services.sorted(by: { ($0.addresses ?? "") > ($1.addresses ?? "") })
                } else {
                    services = services.sorted(by: { ($0.addresses ?? "") < ($1.addresses ?? "" ) })
                }
            } else if (sortBy=="Port") {
                if (sortHow=="Desc") {
                    services = services.sorted(by: { ($0.portRanges ?? "") > ($1.portRanges ?? "") })
                } else {
                    services = services.sorted(by: { ($0.portRanges ?? "") < ($1.portRanges ?? "") })
                }
            } else if (sortBy=="Protocol") {
                if (sortHow=="Desc") {
                    services = services.sorted(by: { ($0.protocols ?? "") > ($1.protocols ?? "") })
                } else {
                    services = services.sorted(by: { ($0.protocols ?? "") < ($1.protocols ?? "") })
                }
            }
            
            for service in services {
                var name = service.name ?? "";
                let valIndex = name.indexOf(string: filterFor)?.utf16Offset(in: name) ?? -1;
                if (filterFor == "" || valIndex > -1) {
                    let serviceItem = ServiceListItem();
                    serviceItem.SetService(service: service, vc: self);
                    serviceItem.frame = CGRect(x: 0, y: CGFloat(index*40), width: 300, height: 40);
                    serviceListView.addArrangedSubview(serviceItem);
                    index = index + 1;
                }
            }
            let innerListHeight = CGFloat(index*40);
            ServiceListHeight.constant = innerListHeight;
                
            
            let clipView = FlippedClipView();
            clipView.drawsBackground = false;
            ServiceList.horizontalScrollElasticity = .none;
            ServiceList.contentView = clipView
            clipView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
              clipView.leftAnchor.constraint(equalTo: ServiceList.leftAnchor),
              clipView.rightAnchor.constraint(equalTo: ServiceList.rightAnchor),
              clipView.topAnchor.constraint(equalTo: ServiceList.topAnchor),
              clipView.bottomAnchor.constraint(equalTo: ServiceList.bottomAnchor)
            ]);
            
            serviceListView.frame = CGRect(x: 0, y: 0, width: view.frame.size.width-50, height: CGFloat(((rowHeight*index))));
            ServiceList.documentView = serviceListView;
            EnrollButton.isHidden = true;
        } else {
            EnrollButton.isHidden = false;
        }
        
        if (index>3) {
            index = index-2;
            baseHeight = baseHeight+(50*index);
        }
        ServiceList.documentView = serviceListView;
        
    }
    
    /**
     Connect the client and restart the timer
     */
    @IBAction func Connect(_ sender: NSClickGestureRecognizer) {
        do {
            try tunnelMgr.startTunnel();
        } catch {
            dialogAlert("Tunnel Error", error.localizedDescription);
        }
    }
    
    /**
     Disconnct the client and stop the tunnel
     */
    @IBAction func Disconnect(_ sender: NSClickGestureRecognizer) {
        tunnelMgr.stopTunnel();
    }
    
    /**
     Forget the identity and update the main list closing the details view
     */
    @IBAction func Forget(_ sender: NSClickGestureRecognizer) {
        let text = "Deleting identity \(identity.name) (\(identity.id)) can't be undone"
        if dialogOKCancel(question: "Are you sure?", text: text) == true {
            let error = zidMgr.zidStore.remove(self.identity)
            guard error == nil else {
                dialogAlert("Unable to remove identity", error!.localizedDescription)
                return
            }
            _ = self.zidMgr.loadZids();
            self.tunnelMgr.restartTunnel();
            self.UpdateList();
            Close(sender);
        }
    }
    
    /**
     Show the identity details
     */
    @objc func GoToDetails(gesture : GoToDetailGesture) {
        let index = gesture.indexValue;
        self.identity = zidMgr.zids[index ?? 0];
        ShowDetails();
    }
    
    /**
     Toggle Inline Identity
     */
    @objc func ToggleInline(gesture : IdentityOperationGesture) {
        let index = gesture.indexValue;
        let identity = zidMgr.zids[index ?? 0];
        identity.enabled = gesture.isOn;
        _ = zidMgr.zidStore.store(identity);
        tunnelMgr.restartTunnel();
    }
    
    func DoEnroll() {
        EnrollButton.isHidden = true;
        enrollingIds.append(identity);
        
        guard let presentedItemURL = zidMgr.zidStore.presentedItemURL else {
            self.dialogAlert("Unable to enroll \(identity.name)", "Unable to access group container");
            return;
        }
        
        let url = presentedItemURL.appendingPathComponent("\(identity.id).jwt", isDirectory:false);
        let jwtFile = url.path;
        
        DispatchQueue.global().async {
            Ziti.enroll(jwtFile) { zidResp, zErr in
                DispatchQueue.main.async { [self] in
                    self.enrollingIds.removeAll { $0.id == identity.id }
                    guard zErr == nil, let zidResp = zidResp else {
                        _ = zidMgr.zidStore.store(self.identity);
                        self.dialogAlert("Unable to enroll \(identity.name)", zErr != nil ? zErr!.localizedDescription : "invalid response");
                        return;
                    }
                    
                    if self.identity.czid == nil {
                        identity.czid = CZiti.ZitiIdentity(id: zidResp.id, ztAPI: zidResp.ztAPI);
                    }
                    identity.czid?.ca = zidResp.ca;
                    if zidResp.name != nil {
                        identity.czid?.name = zidResp.name;
                    }
                    
                    identity.enabled = true;
                    identity.enrolled = true;
                    _ = zidMgr.zidStore.store(identity);
                    self.tunnelMgr.restartTunnel();
                }
            }
        }
        
    }
    
    /**
     Enroll the currnt identity
     */
    @IBAction func Enroll(_ sender: Any) {
        DoEnroll();
    }
    
    @IBAction func AuthClicked(_ sender: NSClickGestureRecognizer) {
        self.ShowAuthentication(identity: self.identity, type: "auth");
    }
    
    
    @IBAction func ShowRecoveryScreen(_ sender: NSClickGestureRecognizer) {
        self.ShowAuthentication(identity: self.identity, type: "recovery");
    }
    
    @IBAction func ToggleMFA(_ sender: NSClickGestureRecognizer) {
        if MFAToggle.state == .off {
            ShowMFASetup();
        } else {
            // only need to prompt for code if enrollment is verified (else can just send empty string)
            var code:String?
            if !self.identity.isMfaVerified {
                code = ""
            } else {
                code = dialogForString(question: "Authorize MFA", text: "Enter code to disable MFA for \(self.identity.name):\(self.identity.id)")
            }
            
            if let code = code { // will be nil if user hit Cancel when prompted...
                let msg = IpcMfaRemoveRequestMessage(self.identity.id, code)
                tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
                    DispatchQueue.main.async {
                        guard zErr == nil else {
                            self.dialogAlert("Error sending provider message to disable MFA", zErr!.localizedDescription)
                            self.toggleMfa(self.identity, .on)
                            return
                        }
                        guard let removeResp = respMsg as? IpcMfaStatusResponseMessage,
                              let status = removeResp.status else {
                            self.dialogAlert("IPC Error", "Unable to parse MFA removal response message")
                            self.toggleMfa(self.identity, .on)
                            return
                        }
                        
                        if status != Ziti.ZITI_OK {
                            self.dialogAlert("MFA Removal Error",
                                             "Status code: \(status)\nDescription: \(Ziti.zitiErrorString(status: status))")
                            self.toggleMfa(self.identity, .on)
                        } else {
                            zLog.info("MFA removed for \(self.identity.name):\(self.identity.id)")
                            self.identity.mfaEnabled = false;
                            self.identity.mfaVerified = false;
                            _ = self.zidMgr.zidStore.store(self.identity)
                            self.ShowDetails();
                        }
                    }
                }
            }
        }
        
        /*
         if (MFAToggle.state == .off) {
         // prompty to setup MF
         ShowMFA();
         
         // Send in the url and secret code to setup MFA
         
         } else {
         // prompt to turn off mfa if it is enabled
         ShowAuthentication();
         }
         */
    }
    
    func doMfaAuth(_ zid:ZitiIdentity) {
        if let code = self.dialogForString(question: "Authorize MFA\n\(zid.name):\(zid.id)", text: "Enter your authentication code") {
            
        }
    }
    
    
    
    
    
    
    
    
    
    
    
    /**
     Main Menu Screen Functionality
     */
    @IBOutlet var AdvancedButton: NSStackView!
    @IBOutlet var AboutButton: NSStackView!
    @IBOutlet var FeedbackButton: NSStackView!
    @IBOutlet var SupportButton: NSStackView!
    @IBOutlet var DetachButton: NSStackView!
    @IBOutlet var QuitButton: NSTextField!
    
    /**
     Close the app down
     */
    @IBAction func Exit(_ sender: NSClickGestureRecognizer) {
        exit(0);
    }
    
    @IBAction func ShowFeedback(_ sender: NSClickGestureRecognizer) {
        let logger = Logger.shared;
        let tunLog = (logger?.currLog(forTag: Logger.TUN_TAG)?.absoluteString)!;
        let appLog = (logger?.currLog(forTag: Logger.APP_TAG)?.absoluteString)!;
        let service = NSSharingService(named: NSSharingService.Name.composeEmail)!;
        
        service.recipients = ["help@openziti.org"];
        service.subject = "Ziti Support";
        
        let tunUrl = NSURL.fileURL(withPath: tunLog);
        let appUrl = NSURL.fileURL(withPath: appLog);
        let items: [Any] = ["see attachment", tunUrl, appUrl];
        
        service.perform(withItems: items);
    }
    
    @IBAction func ShowSupport(_ sender: NSClickGestureRecognizer) {
        let url = URL (string: "https://openziti.discourse.group")!;
        NSWorkspace.shared.open(url);
    }
    
    
    @IBAction func DetachApp(_ sender: NSClickGestureRecognizer) {
        
    }
    
    @IBAction func ShowAbout(_ sender: NSClickGestureRecognizer) {
        showArea(state: "about")
    }
    
    @IBAction func ShowAdvanced(_ sender: NSClickGestureRecognizer) {
        showArea(state: "advanced")
    }
    
    
    
    
    
    
    
    
    
    
    /**
     About Screen functionality
     */
    @IBOutlet var AboutBackButton: NSImageView!
    @IBOutlet var AboutCloseButton: NSImageView!
    @IBOutlet var PrivacyButton: NSStackView!
    @IBOutlet var TermsButton: NSStackView!
    @IBOutlet var VersionString: NSTextField!
    
    @IBAction func OpenPrivacy(_ sender: NSClickGestureRecognizer) {
        let url = URL (string: "https://netfoundry.io/privacy")!;
        NSWorkspace.shared.open(url);
    }
    
    @IBAction func OpenTerms(_ sender: NSClickGestureRecognizer) {
        let url = URL (string: "https://netfoundry.io/terms")!;
        NSWorkspace.shared.open(url);
    }
    
    @IBAction func DoAboutBack(_ sender: NSClickGestureRecognizer) {
        Close(sender);
    }
    
    
    
    
    
    
    
    
    /**
     Progress Modal
     */
    @IBOutlet var ProgressModal: NSBox!
    @IBOutlet var ProgressTitle: NSTextField!
    @IBOutlet var ProgressSubTitle: NSTextField!
    @IBOutlet var ProgressBar: NSProgressIndicator!
    
    func ShowProgress(_ title:String, _ subTitle:String) {
        ProgressTitle.stringValue = title;
        ProgressSubTitle.stringValue = subTitle;
        ProgressBar.startAnimation(nil);
        ProgressModal.isHidden = false;
        ProgressModal.alphaValue = 1;
    }
    
    func HideProgress() {
        ProgressBar.stopAnimation(nil);
        ProgressModal.isHidden = true;
        ProgressModal.alphaValue = 0;
    }
    
    
    
    
    
    
    
    /**
     Advanced Screen Functionality
     */
    @IBOutlet var AdvancedBackButton: NSImageView!
    @IBOutlet var AdvancedCloseButton: NSImageView!
    @IBOutlet var TunnelButton: NSStackView!
    @IBOutlet var ServiceLogButton: NSStackView!
    @IBOutlet var AppLogButton: NSStackView!
    @IBOutlet var LogLevelButton: NSStackView!
    
    /**
     Go to the config screen
     */
    @IBAction func GoToConfig(_ sender: NSClickGestureRecognizer) {
        SetupConfig();
        showArea(state: "config");
    }
    
    /**
     Open the service logs
     */
    @IBAction func GoToServiceLogs(_ sender: NSClickGestureRecognizer) {
        OpenConsole(Logger.TUN_TAG);
    }
    
    /**
     Open the app logs
     */
    @IBAction func GoToAppLogs(_ sender: NSClickGestureRecognizer) {
        OpenConsole(Logger.APP_TAG);
    }
    
    /**
     Open the log level screen
     */
    @IBAction func GoToLogLevel(_ sender: NSClickGestureRecognizer) {
        SetLogIcon();
        showArea(state: "loglevel");
    }
    
    /**
     Open the console to view the log
     */
    func OpenConsole(_ tag:String) {
        guard let logger = Logger.shared, let logFile = logger.currLog(forTag: tag)?.absoluteString else {
            zLog.error("Unable to find path to \(tag) log")
            return
        }
        
        let task = Process()
        task.arguments = ["-b", "com.apple.Console", logFile]
        task.launchPath = "/usr/bin/open"
        task.launch()
        task.waitUntilExit()
        let status = task.terminationStatus
        if (status != 0) {
            zLog.error("Unable to open \(logFile) in com.apple.Console, status=\(status)")
            let alert = NSAlert()
            alert.messageText = "Log Unavailable"
            alert.informativeText = "Unable to open \(logFile) in com.apple.Console"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    
    
    
    
    
    
    
    
    /**
     Tunnel Configuration Functionality
     */
    @IBOutlet var FatalImage: NSImageView!
    @IBOutlet var ErrorImage: NSImageView!
    @IBOutlet var WarnImage: NSImageView!
    @IBOutlet var InfoImage: NSImageView!
    @IBOutlet var DebugImage: NSImageView!
    @IBOutlet var VerboseImage: NSImageView!
    @IBOutlet var TraceImage: NSImageView!
    @IBOutlet var ErrorButton: NSStackView!
    @IBOutlet var FatalButton: NSStackView!
    @IBOutlet var WarnButton: NSStackView!
    @IBOutlet var InfoButton: NSStackView!
    @IBOutlet var DebugButton: NSStackView!
    @IBOutlet var VerboseButton: NSStackView!
    @IBOutlet var TraceButton: NSStackView!
    @IBOutlet var LogGoBackButton: NSImageView!
    @IBOutlet var LogCloseButton: NSImageView!
    
    /**
      Set the selected logging setting icon
     */
    func SetLogIcon() {
        TraceImage.isHidden = true;
        VerboseImage.isHidden = true;
        DebugImage.isHidden = true;
        InfoImage.isHidden = true;
        WarnImage.isHidden = true;
        ErrorImage.isHidden = true;
        FatalImage.isHidden = true;
        let thisLevel = ZitiLog.getLogLevel();
        if (thisLevel==ZitiLog.LogLevel.TRACE) {
            TraceImage.isHidden = false;
        } else if (thisLevel==ZitiLog.LogLevel.VERBOSE) {
            VerboseImage.isHidden = false;
        } else if (thisLevel==ZitiLog.LogLevel.DEBUG) {
            DebugImage.isHidden = false;
        } else if (thisLevel==ZitiLog.LogLevel.INFO) {
            InfoImage.isHidden = false;
        } else if (thisLevel==ZitiLog.LogLevel.WARN) {
            WarnImage.isHidden = false;
        } else if (thisLevel==ZitiLog.LogLevel.ERROR) {
            ErrorImage.isHidden = false;
        } else if (thisLevel==ZitiLog.LogLevel.WTF) {
            FatalImage.isHidden = false;
        }
    }
    
    /**
     Set the log level to fatal
     */
    @IBAction func SetFatal(_ sender: NSClickGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.WTF);
        SetLogIcon();
    }
    
    /**
     Set the log level to error
     */
    @IBAction func SetError(_ sender: NSClickGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.ERROR);
        SetLogIcon();
    }
    
    /**
     Set the log level to warning
     */
    @IBAction func SetWarn(_ sender: NSClickGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.WARN);
        SetLogIcon();
    }
    
    /**
     Set the log level to info
     */
    @IBAction func SetInfo(_ sender: NSClickGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.INFO);
        SetLogIcon();
    }
    
    /**
     Set the log level to debug
     */
    @IBAction func SetDebug(_ sender: NSClickGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.DEBUG);
        SetLogIcon();
    }
    
    /**
     Set the log level to verbose
     */
    @IBAction func SetVerbose(_ sender: NSClickGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.VERBOSE);
        SetLogIcon();
    }
    
    /**
     Set the log level to trace
     */
    @IBAction func SetTrace(_ sender: NSClickGestureRecognizer) {
        TunnelMgr.shared.updateLogLevel(ZitiLog.LogLevel.TRACE);
        SetLogIcon();
    }
    
    
    
    
    
    
    
    
    
    
    /**
     Configuration Screen
     */
    @IBOutlet var ConfigBackButton: NSImageView!
    @IBOutlet var ConfigCloseButton: NSImageView!
    @IBOutlet var IPAddress: NSTextField!
    @IBOutlet var SubNet: NSTextField!
    @IBOutlet var MTU: NSTextField!
    @IBOutlet var DNS: NSTextField!
    @IBOutlet var Matched: NSTextField!
    @IBOutlet var SaveButton: NSTextField!
    
    func SetupConfig() {
        self.IPAddress.stringValue = "0.0.0.0";
        self.SubNet.stringValue = "0.0.0.0";
        self.MTU.stringValue = "0";
        self.DNS.stringValue = "";
        self.Matched.stringValue = "";
        VersionString.stringValue = "v"+Version.str;
        
        guard
            let pp = tunnelMgr.tpm?.protocolConfiguration as? NETunnelProviderProtocol,
            let conf = pp.providerConfiguration
        else { return }
        
        if let ip = conf[ProviderConfig.IP_KEY] {
            self.IPAddress.stringValue = ip as! String
        }
        
        if let subnet = conf[ProviderConfig.SUBNET_KEY] {
            self.SubNet.stringValue = subnet as! String
        }
        
        if let mtu = conf[ProviderConfig.MTU_KEY] {
            self.MTU.stringValue = mtu as! String
        }
        
        if let dns = conf[ProviderConfig.DNS_KEY] {
            self.DNS.stringValue = dns as! String
        }
        
        if let matchDomains = conf[ProviderConfig.MATCH_DOMAINS_KEY] {
            self.Matched.stringValue = matchDomains as! String
        }
        self.IPAddress.becomeFirstResponder()
    }
    
    /**
     Save the configuration for the tunneler
     */
    @IBAction func SaveConfig(_ sender: Any) {
            var dict = ProviderConfigDict()
            dict[ProviderConfig.IP_KEY] = self.IPAddress.stringValue
            dict[ProviderConfig.SUBNET_KEY] = self.SubNet.stringValue
            dict[ProviderConfig.MTU_KEY] = self.MTU.stringValue
            dict[ProviderConfig.DNS_KEY] = self.DNS.stringValue
            dict[ProviderConfig.MATCH_DOMAINS_KEY] = self.Matched.stringValue
            dict[ProviderConfig.LOG_LEVEL] = String(ZitiLog.getLogLevel().rawValue)
            
            let conf:ProviderConfig = ProviderConfig()
            if let error = conf.parseDictionary(dict) {
                // alert and get outta here
                let alert = NSAlert()
                alert.messageText = "Configuration Error"
                alert.informativeText =  error.description
                alert.alertStyle = NSAlert.Style.critical
                alert.runModal()
                return
            }
            
        if let pc = self.tunnelMgr.tpm?.protocolConfiguration {
                (pc as! NETunnelProviderProtocol).providerConfiguration = conf.createDictionary()
                
                self.tunnelMgr.tpm?.saveToPreferences { error in
                    if let error = error {
                        NSAlert(error:error).runModal()
                    } else {
                        self.tunnelMgr.restartTunnel()
                        self.dismiss(self)
                    }
                }
            }
    }
    
    
    
    
    
    
    
    
    
    
    
    
    
    /**
     Recovery Code List functionality - I know this is awful but iterating the labels was erroring weirdly so I will clean it when I get codes
     */
    var codes = [String]();
    @IBOutlet var Code1: NSTextField!
    @IBOutlet var Code2: NSTextField!
    @IBOutlet var Code3: NSTextField!
    @IBOutlet var Code4: NSTextField!
    @IBOutlet var Code5: NSTextField!
    @IBOutlet var Code6: NSTextField!
    @IBOutlet var Code7: NSTextField!
    @IBOutlet var Code8: NSTextField!
    @IBOutlet var Code9: NSTextField!
    @IBOutlet var Code10: NSTextField!
    @IBOutlet var Code11: NSTextField!
    @IBOutlet var Code12: NSTextField!
    @IBOutlet var Code13: NSTextField!
    @IBOutlet var Code14: NSTextField!
    @IBOutlet var Code15: NSTextField!
    @IBOutlet var Code16: NSTextField!
    @IBOutlet var Code17: NSTextField!
    @IBOutlet var Code18: NSTextField!
    @IBOutlet var Code19: NSTextField!
    @IBOutlet var Code20: NSTextField!
    @IBOutlet var RecoveryCloseButton: NSImageView!
    @IBOutlet var RegenButton: NSTextField!
    @IBOutlet var SaveCodesButton: NSBox!
    
    func ShowRecovery() {
        Code1.stringValue = codes.count>0 ? codes[0] : "";
        Code2.stringValue = codes.count>1 ? codes[1] : "";
        Code3.stringValue = codes.count>2 ? codes[2] : "";
        Code4.stringValue = codes.count>3 ? codes[3] : "";
        Code5.stringValue = codes.count>4 ? codes[4] : "";
        Code6.stringValue = codes.count>5 ? codes[5] : "";
        Code7.stringValue = codes.count>6 ? codes[6] : "";
        Code8.stringValue = codes.count>7 ? codes[7] : "";
        Code9.stringValue = codes.count>8 ? codes[8] : "";
        Code10.stringValue = codes.count>9 ? codes[9] : "";
        Code11.stringValue = codes.count>10 ? codes[10] : "";
        Code12.stringValue = codes.count>11 ? codes[11] : "";
        Code13.stringValue = codes.count>12 ? codes[12] : "";
        Code14.stringValue = codes.count>13 ? codes[13] : "";
        Code15.stringValue = codes.count>14 ? codes[14] : "";
        Code16.stringValue = codes.count>15 ? codes[15] : "";
        Code17.stringValue = codes.count>16 ? codes[16] : "";
        Code18.stringValue = codes.count>17 ? codes[17] : "";
        Code19.stringValue = codes.count>18 ? codes[18] : "";
        Code20.stringValue = codes.count>19 ? codes[19] : "";
        showArea(state: "recovery");
    }
    
    @IBAction func RegenClicked(_ sender: NSClickGestureRecognizer) {
        self.ShowAuthentication(identity: self.identity, type: "regen")
    }
    
    @IBAction func SaveClicked(_ sender: NSClickGestureRecognizer) {
        let dialog = NSSavePanel();

        dialog.title = "Choose Directory To Save Codes";
        dialog.showsResizeIndicator = true;
        dialog.showsHiddenFiles = false;
        dialog.nameFieldStringValue = self.identity.name+"-Recovery.txt";

        if (dialog.runModal() ==  NSApplication.ModalResponse.OK) {
            let result = dialog.url
            if (result != nil) {
                let path: String = result!.path;
                var codeString = "";
                for code in self.codes {
                    codeString += code+"\n";
                }
                let filename = result!.standardizedFileURL
                do {
                    try codeString.write(to: filename, atomically: false, encoding: String.Encoding.utf8)
                } catch {
                    let errors = error;
                    print("Unexpected error: \(errors).")
                }
            }
        } else {
            return
        }
    }
    
    
    
    
    
    
    
    
    /**
     MFA Setup functionality
     */
    let context = CIContext();
    let filter = CIFilter.qrCodeGenerator();
    var mfaUrl:String = "";
    @IBOutlet var BarCode: NSImageView!
    @IBOutlet var SecretCode: NSTextField!
    @IBOutlet var SecretCodeArea: NSStackView!
    @IBOutlet var SecretToggle: NSTextField!
    @IBOutlet var LinkButton: NSTextField!
    @IBOutlet var MFACloseButton: NSImageView!
    @IBOutlet var SetupAuthCode: NSTextField!
    @IBOutlet var AuthSetupButton: NSBox!
    @IBOutlet var SetupAuthCodeText: NSTextField!
    @IBOutlet var MfaSubTitle: NSTextField!
    
    func ShowMFASetup() {
        MfaSubTitle.stringValue = self.identity.name;
        let msg = IpcMfaEnrollRequestMessage(self.identity.id)
        tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
            DispatchQueue.main.async {
                guard zErr == nil else {
                    self.dialogAlert("Error sending provider message to enable MFA", zErr!.localizedDescription)
                    self.toggleMfa(self.identity, .off)
                    return
                }
                guard let enrollResp = respMsg as? IpcMfaEnrollResponseMessage, let mfaEnrollment = enrollResp.mfaEnrollment else {
                    self.dialogAlert("IPC Error", "Unable to parse enrollment response message")
                    self.toggleMfa(self.identity, .off)
                    return
                }
                
                self.VerifyMfa(self.identity, mfaEnrollment);
            }
        }
    }
    
    func VerifyMfa(_ zId:ZitiIdentity, _ mfaEnrollment:ZitiMfaEnrollment) {
        guard let provisioningUrl = mfaEnrollment.provisioningUrl else {
            zLog.error("Invalid provisioning URL")
            return
        }
    
        self.mfaUrl = provisioningUrl;
        let parts = provisioningUrl.components(separatedBy: "/")
        let secret = parts.last;
        let secretParts = secret?.components(separatedBy: "=");
        SecretCode.stringValue = (secretParts?.last!)!;
        
        self.codes = mfaEnrollment.recoveryCodes!;
        
        let data = Data(provisioningUrl.utf8);
        filter.setValue(data, forKey: "inputMessage");
        let transform = CGAffineTransform(scaleX: 3, y: 3)
        if let qrCodeImage = filter.outputImage?.transformed(by: transform) {
            if let qrCodeCGImage = context.createCGImage(qrCodeImage, from: qrCodeImage.extent) {
                BarCode.image = redimensionaNSImage(image: NSImage(cgImage: qrCodeCGImage, size: .zero), size: NSSize(width: 200, height: 200));
            }
        }
        showArea(state: "mfa");
    }
    
    
    @IBAction func VerifySetupMfa(_ sender: NSClickGestureRecognizer) {
        // Need to call the setup MFA service and get a response
        let code = SetupAuthCodeText.stringValue;
        let msg = IpcMfaVerifyRequestMessage(self.identity.id, code)
        tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
            DispatchQueue.main.async {
                guard zErr == nil else {
                    self.dialogAlert("Error sending provider message to verify MFA", zErr!.localizedDescription)
                    self.toggleMfa(self.identity, .off)
                    return
                }
                guard let statusMsg = respMsg as? IpcMfaStatusResponseMessage, let status = statusMsg.status else {
                    self.dialogAlert("IPC Error", "Unable to parse verification response message")
                    self.toggleMfa(self.identity, .off)
                    return
                }
                guard status == Ziti.ZITI_OK else {
                    self.dialogAlert("MFA Verification Error", Ziti.zitiErrorString(status: status))
                    self.toggleMfa(self.identity, .off)
                    return
                }
                
                // Success!
                self.identity.mfaEnabled = true;
                self.identity.mfaVerified = true;
                self.identity.lastMfaAuth = Date();
                _ = self.zidMgr.zidStore.store(self.identity);
                _ = self.zidMgr.loadZids();
                self.UpdateList();
                self.ShowDetails();
                self.Close(sender);
                
                self.ShowRecovery();
            }
        }
    }
    
    func redimensionaNSImage(image: NSImage, size: NSSize) -> NSImage {

        var ratio: Float = 0.0
        let imageWidth = Float(image.size.width)
        let imageHeight = Float(image.size.height)
        let maxWidth = Float(size.width)
        let maxHeight = Float(size.height)

        if (imageWidth > imageHeight) {
            ratio = maxWidth / imageWidth;
        } else {
            ratio = maxHeight / imageHeight;
        }

        // Calculate new size based on the ratio
        let newWidth = imageWidth * ratio
        let newHeight = imageHeight * ratio

        let imageSo = CGImageSourceCreateWithData(image.tiffRepresentation! as CFData, nil)
        let options: [NSString: NSObject] = [
            kCGImageSourceThumbnailMaxPixelSize: max(imageWidth, imageHeight) * ratio as NSObject,
            kCGImageSourceCreateThumbnailFromImageAlways: true as NSObject
        ]
        let size1 = NSSize(width: Int(newWidth), height: Int(newHeight))
        let scaledImage = CGImageSourceCreateThumbnailAtIndex(imageSo!, 0, options as CFDictionary).flatMap {
            NSImage(cgImage: $0, size: size1)
        }

        return scaledImage!
    }
    
    @IBAction func LinkClicked(_ sender: NSClickGestureRecognizer) {
        let launchUrl = URL (string: self.mfaUrl)!;
        NSWorkspace.shared.open(launchUrl);
    }
    
    @IBAction func SecretClicked(_ sender: NSClickGestureRecognizer) {
        if (BarCode.isHidden) {
            BarCode.isHidden = false;
            SecretCodeArea.isHidden = true;
            SecretToggle.stringValue = "Show Secret";
        } else {
            BarCode.isHidden = true;
            SecretCodeArea.isHidden = false;
            SecretToggle.stringValue = "Show QR Code";
        }
    }
    
    
    
    
    
    /**
        Multi Authentication Screen
     */
    @IBOutlet var MultiAuthCode: NSTextField!
    @IBOutlet var MultiAuthButton: NSBox!
    @IBOutlet var MultiAuthDescription: NSTextField!
    @IBOutlet var SkipButton: NSTextField!
    @IBOutlet var MultiAuthTitle: NSTextField!
    
    @IBAction func SkipMfa(_ sender: NSClickGestureRecognizer) {
    }
    
    @IBAction func MultiAuthClick(_ sender: NSClickGestureRecognizer) {
    }
    
    @IBAction func CloseAuth(_ sender: Any) {
        // Skip all
        MultiAuthBox.isHidden = true;
    }
    
    
    
    
    
    /**
     Authentication Screen
     */
    @IBOutlet var AuthMFAButton: NSBox!
    @IBOutlet var AuthCode: NSTextField!
    @IBOutlet var AuthCloseButton: NSImageView!
    @IBOutlet var AuthCodeText: NSTextField!
    @IBOutlet var AuthSubTitle: NSTextField!;
    private var authType: String = "";
    
    func ShowAuthentication(identity:ZitiIdentity, type:String) {
        self.authType = type;
        self.identity = identity;
        AuthSubTitle.stringValue = "Enter code for "+identity.name;
        AuthCodeText.stringValue = "";
        showArea(state: "auth");
    }
    
    func DoAuthorize() {
        let code = AuthCodeText.stringValue;
        let authCode = code.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789.").inverted)
        AuthCodeText.stringValue = authCode;
        if (authCode.count == 6 || authCode.count == 8) {
            if (self.authType=="recovery") {
                let msg = IpcMfaGetRecoveryCodesRequestMessage(self.identity.id, authCode);
                self.tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
                    DispatchQueue.main.async {
                        guard zErr == nil else {
                            self.dialogAlert("Error sending provider message to auth MFA", zErr!.localizedDescription)
                            return
                        }
                        guard let codesMsg = respMsg as? IpcMfaRecoveryCodesResponseMessage,
                              let status = codesMsg.status else {
                            self.dialogAlert("IPC Error", "Unable to parse recovery codees response message")
                            return
                        }
                        guard status == Ziti.ZITI_OK else {
                            self.dialogAlert("MFA Auth Error", Ziti.zitiErrorString(status: status))
                            return
                        }
                        
                        self.codes = codesMsg.codes ?? [String]();
                        self.ShowRecovery();
                        
                    }
                }
            } else if (self.authType=="regen") {
                let msg = IpcMfaNewRecoveryCodesRequestMessage(self.identity.id, authCode);
                self.tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
                    DispatchQueue.main.async {
                        guard zErr == nil else {
                            self.dialogAlert("Error sending provider message to auth MFA", zErr!.localizedDescription)
                            return
                        }
                        guard let codesMsg = respMsg as? IpcMfaRecoveryCodesResponseMessage,
                              let status = codesMsg.status else {
                                  self.dialogAlert("IPC Error", "Unable to parse recovery codees response message");
                                  self.DoClose();
                                  self.DoClose();
                            return
                        }
                        guard status == Ziti.ZITI_OK else {
                            self.dialogAlert("MFA Auth Error", Ziti.zitiErrorString(status: status))
                            return
                        }
                            
                        self.codes = codesMsg.codes ?? [String]();
                        self.ShowRecovery();
                    }
                }
            } else {
                let msg = IpcMfaAuthQueryResponseMessage(self.identity.id, code);
                self.tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
                    DispatchQueue.main.async {
                        guard zErr == nil else {
                            self.dialogAlert("Error sending provider message to auth MFA", zErr!.localizedDescription)
                            return
                        }
                        guard let statusMsg = respMsg as? IpcMfaStatusResponseMessage, let status = statusMsg.status else {
                            self.dialogAlert("IPC Error", "Unable to parse auth response message")
                            return
                        }
                        guard status == Ziti.ZITI_OK else {
                            self.dialogAlert("MFA Auth Error", Ziti.zitiErrorString(status: status))
                            return
                        }
                        
                        self.identity.lastMfaAuth = Date();
                        self.identity.mfaEnabled = true;
                        self.identity.mfaVerified = true;
                        _ = self.zidMgr.zidStore.store(self.identity);
                        self.UpdateList();
                        
                        self.DoClose();
                    }
                }
            }
        } else {
            self.dialogAlert("Invalid", "Invalid Authorization Code")
        }
        
    }
    
    @IBAction func AuthorizeClicked(_ sender: NSClickGestureRecognizer) {
        DoAuthorize();
    }
    
    
    
    
    
    
    /**
     Service Details Window Functions
     */
    @IBOutlet var ServiceName: NSTextField!
    @IBOutlet var UrlValue: NSTextField!
    @IBOutlet var AddressValue: NSTextField!
    @IBOutlet var PortValue: NSTextField!
    @IBOutlet var ProtocolsValue: NSTextField!
    @IBOutlet var PostureInfo: NSTextField!
    @IBOutlet var CloseServiceButton: NSImageView!
    
    func ShowServiceDetails(service: ZitiService) {
        ServiceName.stringValue = service.name!;
        UrlValue.stringValue = "\(service.protocols!):\(service.addresses!):\(service.portRanges!)";
        AddressValue.stringValue = service.addresses!;
        PortValue.stringValue = service.portRanges!;
        ProtocolsValue.stringValue = service.protocols!;
        var checks = "";
        for checkSet in service.postureQuerySets ?? [] {
            for posture in checkSet.postureQueries ?? [] {
                checks += posture.queryType!;
                if (posture.isPassing!) {
                    checks += ": Passing";
                } else {
                    checks += ": Failing";
                }
            }
        }
        if (checks.count==0) {
            checks = "N/A";
        }
        PostureInfo.stringValue = checks;
        showArea(state: "service");
    }
    
    
    
    
    
    @IBOutlet var AlertMessage: NSTextField!;
    @IBOutlet var Blurb: NSBox!;
    var blurbTimer = Timer();
    
    @IBAction func CloseAlert(_ sender: Any) {
        CloseAlerts();
    }
    
    @objc func CloseAlerts() {
        Blurb.isHidden = true;
        Blurb.alphaValue = 0;
    }
    
    /**
     Pop a dialog message
     */
    func dialogAlert(_ msg:String, _ text:String? = nil) {
        /*
        let alert = NSAlert()
        alert.messageText = msg
        alert.informativeText =  text ?? ""
        alert.alertStyle = NSAlert.Style.critical
        alert.runModal()
         */
        AlertMessage.stringValue = text ?? "";
        AlertMessage.toolTip = msg+" "+text!;
        Blurb.isHidden = false;
        Blurb.alphaValue = 1;
        self.blurbTimer = Timer.scheduledTimer(timeInterval: 10, target: self, selector: (#selector(self.CloseAlerts)), userInfo: nil, repeats: true);
    }
    
    /**
     Pop a dialog message that requires a yes/no response
     */
    func dialogOKCancel(question: String, text: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    
    /**
     Hide and kill the clickability of all fields
     */
    func HideAll() {
        Blurb.isHidden = true;
        for view in allViews {
            view.isHidden = true;
            view.alphaValue = 1;
            view.shadow = .none;
        }
    }
    
    /**
     Return the current view area for the state we are in
     */
    func GetStateView() -> NSView {
        var view = MenuBox;
        
        switch self.state {
        case "details":
            view = DetailsBox;
        case "menu":
            view = MenuBox;
        case "advanced":
            view = AdvancedBox;
        case "about":
            view = AboutBox;
        case "config":
            view = ConfigBox;
        case "mfa":
            view = MFASetupBox;
        case "loglevel":
            view = LogLevelBox;
        case "auth":
            view = AuthBox;
        case "recovery":
            view = RecoveryBox;
        case "service":
            view = ServiceBox;
        default:
            view = MenuBox;
        }
        
        return view!;
    }
    
    /**
     Show the area defined by the state we are in
     */
    func showArea(state: String) {
        if (state=="recovery" && self.state=="mfa") {
            MFASetupBox.isHidden = true;
            MFASetupBox.alphaValue = 0.0;
        }
        self.state = state;
        
        
        let view = GetStateView();
        
        view.alphaValue = 1;
        view.isHidden = false;
        /*
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.5
            view.animator().alphaValue = 1
        } completionHandler: {
            view.alphaValue = 1;
            view.isHidden = false;
        }
         */
    }
    
    /**
     Do a close that requires rolling back the last two states
     */
    @IBAction func DoDoubleClose(_ sender: NSClickGestureRecognizer) {
        Close(sender);
        Close(sender);
    }
    
    /**
     Close three screens deep to dismiss all
     */
    @IBAction func DoTripleClose(_ sender: NSClickGestureRecognizer) {
        Close(sender);
        Close(sender);
        Close(sender);
    }
    
    /**
     Close four screens deep to dismiss all
     */
    @IBAction func DoQuadClose(_ sender: NSClickGestureRecognizer) {
        Close(sender);
        Close(sender);
        Close(sender);
        Close(sender);
    }
    
    /**
     Close the current view
     */
    @IBAction func Close(_ sender: NSClickGestureRecognizer) {
        self.DoClose();
    }
    
    func DoClose() {
        let view = GetStateView();
        if (state=="about"||state=="advanced") {
            state = "menu";
        } else if (state=="config"||state=="loglevel") {
            state = "advanced";
        } else if (state=="mfa"||state=="recovery"||state=="service") {
            state = "details";
        } else if (state=="auth") {
            if (DetailsBox.isHidden) {
                state = "dashboard";
            } else {
                state = "details";
            }
        } else {
            state = "dashboard";
        }
        
        view.alphaValue = 1;
        view.isHidden = true;
    }
    
    /**
        Setup the cursor for rollover state to fade the elements and show the pointer cursor
     */
    func SetupCursor() {
        let items = [AddButton, AddIdButton, ConnectButton, ConnectedButton, MenuButton,
                     IdDetailCloseButton, EnrollButton, ForgotButton, IsOfflineButton, IsOnlineButton, MFAToggle, MFAOff, MFARecovery, QuitButton, AdvancedButton, AboutButton,
                     FeedbackButton, SupportButton, DetachButton,
                     AboutBackButton, AboutCloseButton, PrivacyButton, TermsButton,
                     AdvancedBackButton, AdvancedCloseButton, TunnelButton, ServiceLogButton, AppLogButton, LogLevelButton,
                     LogCloseButton, ErrorButton, FatalButton, WarnButton, InfoButton, DebugButton, VerboseButton, TraceButton,
                     ConfigBackButton, ConfigCloseButton, SaveButton,
                     RecoveryCloseButton, RegenButton, SaveCodesButton,
                     SecretToggle, LinkButton, MFACloseButton, AuthSetupButton, AuthCloseButton, CloseServiceButton];
        
        pointingHand = NSCursor.pointingHand;
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: pointingHand!);
        }
        
        pointingHand!.setOnMouseEntered(true);
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: pointingHand!, userData: nil, assumeInside: true);
            item!.alphaValue = 0.4;
        }

        arrow = NSCursor.arrow
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: arrow!);
        }
        
        arrow!.setOnMouseExited(true)
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: arrow!, userData: nil, assumeInside: true);
            item!.alphaValue = 1.0;
        }
    }
    
    
    
    /**
     * MFA Functionality
     */
    
    
    func toggleMfa(_ zId:ZitiIdentity, _ flag:NSControl.StateValue) {
        self.MFAToggle.state = flag
        self.identity = zId;
        self.ShowDetails();
    }
    
    @IBAction func onMfaAuthNow(_ sender: Any) {
        let indx = representedObject as! Int
        let zid = zidMgr.zids[indx]
        doMfaAuth(zid)
    }
    
    @IBAction func onMfaCodes(_ sender: Any) {
        let indx = representedObject as! Int
        let zid = zidMgr.zids[indx]
        
        if let code = self.dialogForString(question: "Authorize MFA\n\(zid.name):\(zid.id)", text: "Enter your authentication code") {
            let msg = IpcMfaGetRecoveryCodesRequestMessage(zid.id, code)
            self.tunnelMgr.ipcClient.sendToAppex(msg) { respMsg, zErr in
                DispatchQueue.main.async {
                    guard zErr == nil else {
                        self.dialogAlert("Error sending provider message to auth MFA", zErr!.localizedDescription)
                        return
                    }
                    guard let codesMsg = respMsg as? IpcMfaRecoveryCodesResponseMessage,
                          let status = codesMsg.status else {
                        self.dialogAlert("IPC Error", "Unable to parse recovery codees response message")
                        return
                    }
                    guard status == Ziti.ZITI_OK else {
                        self.dialogAlert("MFA Auth Error", Ziti.zitiErrorString(status: status))
                        return
                    }
                    
                    // Success!
                    let codes = codesMsg.codes?.joined(separator: ", ")
                    self.dialogAlert("Recovery Codes", codes ?? "no recovery codes available")
                }
            }
        }
    }
    
    func dialogForString(question: String, text: String) -> String? {
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let txtView = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = txtView
        
        let response = alert.runModal()

        if (response == .alertFirstButtonReturn) {
            return txtView.stringValue
        }
        return nil // Cancel
    }
    
}


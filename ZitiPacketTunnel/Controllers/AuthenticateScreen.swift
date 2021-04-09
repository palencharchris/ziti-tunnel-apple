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

class AuthenticateScreen: NSViewController {
    
    @IBOutlet var AuthButton: NSBox!
    @IBOutlet var AuthCode: NSTextField!
    @IBOutlet var AuthTypeTitle: NSTextField!
    @IBOutlet var CloseButton: NSImageView!
    
    private var pointingHand: NSCursor?
    private var arrow : NSCursor?
    
    override func viewDidLoad() {
        SetupCursor();
    }
    
    @IBAction func Close(_ sender: NSClickGestureRecognizer) {
        dismiss(self);
    }
    
    @IBAction func AuthClicked(_ sender: NSClickGestureRecognizer) {
        var code = AuthCode.stringValue;
        // Do authentication
    }
    
    func SetupCursor() {
        let items = [AuthButton, CloseButton];
        
        pointingHand = NSCursor.pointingHand;
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: pointingHand!);
        }
        
        pointingHand!.setOnMouseEntered(true);
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: pointingHand!, userData: nil, assumeInside: true);
        }

        arrow = NSCursor.arrow
        for item in items {
            item!.addCursorRect(item!.bounds, cursor: arrow!);
        }
        
        arrow!.setOnMouseExited(true)
        for item in items {
            item!.addTrackingRect(item!.bounds, owner: arrow!, userData: nil, assumeInside: true);
        }
    }
    
}

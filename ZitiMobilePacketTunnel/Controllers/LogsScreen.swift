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
import UIKit


class LogsScreen: UIViewController, UIActivityItemSource {
    
    @IBAction func dismissVC(_ sender: Any) {
         dismiss(animated: true, completion: nil)
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return "";
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return "";
    }
    
    @IBAction func ShoPacketLog(_ sender: UITapGestureRecognizer) {
        let storyBoard : UIStoryboard = UIStoryboard(name: "MainUI", bundle:nil)
        let logDetails = storyBoard.instantiateViewController(withIdentifier: "LogDetails") as! LogDetailScreen
        logDetails.logType = "packet";
        self.present(logDetails, animated:true, completion:nil)
    }
    
    @IBAction func ShowAppLog(_ sender: UITapGestureRecognizer) {
        let storyBoard : UIStoryboard = UIStoryboard(name: "MainUI", bundle:nil)
        let logDetails = storyBoard.instantiateViewController(withIdentifier: "LogDetails") as! LogDetailScreen
        logDetails.logType = "application";
        self.present(logDetails, animated:true, completion:nil)
    }
    
    
}
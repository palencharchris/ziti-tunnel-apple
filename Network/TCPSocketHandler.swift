//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation
import tun2socks

class TCPSocketHandler: TSTCPSocketDelegate {
    var ziti:ZitiClientProtocol
    var regulator:TransferRegulator
    
    init(_ ziti:ZitiClientProtocol, _ regulator:TransferRegulator) {
        self.ziti = ziti
        self.regulator = regulator
        NSLog("TCPSocketHandler init")
    }
    
    deinit {
        NSLog("TCPSocketHandler deinit")
    }
    
    func localDidClose(_ socket: TSTCPSocket) {
        NSLog("TCPSocketHandler localDidClose. Closing Ziti")
        ziti.close()
    }
    
    func socketDidReset(_ socket: TSTCPSocket) {
        NSLog("TCPSocketHandler socketDidReset. Closing Ziti")
        ziti.close()
    }
    
    func socketDidAbort(_ socket: TSTCPSocket) {
        NSLog("TCPSocketHandler socketDidAbort. Closing Ziti")
        ziti.close()
    }
    
    func socketDidClose(_ socket: TSTCPSocket) {
        NSLog("TCPSocketHandler socketDidClose. Closing Ziti")
        ziti.close()
    }
    
    func didReadData(_ data: Data, from: TSTCPSocket) {
        _ = ziti.write(payload: data)
    }
    
    func didWriteData(_ length: Int, from: TSTCPSocket) {
        //print(">>>TCPSocketHandler didWriteData: \(length) bytes were written (back to TUN)")
        regulator.decPending(length)
    }
}

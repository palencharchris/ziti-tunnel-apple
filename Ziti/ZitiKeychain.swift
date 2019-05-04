//
// Copyright © 2019 NetFoundry Inc. All rights reserved.
//

import Foundation

class ZitiKeychain : NSObject {
    // kSecAttrAccessGroup not needed if sharing only a single keychain group?
    static let ZITI_KEYCHAIN_GROUP = "TEAMID.ZitiKeychain"
    let keySize = 2048
    
    #if os(macOS)
    private func getSecAccessRef() -> SecAccess? {
        var secAccess:SecAccess?
        
        var app:SecTrustedApplication?
        if SecTrustedApplicationCreateFromPath(nil, &app) != errSecSuccess { return nil }
        
        var ext:SecTrustedApplication?
        let extPath = Bundle.main.builtInPlugInsPath! + "/PacketTunnelProvider.appex"
        if SecTrustedApplicationCreateFromPath(extPath, &ext) != errSecSuccess { return nil }
        
        let trustedList = [app!, ext!] as NSArray?
        if SecAccessCreate("ZitiPacketTunnel" as CFString, trustedList, &secAccess) != errSecSuccess {
            return nil
        }
        return secAccess
    }
    #endif
    
    func createKeyPair(_ zid:ZitiIdentity) -> (privKey:SecKey?, pubKey:SecKey?, ZitiError?) {
        guard let atag = zid.id.data(using: .utf8) else {
            return (nil, nil, ZitiError("createPrivateKey: Unable to create application tag \(zid.id)"))
        }
        
        let privateKeyParams: [CFString: Any] = [
            kSecAttrIsPermanent: true,
            kSecAttrLabel: zid.id,
            kSecAttrApplicationTag: atag]
        var parameters: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: keySize,
            kSecReturnRef: kCFBooleanTrue as Any,
            kSecAttrLabel: zid.id, //macOs
            kSecAttrIsPermanent: true, // macOs
            kSecAttrApplicationTag: atag, //macOs
            /*kSecPublicKeyAttrs: publicKeyParams,*/
            kSecPrivateKeyAttrs: privateKeyParams]
        
#if os(macOS)
        if let secAccessRef = getSecAccessRef() {
            parameters[kSecAttrAccess] = secAccessRef
        } else {
            // Just log it. All should still work, but user will be prompted to allow access
            NSLog("createPrivateKey: Unable to to add secAttrAccess for \(zid.name)")
        }
#endif
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(parameters as CFDictionary, &error) else {
            return (nil, nil, ZitiError("createKeyPair: Unable to create private key for \(zid.id): \(error!.takeRetainedValue() as Error)"))
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return (nil, nil, ZitiError("createKeyPair: Unable to copy public key for \(zid.id)"))
        }
        return (privateKey, publicKey, nil)
    }
 
    func getKeyPair(_ zid:ZitiIdentity) -> (privKey:SecKey?, pubKey:SecKey?, ZitiError?) {
        guard let atag = zid.id.data(using: .utf8) else {
            return (nil, nil, ZitiError("geKeyPair: Unable to create application tag \(zid.id)"))
        }
        let parameters:[CFString:Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag: atag,
            kSecReturnRef: kCFBooleanTrue as Any]
        var ref: AnyObject?
        let status = SecItemCopyMatching(parameters as CFDictionary, &ref)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return (nil, nil, ZitiError("geKeyPair: Unable to get private key for \(zid.id): \(errStr)"))
        }
        let privKey = ref! as! SecKey
        guard let pubKey = SecKeyCopyPublicKey(privKey) else {
            return (nil, nil, ZitiError("geKeyPair: Unable to copy public key for \(zid.id)"))
        }
        return (privKey, pubKey, nil)
    }
    
    func keyPairExists(_ zid:ZitiIdentity) -> Bool {
        let (_, _, e) = getKeyPair(zid)
        return e == nil
    }
    
    func getKeyPEM(_ key:SecKey) -> String {
        var cfErr:Unmanaged<CFError>?
        guard let derKey = SecKeyCopyExternalRepresentation(key, &cfErr) else {
            NSLog("getKeyPEM: Unable to get external rep for key: \(cfErr!.takeRetainedValue() as Error)")
            return ""
        }
        
        return convertToPEM("RSA PRIVATE KEY", der: derKey as Data) // RSA PRIVATE KEY?
    }
    
    private func deleteKey(_ atag:Data, keyClass:Any) -> OSStatus {
        let deleteQuery:[CFString:Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyClass: keyClass,
            kSecAttrApplicationTag: atag]
        return SecItemDelete(deleteQuery as CFDictionary)
    }
    
    func deleteKeyPair(_ zid:ZitiIdentity) -> ZitiError? {
        guard let atag = zid.id.data(using: .utf8) else {
            return ZitiError("deleteKeyPair: Unable to create application tag \(zid.id)")
        }
        
        _ = deleteKey(atag, keyClass:kSecAttrKeyClassPublic)
        let status = deleteKey(atag, keyClass:kSecAttrKeyClassPrivate)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return ZitiError("Unable to delete key pair for \(zid.id): \(errStr)")
        }
        return nil
    }
    
    func getSecureIdentity(_ zid:ZitiIdentity) -> (SecIdentity?, ZitiError?) {
#if os(macOS)
        let params: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecReturnRef: kCFBooleanTrue as Any,
            kSecAttrLabel: zid.id]
        
        var cert: CFTypeRef?
        let certStatus = SecItemCopyMatching(params as CFDictionary, &cert)
        guard certStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(certStatus, nil) as String? ?? "\(certStatus)"
            return (nil, ZitiError("Unable to get identity certificate for \(zid.id): \(errStr)"))
        }
        let certificate = cert as! SecCertificate

        var identity: SecIdentity?
        let status = SecIdentityCreateWithCertificate(nil, certificate, &identity)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return (nil, ZitiError("Unable to get identity for \(zid.id): \(errStr)"))
        }
#else
        // pubKey is showing up instead of private key on iOS.  Deleting pubKey first fixes it...
        // https://forums.developer.apple.com/thread/69642
        if let atag = zid.id.data(using: .utf8) {
            _ = deleteKey(atag, keyClass:kSecAttrKeyClassPublic)
        }
        
        let params: [CFString:Any] = [
            kSecClass: kSecClassIdentity,
            kSecReturnRef: kCFBooleanTrue! as Any,
            kSecAttrLabel: zid.id,
            kSecMatchSubjectContains: zid.id]
        
        var ref: CFTypeRef?
        let status = SecItemCopyMatching(params as CFDictionary, &ref) // wildly slow. cache it?
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return (nil, ZitiError("Unable to get identity for \(zid.id): \(errStr)"))
        }
        let identity = ref as! SecIdentity
#endif
        return (identity, nil)
    }
    
#if os(macOS)
    // Will prompt for user creds to access keychain
    func addTrustForCertificate(_ certificate:SecCertificate) -> OSStatus {
        return SecTrustSettingsSetTrustSettings(certificate, SecTrustSettingsDomain.user, nil) // macOS only
    }
#endif
    
    func isRootCa(_ cert:SecCertificate) -> Bool {
        if let issuer = SecCertificateCopyNormalizedIssuerSequence(cert),
            let subject = SecCertificateCopyNormalizedSubjectSequence(cert) {
            if (issuer as NSData).isEqual(to: (subject as NSData) as Data) {
                return true
            }
        }
        return false
    }
    
    func certsMatch(_ cert1:SecCertificate, _ cert2:SecCertificate) -> Bool {
        let data1 = SecCertificateCopyData(cert1)
        let data2 = SecCertificateCopyData(cert2)
        if (data1 as NSData).isEqual(to: (data2 as NSData) as Data) {
            print("Matched cert: \(cert1):\n\(data1)")
            return true
        }
        return false
    }
    
    func evalTrustForCertificates(_ certificates:[SecCertificate], _ result: @escaping SecTrustCallback) -> OSStatus {
        var secTrust:SecTrust?
        let policy = SecPolicyCreateBasicX509()
        let stcStatus = SecTrustCreateWithCertificates(certificates as CFTypeRef, policy, &secTrust)
        if stcStatus != errSecSuccess { return stcStatus }
        guard secTrust != nil else { return errSecBadReq }
        let sceStatus = SecTrustEvaluateAsync(secTrust!, DispatchQueue(label: "evalTrustForCertificate"), result)
        return sceStatus
    }
    
    func storeCertificate(_ der:Data, label:String) -> (SecCertificate?, ZitiError?) {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            return (nil, ZitiError("Unable to create certificate from data for \(label)"))
        }
        let parameters: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: certificate,
            kSecAttrLabel: label]
        let status = SecItemAdd(parameters as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return (nil, ZitiError("Unable to store certificate for \(label): \(errStr)"))
        }
        return (certificate, nil)
    }
    
    func getCertificate(_ label:String) -> (Data?, ZitiError?) {
        let params: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecReturnRef: kCFBooleanTrue as Any,
            kSecAttrLabel: label]
        
        var cert: CFTypeRef?
        let status = SecItemCopyMatching(params as CFDictionary, &cert)
        guard status == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return (nil, ZitiError("Unable to get certificate for \(label): \(errStr)"))
        }
        guard let certData = SecCertificateCopyData(cert as! SecCertificate) as Data? else {
            return (nil, ZitiError("Unable to copy certificate data for \(label)"))
        }
        return (certData, nil)
    }
    
    func deleteCertificate(_ label:String) -> ZitiError? { 
        let params: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecReturnRef: kCFBooleanTrue as Any,
            kSecAttrLabel: label]
        
        var cert: CFTypeRef?
        let copyStatus = SecItemCopyMatching(params as CFDictionary, &cert)
        guard copyStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(copyStatus, nil) as String? ?? "\(copyStatus)"
            return ZitiError("Unable to find certificate for \(label): \(errStr)")
        }
        
        let delParams: [CFString:Any] = [
            kSecClass: kSecClassCertificate,
            kSecValueRef: cert!,
            kSecAttrLabel: label]
        let deleteStatus = SecItemDelete(delParams as CFDictionary)
        guard deleteStatus == errSecSuccess else {
            let errStr = SecCopyErrorMessageString(deleteStatus, nil) as String? ?? "\(deleteStatus)"
            return ZitiError("Unable to delete certificate for \(label): \(errStr)")
        }
        return nil
    }
    
    func convertToPEM(_ type:String, der:Data) -> String {
        guard let str = der.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0)).addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
            return ""
        }
        var pem = "-----BEGIN \(type)-----\n";
        for (i, ch) in str.enumerated() {
            pem.append(ch)
            if ((i != 0) && ((i+1) % 64 == 0)) {
                pem.append("\n")
            }
        }
        if (str.count % 64) != 0 {
            pem.append("\n")
        }
        return pem + "-----END \(type)-----\n"
    }
    
    func extractPEMs(_ caPool:String) -> [String] {
        var pems:[String] = []
        let start = "-----BEGIN CERTIFICATE-----"
        let end = "-----END CERTIFICATE-----"
        
        var pem:String? = nil
        caPool.split(separator: "\n").forEach { line in
            if pem != nil { pem = pem! + line + "\n" }
            if line == start { pem = String(line) + "\n" }
            if line == end && pem != nil {
                pems.append(pem!)
                pem = nil
            }
        }
        return pems
    }
    
    func PEMstoCerts(_ pems:[String]) -> [SecCertificate] {
        var certs:[SecCertificate] = []
        pems.forEach { pem in
            let der = convertToDER(pem)
            if let cert = SecCertificateCreateWithData(nil, der as CFData) {
                certs.append(cert)
            }
        }
        return certs
    }
    
    func convertToDER(_ pem:String) -> Data {
        var der = Data()
        pem.split(separator: "\n").forEach { line in
            if line.starts(with: "-----") == false {
                der.append(Data(base64Encoded: String(line)) ?? Data())
            }
        }
        return der
    }
}

import Foundation
import CryptoKit
import CommonCrypto
import zlib

enum DeviceCipher {
  static func rc442(_ input: Data, key: Data) -> Data {
    guard !key.isEmpty else { return Data() }
    var state = Array(0...255); let key = Array(key); var j = 0
    for i in 0..<256 { j = (j + state[i] + Int(key[i % key.count])) & 255; state.swapAt(i, j) }
    var i = 0; j = 0
    return Data(input.map { value in
      i = (i + 1) & 255; j = (j + state[i]) & 255; state.swapAt(i, j)
      return value ^ UInt8(state[(state[i] + state[j]) & 255]) ^ 42
    })
  }
  static func aes(_ input: Data, key: Data, encrypt: Bool) throws -> Data {
    guard key.count == 16 else { throw APIError(message: "Invalid verification key.") }
    var result = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
    var length = 0
    let capacity = result.count
    let status = key.withUnsafeBytes { keyBuffer in input.withUnsafeBytes { inputBuffer in
      CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), keyBuffer.baseAddress, key.count, nil, inputBuffer.baseAddress, input.count, &result, capacity, &length)
    } }
    guard status == kCCSuccess else { throw APIError(message: "Invalid device verification response.") }
    return Data(result.prefix(length))
  }
  static func gzip(_ input: Data) throws -> Data {
    var stream = z_stream()
    guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw APIError(message: "Could not encode device verification.") }
    defer { deflateEnd(&stream) }
    var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(input.count))))
    let capacity = output.count
    let status = input.withUnsafeBytes { source in output.withUnsafeMutableBytes { destination in
      stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: UInt8.self).baseAddress)
      stream.avail_in = uInt(input.count)
      stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress
      stream.avail_out = uInt(capacity)
      return deflate(&stream, Z_FINISH)
    } }
    guard status == Z_STREAM_END else { throw APIError(message: "Could not encode device verification.") }
    return Data(output.prefix(Int(stream.total_out)))
  }
}

extension TiebaTransport {
  func fetchZid() async throws -> String {
    let cuid = Self.md5(Data(deviceID.utf8)).uppercased() + "|0"
    let hash = Self.md5(Data(cuid.utf8))
    let timestamp = String(Int(Date().timeIntervalSince1970))
    let pathHash = Self.md5(Data(("200033" + timestamp + "ea737e4f435b53786043369d2e5ace4f").utf8))
    let input = try JSONSerialization.data(withJSONObject: ["module_section": [["zid": cuid]]])
    let compressed = try DeviceCipher.gzip(input)
    let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf8)
    let key = Data((0..<16).map { _ in alphabet.randomElement()! })
    let payload = try DeviceCipher.aes(compressed, key: key, encrypt: true) + Data(Insecure.MD5.hash(data: compressed))
    let encodedKey = DeviceCipher.rc442(key, key: Data(hash.utf8)).base64EncodedString()
    let url = URL(string: "https://sofire.baidu.com/c/11/z/100/200033/\(timestamp)/\(pathHash)?skey=\(urlEncode(encodedKey))")!
    let headers = ["Pragma": "no-cache", "Accept": "*/*", "Accept-Language": "en", "x-device-id": hash, "x-client-src": "src", "User-Agent": "x6/200033/12.35.1.0/4.4.1.3", "x-sdk-ver": "sofire/3.5.9.6", "x-plu-ver": "x6/4.4.1.3", "x-app-ver": "com.baidu.tieba/12.35.1.0", "x-api-ver": "33"]
    let data = try await request(url, method: "POST", data: payload, headers: headers, type: "application/x-www-form-urlencoded")
    let json = object(try JSONSerialization.jsonObject(with: data))
    guard let rawKey = Data(base64Encoded: string(json["skey"]), options: .ignoreUnknownCharacters), let encrypted = Data(base64Encoded: string(json["data"]), options: .ignoreUnknownCharacters), encrypted.count > 16 else { throw APIError(message: "Device verification returned an incompatible response.") }
    let responseKey = DeviceCipher.rc442(rawKey, key: Data(hash.utf8))
    let plaintext = try DeviceCipher.aes(encrypted.dropLast(16), key: responseKey, encrypt: false)
    let token = string(object(try JSONSerialization.jsonObject(with: plaintext))["token"])
    guard !token.isEmpty else { throw APIError(message: "Device verification returned no token.") }
    return token
  }
}

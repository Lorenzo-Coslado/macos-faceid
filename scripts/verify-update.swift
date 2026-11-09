import Foundation
import CryptoKit

// Public key and signature only. No signing secret is read or exported here.
let args = CommandLine.arguments
guard args.count == 4,
      let keyData = Data(base64Encoded: args[2]),
      let signature = Data(base64Encoded: args[3]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
      let archive = try? Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe),
      key.isValidSignature(signature, for: archive) else {
    fputs("Update signature does not match the public key embedded in Mugshot\n", stderr)
    exit(1)
}
print("Update signature matches the app's public key")

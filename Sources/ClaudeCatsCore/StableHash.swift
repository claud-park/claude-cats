public enum StableHash {
    /// FNV-1a 64bit. Swift 의 Hasher 는 프로세스마다 시드가 달라 배치가 튀므로 쓰지 않는다.
    public static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

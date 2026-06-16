enum DesktopPetMascotAsset {
    static func spriteName(for edgeAttachment: DesktopPetEdgeAttachment) -> String {
        switch edgeAttachment {
        case .none:
            return "DesktopPetSprite"
        case .left:
            return "DesktopPetPeekLeft"
        case .right:
            return "DesktopPetPeekRight"
        }
    }
}

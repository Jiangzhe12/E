func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

expect(
    DesktopPetMascotAsset.spriteName(for: .none) == "DesktopPetSprite",
    "default pet state should use the normal standing sprite"
)
expect(
    DesktopPetMascotAsset.spriteName(for: .left) == "DesktopPetPeekLeft",
    "left-clinging pet state should use the left peeking sprite"
)
expect(
    DesktopPetMascotAsset.spriteName(for: .right) == "DesktopPetPeekRight",
    "right-clinging pet state should use the right peeking sprite"
)

print("DesktopPetMascotAssetTests passed")

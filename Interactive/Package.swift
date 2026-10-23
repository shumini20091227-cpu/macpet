// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacPet", targets: ["MacPet"]),
        .library(name: "MacPetCore", targets: ["MacPetCore"])
    ],
    targets: [
        .target(
            name: "MacPetCore"
        ),
        .executableTarget(
            name: "MacPet",
            dependencies: ["MacPetCore"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "MacPetCoreTestRunner",
            dependencies: ["MacPetCore"]
        )
    ]
)

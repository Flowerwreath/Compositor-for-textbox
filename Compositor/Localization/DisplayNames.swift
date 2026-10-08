import Foundation

// Enums the screen shows by name. Their raw values stay English because project files store them; each case's Korean
// is a manual key in the catalog.
nonisolated extension AdjustmentKind: LocalizedDisplayName {}
nonisolated extension BackgroundQuality: LocalizedDisplayName {}
nonisolated extension BlurToolMode: LocalizedDisplayName {}
nonisolated extension BrushToolMode: LocalizedDisplayName {}
nonisolated extension CameraRawControls.Section: LocalizedDisplayName {}
nonisolated extension CameraRawCurvePage: LocalizedDisplayName {}
nonisolated extension CameraRawGlowStyle: LocalizedDisplayName {}
nonisolated extension CameraRawGradePage: LocalizedDisplayName {}
nonisolated extension CameraRawMixerPage: LocalizedDisplayName {}
nonisolated extension CameraRawMixerTab: LocalizedDisplayName {}
nonisolated extension CameraRawPointChannel: LocalizedDisplayName {}
nonisolated extension CameraRawProcessVersion: LocalizedDisplayName {}
nonisolated extension CameraRawProjection: LocalizedDisplayName {}
nonisolated extension CameraRawUprightMode: LocalizedDisplayName {}
nonisolated extension CameraRawVignetteStyle: LocalizedDisplayName {}
nonisolated extension CameraRawWhiteBalance: LocalizedDisplayName {}
nonisolated extension CanvasUnit: LocalizedDisplayName {}
nonisolated extension ColorRange: LocalizedDisplayName {}
nonisolated extension DitherColors: LocalizedDisplayName {}
nonisolated extension DitherPixelShape: LocalizedDisplayName {}
nonisolated extension DitherStyle: LocalizedDisplayName {}
nonisolated extension FilterKind: LocalizedDisplayName {}
nonisolated extension GradientShape: LocalizedDisplayName {}
nonisolated extension GradientStyle: LocalizedDisplayName {}
nonisolated extension GridAppearance.Preset: LocalizedDisplayName {}
nonisolated extension GridAppearance.Style: LocalizedDisplayName {}
nonisolated extension HueSampleMode: LocalizedDisplayName {}
nonisolated extension LassoKind: LocalizedDisplayName {}
nonisolated extension LayerBlendMode: LocalizedDisplayName {}
nonisolated extension LayerEffectKind: LocalizedDisplayName {}
nonisolated extension LayerSampling: LocalizedDisplayName {}
nonisolated extension LevelsAuto: LocalizedDisplayName {}
nonisolated extension LevelsChannel: LocalizedDisplayName {}
nonisolated extension LevelsSample: LocalizedDisplayName {}
nonisolated extension SelectionMode: LocalizedDisplayName {}
nonisolated extension ShapeKind: LocalizedDisplayName {}
nonisolated extension SpotHealingMode: LocalizedDisplayName {}
nonisolated extension TrimBasedOn: LocalizedDisplayName {}
nonisolated extension WandMode: LocalizedDisplayName {}

/// Catalog keys the compiler can't see, so a test can check each has Korean.
nonisolated enum ManualKeys {
    static let displayNameTypes: [any LocalizedDisplayName.Type] = [
        AdjustmentKind.self, BackgroundQuality.self, BlurToolMode.self, BrushToolMode.self,
        CameraRawControls.Section.self, CameraRawCurvePage.self, CameraRawGlowStyle.self, CameraRawGradePage.self,
        CameraRawMixerPage.self, CameraRawMixerTab.self, CameraRawPointChannel.self, CameraRawProcessVersion.self,
        CameraRawProjection.self, CameraRawUprightMode.self, CameraRawVignetteStyle.self,
        CameraRawWhiteBalance.self, CanvasUnit.self, ColorRange.self, DitherColors.self, DitherPixelShape.self,
        DitherStyle.self, FilterKind.self, GradientShape.self, GradientStyle.self, GridAppearance.Preset.self,
        GridAppearance.Style.self, HueSampleMode.self, LassoKind.self, LayerBlendMode.self, LayerEffectKind.self,
        LayerSampling.self, LevelsAuto.self, LevelsChannel.self, LevelsSample.self, SelectionMode.self,
        ShapeKind.self, SpotHealingMode.self, TrimBasedOn.self, WandMode.self,
    ]

    static var displayNames: [String] { displayNameTypes.flatMap { $0.displayKeys } }

    /// Keyboard Shortcuts keeps titles and groups in English as ids; the list shows them translated.
    static var shortcutNames: [String] {
        Array(Set(ShortcutDefinition.all.flatMap { [$0.title, $0.group] } + ["Menus", "Canvas & Layers", "Text Editing"])).sorted()
    }

    @MainActor static var canvasExtensionChoices: [String] { CanvasSizeSheet.extensionChoices }

    @MainActor static var cropRatioChoices: [String] { CropControls.ratioChoices }

    /// New Canvas presets whose names are words rather than product names.
    static let canvasPresetWords = ["Instagram Square", "Instagram Portrait", "Instagram Story", "YouTube Thumb"]

    /// Camera Raw's color mixer rows, named from a static list.
    static var cameraRawMixerNames: [String] { CameraRawMixerSettings.names }
}

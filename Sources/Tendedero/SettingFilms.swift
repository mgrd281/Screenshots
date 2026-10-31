import Foundation

extension SettingFilm {
    /// The settings that have a film, one for each row in Settings that
    /// turns on, chooses or does something, in the order Settings shows them.
    enum ID: String, CaseIterable {
        case takeScreenshotsWithSnapfly, alsoFromTheScreenshotApp, handlesScreenshots, hangsCopiedImages
        case smartSelection, stampsTime, whichScreenshots, sound, openStudioAfterRecording, sounds, openAtLogin
        case watchAnotherFolder, screenshotsFolder, lineStyle, whenThePointerRestsInTheMenuBar
        case whenSomethingNewHangs, overFullScreenApps, notDuringACall, lineSize, keepOnLine, countOnTheMenuBarIcon
        case takePhotosDownOnceSent, markPhotosSentBefore, keepAHistory, iconsUnderPhotos, websitesOpenIn
        case sendEachScreenshotTo, whereItGoes, keepItOnTheLine, showTheScreenshotButton, captureButtonClick
        case captureButtonIcon, captureButtonColor, showOrHideTheLine, sendTheNewestPhoto, searchScreenshots
        case takeAScreenshot, captureAWholePage, recordTheScreen, showItWhilePhotosHang, inChatApps
        case chatButtonPosition, chatButtonStyle, chatButtonIcon, chatButtonColor, chatApps, chatWebsites
        case hidePrivateDetails, detailNames, detailPatientNames, detailOtherPeople, detailAddresses
        case detailBirthDates, detailEmails, detailPhones, detailUsernames, detailFaces, detailOrganizations
        case detailBank, detailAmounts, detailHealth, detailIds, detailBarcodes, detailOrders, detailTracking
        case detailDates, detailLinks, detailIpAddresses, detailCodes, detailKeys, coverLook, keepTheLastFourDigits
        case strongestProtection, findMoreWithAppleIntelligence, findMoreWithModel, coverEverythingInAIChats
        case checkBeforeSending, plainFileNames, coverWhatLandsInAFolder, testOnASample, bookkeepingFolder
        case monthlyPack, shopLogo, numbersBesideTheSendButton, assistant, assistantModel, writeAReply, explainWith
        case orderDetails, keepScreenshotsInAWorkspaceFolder, workspaceFolder, newScreenshotsGoTo
        case orderAndVisibility, deleteTheWorkspace, syncWithYourIPhone, originalsToo, thisMac, connectWithACode
    }
}

/// Each setting's film. They follow one grammar: the scene as it is, the
/// pointer or a key doing what you would do, then what Snapfly does, held
/// still at the end for a moment.
enum SettingFilms {
    typealias Part = SettingFilm.Part
    typealias Box = SettingFilm.Box

    static func film(_ id: SettingFilm.ID) -> SettingFilm {
        switch id {
        case .takeScreenshotsWithSnapfly:
            // Snapfly takes the shot itself, from its shortcut or its round button: a drag
            // over the page and the shot flies straight onto the line, nothing set up.
            return SettingFilm("camera.aperture", FilmScene.line(cards: 1) + [
                .show(.window(.browser), Box(0.5, 0.64, 0.6, 0.56)),
                .show(.symbol("camera.viewfinder"), Box(0.92, 0.42, 0.09, 0.144)),
                .show(.key("⌃"), Box(0.41, 0.6, 0.07, 0.11), from: 0.2, to: 0.6),
                .show(.key("⌥"), Box(0.5, 0.6, 0.07, 0.11), from: 0.3, to: 0.6),
                Part(kind: .key("S"), keys: [
                    .init(0.4, Box(0.59, 0.6, 0.07, 0.11), opacity: 0),
                    .init(0.55, Box(0.59, 0.6, 0.07, 0.11)),
                    .init(0.6, Box(0.59, 0.6, 0.07, 0.11)),
                    .init(0.8, Box(0.59, 0.6, 0.07, 0.11), opacity: 0),
                ]),
                .move(.selection, Box(0.4, 0.62, 0.02, 0.03), Box(0.5, 0.66, 0.3, 0.3), start: 1.0, end: 1.4,
                      appear: 1.0, leave: 1.6),
                .move(.card(1), Box(0.5, 0.66, 0.3, 0.3), FilmScene.slot(1), start: 1.8, end: 2.4, appear: 1.7,
                      angles: (0, FilmScene.tilt(1))),
                .click(0.92, 0.42, at: 0.75),
                Part(kind: .cursor, keys: [
                    .init(0.45, Box(0.8, 0.86, 0.05, 0.08), opacity: 0),
                    .init(0.55, Box(0.8, 0.86, 0.05, 0.08)),
                    .init(0.7, Box(0.92, 0.43, 0.05, 0.08)),
                    .init(0.95, Box(0.35, 0.51, 0.05, 0.08)),
                    .init(1.4, Box(0.65, 0.81, 0.05, 0.08)),
                    .init(2.4, Box(0.65, 0.81, 0.05, 0.08)),
                    .init(2.6, Box(0.65, 0.81, 0.05, 0.08), opacity: 0),
                ]),
            ])
        case .alsoFromTheScreenshotApp:
            // macOS's own ⌘⇧4 and a drag: the shot drops into Pictures › Snapfly and
            // rises out of that folder onto the empty line.
            return SettingFilm("photo.badge.arrow.down", [FilmScene.desktop, FilmScene.menuBar,
                FilmScene.rope(),
                .show(.window(.browser), Box(0.6, 0.65, 0.56, 0.52)),
                .show(.folder, Box(0.15, 0.68, 0.15, 0.19)),
                .show(.key("⌘"), Box(0.41, 0.6, 0.07, 0.11), from: 0.2, to: 0.8),
                .show(.key("⇧"), Box(0.5, 0.6, 0.07, 0.11), from: 0.3, to: 0.8),
                .show(.key("4"), Box(0.59, 0.6, 0.07, 0.11), from: 0.4, to: 0.8),
                .move(.selection, Box(0.46, 0.56, 0.02, 0.03), Box(0.59, 0.68, 0.27, 0.25), start: 1.0, end: 1.4,
                      appear: 1.0, leave: 1.55),
                .show(.outline, Box(0.15, 0.68, 0.18, 0.24), from: 1.95, to: 2.3),
                Part(kind: .card(1), keys: [
                    .init(1.5, Box(0.59, 0.68, 0.27, 0.25), opacity: 0),
                    .init(1.6, Box(0.59, 0.68, 0.27, 0.25)),
                    .init(2.1, Box(0.15, 0.69, 0.07, 0.09)),
                    .init(2.3, Box(0.15, 0.69, 0.07, 0.09)),
                    .init(2.9, FilmScene.slot(1), angle: FilmScene.tilt(1)),
                ]),
                Part(kind: .cursor, keys: [
                    .init(0.9, Box(0.45, 0.55, 0.05, 0.08), opacity: 0),
                    .init(1.05, Box(0.45, 0.55, 0.05, 0.08)),
                    .init(1.4, Box(0.72, 0.8, 0.05, 0.08)),
                    .init(1.5, Box(0.72, 0.8, 0.05, 0.08)),
                    .init(1.7, Box(0.72, 0.8, 0.05, 0.08), opacity: 0),
                ]),
            ])
        case .handlesScreenshots:
            // ⌘⇧4 and a drag over a page: the screenshot flies straight up to the
            // line instead of landing on the Desktop.
            return SettingFilm("camera.on.rectangle", FilmScene.line(cards: 2) + [
                .show(.window(.browser), Box(0.5, 0.64, 0.6, 0.56)),
                .show(.key("⌘"), Box(0.41, 0.6, 0.07, 0.11), from: 0.2, to: 0.8),
                .show(.key("⇧"), Box(0.5, 0.6, 0.07, 0.11), from: 0.3, to: 0.8),
                .show(.key("4"), Box(0.59, 0.6, 0.07, 0.11), from: 0.4, to: 0.8),
                .move(.selection, Box(0.4, 0.62, 0.02, 0.03), Box(0.5, 0.66, 0.3, 0.3), start: 1.0, end: 1.4,
                      appear: 1.0, leave: 1.6),
                .move(.card(2), Box(0.5, 0.66, 0.3, 0.3), FilmScene.slot(2), start: 1.8, end: 2.4, appear: 1.7,
                      angles: (0, FilmScene.tilt(2))),
                Part(kind: .cursor, keys: [
                    .init(0.9, Box(0.35, 0.51, 0.05, 0.08), opacity: 0),
                    .init(1.05, Box(0.35, 0.51, 0.05, 0.08)),
                    .init(1.4, Box(0.65, 0.81, 0.05, 0.08)),
                    .init(2.4, Box(0.65, 0.81, 0.05, 0.08)),
                    .init(2.6, Box(0.65, 0.81, 0.05, 0.08), opacity: 0),
                ]),
            ])
        case .hangsCopiedImages:
            // A picture copied with ⌘C hangs on the line too.
            return SettingFilm("doc.on.clipboard", FilmScene.line(cards: 1) + [
                .show(.window(.browser), Box(0.5, 0.64, 0.6, 0.56)),
                .show(.card(1), Box(0.42, 0.66, 0.2, 0.24), from: 0.1),
                .show(.outline, Box(0.42, 0.66, 0.22, 0.27), from: 0.6, to: 1.3),
                .show(.key("⌘"), Box(0.62, 0.62, 0.07, 0.11), from: 0.7, to: 1.3),
                .show(.key("C"), Box(0.71, 0.62, 0.07, 0.11), from: 0.8, to: 1.3),
                .move(.card(1), Box(0.42, 0.66, 0.2, 0.24), FilmScene.slot(1), start: 1.5, end: 2.1, appear: 1.4,
                      angles: (0, FilmScene.tilt(1))),
            ])
        case .smartSelection:
            // The outline follows the pointer from one picture to the next, and a
            // click takes just that picture to the line.
            return SettingFilm("viewfinder", FilmScene.line(cards: 2) + [
                .show(.window(.browser), Box(0.5, 0.66, 0.72, 0.5)),
                .show(.card(0), Box(0.36, 0.68, 0.2, 0.24)),
                .show(.card(2), Box(0.64, 0.68, 0.2, 0.24)),
                .move(.outline, Box(0.36, 0.68, 0.22, 0.28), Box(0.64, 0.68, 0.22, 0.28), start: 1.15, end: 1.4,
                      appear: 0.7, leave: 2.0),
                .move(.card(2), Box(0.64, 0.68, 0.2, 0.24), FilmScene.slot(2), start: 2.0, end: 2.5, appear: 1.95,
                      angles: (0, FilmScene.tilt(2))),
                Part(kind: .cursor, keys: [
                    .init(0.1, Box(0.2, 0.95, 0.05, 0.08), opacity: 0),
                    .init(0.25, Box(0.2, 0.95, 0.05, 0.08)),
                    .init(0.7, Box(0.38, 0.72, 0.05, 0.08)),
                    .init(1.3, Box(0.66, 0.72, 0.05, 0.08)),
                    .init(2.0, Box(0.66, 0.72, 0.05, 0.08)),
                    .init(2.2, Box(0.66, 0.72, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.66, 0.72, at: 1.9),
            ])
        case .stampsTime:
            // While the time is fetched, the stamp with the date and time comes
            // in and lands on the top of the newest screenshot.
            return SettingFilm("clock.badge.checkmark", FilmScene.line(cards: 2, of: 2) + [
                .show(.symbol("clock"), Box(0.5, 0.62, 0.1, 0.16), from: 0.3, to: 0.9),
                .move(.stamp, Box(0.5, 0.75, 0.16, 0.09), Box(0.76, FilmScene.slot(1, of: 2).y - 0.05, 0.1, 0.05),
                      start: 1.3, end: 2.0, appear: 0.9),
            ])
        case .whichScreenshots:
            // With the whole screen chosen, only the whole-screen shot is stamped; the
            // picker's second choice stamps every shot, so the area shot gets one too.
            return SettingFilm("display", [FilmScene.desktop, FilmScene.menuBar, FilmScene.rope(),
                .show(.window(.browser), Box(0.5, 0.6, 0.6, 0.38)),
                .move(.outline, Box(0.44, 0.89, 0.115, 0.184), Box(0.56, 0.89, 0.115, 0.184), start: 2.5, end: 2.8,
                      appear: 0),
                .show(.symbol("display"), Box(0.44, 0.89, 0.09, 0.144)),
                .show(.symbol("rectangle.dashed"), Box(0.56, 0.89, 0.09, 0.144)),
                .move(.card(0), Box(0.5, 0.55, 0.8, 0.8), FilmScene.slot(0, of: 2), start: 0.5, end: 0.9, appear: 0.4,
                      angles: (0, FilmScene.tilt(0))),
                .move(.stamp, Box(0.24, 0.15, 0.1, 0.05), Box(0.24, 0.23, 0.1, 0.05), start: 0.95, end: 1.15,
                      appear: 0.9),
                .move(.selection, Box(0.53, 0.55, 0.02, 0.03), Box(0.6, 0.62, 0.2, 0.18), start: 1.25, end: 1.65,
                      appear: 1.2, leave: 1.75),
                .move(.card(1), Box(0.6, 0.62, 0.2, 0.18), FilmScene.slot(1, of: 2), start: 1.85, end: 2.35,
                      appear: 1.75, angles: (0, FilmScene.tilt(1))),
                .move(.stamp, Box(0.76, 0.15, 0.1, 0.05), Box(0.76, 0.23, 0.1, 0.05), start: 2.95, end: 3.15,
                      appear: 2.9),
            ])
        case .sound:
            // While recording, the Mac's sound and the microphone flow into the stop
            // button; a click stops it and the video hangs with one sound track.
            return SettingFilm("waveform.and.mic", FilmScene.line(cards: 0) + [
                .show(.symbol("stop.fill"), Box(0.5, 0.9, 0.09, 0.144), to: 1.5),
                Part(kind: .symbol("hifispeaker.fill"), keys: [
                    .init(0.2, Box(0.2, 0.6, 0.11, 0.176), opacity: 0),
                    .init(0.4, Box(0.2, 0.6, 0.11, 0.176)),
                    .init(0.55, Box(0.2, 0.6, 0.11, 0.176)),
                    .init(0.95, Box(0.4, 0.9, 0.11, 0.176)),
                    .init(1.05, Box(0.5, 0.9, 0.09, 0.144)),
                    .init(1.25, Box(0.5, 0.9, 0.09, 0.144), opacity: 0),
                ]),
                Part(kind: .symbol("mic.fill"), keys: [
                    .init(0.35, Box(0.8, 0.6, 0.11, 0.176), opacity: 0),
                    .init(0.55, Box(0.8, 0.6, 0.11, 0.176)),
                    .init(0.7, Box(0.8, 0.6, 0.11, 0.176)),
                    .init(1.1, Box(0.6, 0.9, 0.11, 0.176)),
                    .init(1.2, Box(0.5, 0.9, 0.09, 0.144)),
                    .init(1.4, Box(0.5, 0.9, 0.09, 0.144), opacity: 0),
                ]),
                .move(.card(1), Box(0.5, 0.84, 0.14, 0.17), FilmScene.slot(1), start: 1.7, end: 2.2, appear: 1.6,
                      angles: (0, FilmScene.tilt(1))),
                .move(.symbol("play.fill"), Box(0.5, 0.84, 0.08, 0.128), Box(0.5, 0.295, 0.08, 0.128), start: 1.7,
                      end: 2.2, appear: 1.6),
                .show(.symbol("waveform"), Box(0.5, 0.47, 0.09, 0.144), from: 2.4),
                .click(0.5, 0.9, at: 1.45),
                Part(kind: .cursor, keys: [
                    .init(1.0, Box(0.76, 0.84, 0.05, 0.08), opacity: 0),
                    .init(1.15, Box(0.76, 0.84, 0.05, 0.08)),
                    .init(1.4, Box(0.5, 0.91, 0.05, 0.08)),
                    .init(1.55, Box(0.5, 0.91, 0.05, 0.08)),
                    .init(1.75, Box(0.5, 0.91, 0.05, 0.08), opacity: 0),
                ]),
            ])
        case .openStudioAfterRecording:
            // A click on stop hangs the recording, and Studio opens from it: a click
            // on the picture rings, and the picture zooms in where it was.
            return SettingFilm("wand.and.stars", FilmScene.line(cards: 0) + [
                .show(.symbol("stop.fill"), Box(0.5, 0.9, 0.09, 0.144), to: 0.25),
                .click(0.5, 0.9, at: 0.15),
                .move(.card(1), Box(0.5, 0.84, 0.14, 0.17), FilmScene.slot(1), start: 0.4, end: 0.9, appear: 0.3,
                      leave: 1.05, angles: (0, FilmScene.tilt(1))),
                .move(.symbol("play.fill"), Box(0.5, 0.84, 0.08, 0.128), Box(0.5, 0.295, 0.08, 0.128), start: 0.4,
                      end: 0.9, appear: 0.3, leave: 1.05),
                .move(.window(.document), FilmScene.slot(1), Box(0.5, 0.665, 0.74, 0.6), start: 1.15, end: 1.6,
                      appear: 1.05),
                .move(.card(1), Box(0.5, 0.62, 0.5, 0.29), Box(0.528, 0.62, 0.675, 0.39), start: 2.05, end: 2.55,
                      appear: 1.5),
                .show(.line(.filmstrip), Box(0.5, 0.885, 0.62, 0.07), from: 1.55),
                .click(0.42, 0.62, at: 1.9),
                Part(kind: .cursor, keys: [
                    .init(0, Box(0.5, 0.91, 0.05, 0.08), opacity: 0),
                    .init(0.1, Box(0.5, 0.91, 0.05, 0.08)),
                    .init(0.25, Box(0.5, 0.91, 0.05, 0.08)),
                    .init(0.45, Box(0.5, 0.91, 0.05, 0.08), opacity: 0),
                    .init(1.45, Box(0.62, 0.76, 0.05, 0.08), opacity: 0),
                    .init(1.6, Box(0.62, 0.76, 0.05, 0.08)),
                    .init(1.85, Box(0.42, 0.63, 0.05, 0.08)),
                    .init(2.0, Box(0.42, 0.63, 0.05, 0.08)),
                    .init(2.2, Box(0.42, 0.63, 0.05, 0.08), opacity: 0),
                ]),
            ])
        case .sounds:
            // A tink as a new screenshot clips on; a photo dragged off the line into
            // the Trash makes the Trash's sound.
            return SettingFilm("speaker.wave.2.fill", [FilmScene.desktop, FilmScene.menuBar, FilmScene.rope(),
                FilmScene.dock,
                .show(.symbol("trash.fill"), Box(0.87, 0.88, 0.09, 0.144)),
                .move(.card(0), FilmScene.slot(0), Box(0.87, 0.88, 0.05, 0.06), start: 1.55, end: 2.05, appear: 0,
                      leave: 2.1, angles: (FilmScene.tilt(0), 0)),
                .show(.card(1), FilmScene.slot(1), angle: FilmScene.tilt(1)),
                .move(.card(2), Box(0.5, 0.62, 0.2, 0.24), FilmScene.slot(2), start: 0.25, end: 0.75, appear: 0.15,
                      angles: (0, FilmScene.tilt(2))),
                .show(.symbol("speaker.wave.2.fill"), Box(0.76, 0.48, 0.09, 0.144), from: 0.75, to: 1.3),
                Part(kind: .cursor, keys: [
                    .init(1.05, Box(0.5, 0.62, 0.05, 0.08), opacity: 0),
                    .init(1.2, Box(0.5, 0.62, 0.05, 0.08)),
                    .init(1.55, Box(0.24, 0.3, 0.05, 0.08)),
                    .init(2.05, Box(0.87, 0.88, 0.05, 0.08)),
                    .init(2.15, Box(0.87, 0.88, 0.05, 0.08)),
                    .init(2.35, Box(0.87, 0.88, 0.05, 0.08), opacity: 0),
                ]),
                .show(.symbol("speaker.wave.2.fill"), Box(0.87, 0.69, 0.09, 0.144), from: 2.05),
            ])
        case .openAtLogin:
            // From the login screen to the desktop: Snapfly is already in the
            // menu bar, ready.
            return SettingFilm("power", [FilmScene.desktop,
                .move(.menuBar, Box(0.5, -0.04, 1, 0.08), Box(0.5, 0.04, 1, 0.08), start: 1.25, end: 1.65, appear: 1.2),
                .show(.cover, Box(0.5, 0.5, 1.02, 1.02), to: 1.0),
                .show(.symbol("person.crop.circle"), Box(0.5, 0.42, 0.16, 0.256), to: 1.0),
                .show(.key("↩"), Box(0.5, 0.7, 0.08, 0.128), from: 0.35, to: 1.0),
                .show(.outline, Box(0.925, 0.04, 0.1, 0.075), from: 1.9),
            ])
        case .watchAnotherFolder:
            // A picture saved from a page into a watched folder rises out of it onto
            // the line.
            return SettingFilm("binoculars.fill", FilmScene.line(cards: 2) + [
                .show(.folder, Box(0.2, 0.68, 0.16, 0.2), from: 0.1),
                .show(.symbol("eye.fill"), Box(0.27, 0.6, 0.09, 0.144), from: 0.45),
                .show(.window(.browser), Box(0.65, 0.66, 0.5, 0.5)),
                .move(.card(2), Box(0.62, 0.69, 0.18, 0.2), Box(0.2, 0.69, 0.07, 0.09), start: 1.1, end: 1.6, appear: 0,
                      leave: 1.65),
                Part(kind: .cursor, keys: [
                    .init(0.6, Box(0.82, 0.86, 0.05, 0.08), opacity: 0),
                    .init(0.75, Box(0.82, 0.86, 0.05, 0.08)),
                    .init(1.1, Box(0.62, 0.69, 0.05, 0.08)),
                    .init(1.6, Box(0.2, 0.69, 0.05, 0.08)),
                    .init(1.7, Box(0.2, 0.69, 0.05, 0.08)),
                    .init(1.9, Box(0.2, 0.69, 0.05, 0.08), opacity: 0),
                ]),
                .move(.card(2), Box(0.2, 0.66, 0.07, 0.09), FilmScene.slot(2), start: 1.9, end: 2.5, appear: 1.8,
                      angles: (0, FilmScene.tilt(2))),
            ])
        case .screenshotsFolder:
            // Pictures, then the Snapfly folder inside it; a click opens it in a Finder window
            // holding the photos that hang on the line.
            return SettingFilm("folder", FilmScene.line(cards: 2) + [
                .show(.folder, Box(0.4, 0.6, 0.11, 0.15), from: 0.2, to: 1.6),
                .show(.folder, Box(0.6, 0.6, 0.14, 0.19), from: 0.45, to: 1.6),
                .move(.window(.finder), Box(0.6, 0.6, 0.14, 0.19), Box(0.5, 0.64, 0.6, 0.52), start: 1.65, end: 2.2,
                      appear: 1.6),
                .show(.card(0), Box(0.373, 0.653, 0.2375, 0.36), from: 2.2),
                .show(.card(1), Box(0.631, 0.653, 0.2375, 0.36), from: 2.35),
                Part(kind: .cursor, keys: [
                    SettingFilm.Key(0.5, Box(0.88, 0.86, 0.05, 0.08), opacity: 0),
                    SettingFilm.Key(0.65, Box(0.88, 0.86, 0.05, 0.08)),
                    SettingFilm.Key(1.1, Box(0.62, 0.64, 0.05, 0.08)),
                    SettingFilm.Key(1.6, Box(0.62, 0.64, 0.05, 0.08)),
                    SettingFilm.Key(1.8, Box(0.62, 0.64, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.62, 0.63, at: 1.45),
            ])
        case .lineStyle:
            // The same photos hang on the rope, then stand on a glass shelf, then sit in the black island.
            return SettingFilm("rectangle.3.group", [FilmScene.desktop, FilmScene.menuBar,
                .show(.line(.rope), FilmScene.ropeBox, to: 0.9),
                .show(.line(.shelf), Box(0.5, 0.27, 0.66, 0.24), from: 0.9, to: 2.0),
                .show(.line(.island), Box(0.5, 0.16, 0.68, 0.32), from: 2.0),
                Part(kind: .card(0), keys: [
                    SettingFilm.Key(0, FilmScene.slot(0), angle: -4), SettingFilm.Key(0.9, FilmScene.slot(0), angle: -4),
                    SettingFilm.Key(1.3, Box(0.3, 0.27, 0.14, 0.17)), SettingFilm.Key(2.0, Box(0.3, 0.27, 0.14, 0.17)),
                    SettingFilm.Key(2.4, Box(0.3, 0.17, 0.14, 0.17)),
                ]),
                Part(kind: .card(1), keys: [
                    SettingFilm.Key(0, FilmScene.slot(1), angle: 2), SettingFilm.Key(0.9, FilmScene.slot(1), angle: 2),
                    SettingFilm.Key(1.3, Box(0.5, 0.27, 0.14, 0.17)), SettingFilm.Key(2.0, Box(0.5, 0.27, 0.14, 0.17)),
                    SettingFilm.Key(2.4, Box(0.5, 0.17, 0.14, 0.17)),
                ]),
                Part(kind: .card(2), keys: [
                    SettingFilm.Key(0, FilmScene.slot(2), angle: 5), SettingFilm.Key(0.9, FilmScene.slot(2), angle: 5),
                    SettingFilm.Key(1.3, Box(0.7, 0.27, 0.14, 0.17)), SettingFilm.Key(2.0, Box(0.7, 0.27, 0.14, 0.17)),
                    SettingFilm.Key(2.4, Box(0.7, 0.17, 0.14, 0.17)),
                ]),
            ])
        case .whenThePointerRestsInTheMenuBar:
            // The pointer rests in the menu bar and the line glides down from behind it.
            return SettingFilm("cursorarrow.rays", [FilmScene.desktop,
                .move(.line(.rope), Box(0.5, -0.22, 1.04, 0.12), FilmScene.ropeBox, start: 1.1, end: 1.6, appear: 0),
                Part(kind: .card(0), keys: [
                    SettingFilm.Key(0, Box(0.24, -0.14, 0.14, 0.17)), SettingFilm.Key(1.1, Box(0.24, -0.14, 0.14, 0.17)),
                    SettingFilm.Key(1.6, FilmScene.slot(0), angle: 1), SettingFilm.Key(1.95, FilmScene.slot(0), angle: -6),
                    SettingFilm.Key(2.3, FilmScene.slot(0), angle: -4),
                ]),
                Part(kind: .card(1), keys: [
                    SettingFilm.Key(0, Box(0.5, -0.125, 0.14, 0.17)), SettingFilm.Key(1.1, Box(0.5, -0.125, 0.14, 0.17)),
                    SettingFilm.Key(1.6, FilmScene.slot(1), angle: 7), SettingFilm.Key(1.95, FilmScene.slot(1), angle: 0),
                    SettingFilm.Key(2.3, FilmScene.slot(1), angle: 2),
                ]),
                Part(kind: .card(2), keys: [
                    SettingFilm.Key(0, Box(0.76, -0.14, 0.14, 0.17)), SettingFilm.Key(1.1, Box(0.76, -0.14, 0.14, 0.17)),
                    SettingFilm.Key(1.6, FilmScene.slot(2), angle: 10), SettingFilm.Key(1.95, FilmScene.slot(2), angle: 3),
                    SettingFilm.Key(2.3, FilmScene.slot(2), angle: 5),
                ]),
                FilmScene.menuBar,
                .cursor([(0.6, 0.75), (0.64, 0.035)], start: 0.1, each: 0.7),
            ])
        case .whenSomethingNewHangs:
            // A screenshot is taken on a page; the line comes down by itself, swinging, and the new photo
            // flies onto it.
            return SettingFilm("photo.badge.plus", [FilmScene.desktop,
                .show(.window(.browser), Box(0.5, 0.68, 0.6, 0.5)),
                .move(.selection, Box(0.39, 0.6, 0.02, 0.02), Box(0.5, 0.72, 0.24, 0.24), start: 0.35, end: 1.0,
                      appear: 0.3, leave: 1.15),
                .move(.line(.rope), Box(0.5, -0.22, 1.04, 0.12), FilmScene.ropeBox, start: 1.15, end: 1.7, appear: 0),
                Part(kind: .card(0), keys: [
                    SettingFilm.Key(0, Box(0.24, -0.14, 0.14, 0.17)), SettingFilm.Key(1.15, Box(0.24, -0.14, 0.14, 0.17)),
                    SettingFilm.Key(1.7, FilmScene.slot(0), angle: 1), SettingFilm.Key(2.05, FilmScene.slot(0), angle: -6),
                    SettingFilm.Key(2.4, FilmScene.slot(0), angle: -4),
                ]),
                Part(kind: .card(1), keys: [
                    SettingFilm.Key(0, Box(0.5, -0.125, 0.14, 0.17)), SettingFilm.Key(1.15, Box(0.5, -0.125, 0.14, 0.17)),
                    SettingFilm.Key(1.7, FilmScene.slot(1), angle: 7), SettingFilm.Key(2.05, FilmScene.slot(1), angle: 0),
                    SettingFilm.Key(2.4, FilmScene.slot(1), angle: 2),
                ]),
                Part(kind: .card(2), keys: [
                    SettingFilm.Key(1.2, Box(0.5, 0.72, 0.24, 0.24), opacity: 0),
                    SettingFilm.Key(1.3, Box(0.5, 0.72, 0.24, 0.24)),
                    SettingFilm.Key(1.9, FilmScene.slot(2), angle: 10), SettingFilm.Key(2.25, FilmScene.slot(2), angle: 3),
                    SettingFilm.Key(2.6, FilmScene.slot(2), angle: 5),
                ]),
                FilmScene.menuBar,
                Part(kind: .cursor, keys: [
                    SettingFilm.Key(0.2, Box(0.38, 0.59, 0.05, 0.08), opacity: 0),
                    SettingFilm.Key(0.35, Box(0.38, 0.59, 0.05, 0.08)),
                    SettingFilm.Key(1.0, Box(0.62, 0.84, 0.05, 0.08)),
                    SettingFilm.Key(1.9, Box(0.62, 0.84, 0.05, 0.08)),
                    SettingFilm.Key(2.1, Box(0.62, 0.84, 0.05, 0.08), opacity: 0),
                ]),
            ])
        case .overFullScreenApps:
            // A click on the green button takes a window to full screen and the menu bar goes; the pointer
            // pushes at the top edge and the line comes down over the window, swinging.
            return SettingFilm("arrow.up.left.and.down.right.and.arrow.up.right.and.down.left",
                [FilmScene.desktop,
                 .show(.menuBar, Box(0.5, 0.04, 1, 0.08), to: 1.15),
                 Part(kind: .window(.browser), keys: [
                    SettingFilm.Key(0, Box(0.5, 0.6, 0.56, 0.5)), SettingFilm.Key(0.85, Box(0.5, 0.6, 0.56, 0.5)),
                    SettingFilm.Key(1.35, Box(0.5, 0.5, 1, 1)), SettingFilm.Key(1.55, Box(0.5, 0.5, 1, 1), opacity: 0.8),
                 ]),
                 .move(.line(.rope), Box(0.5, -0.22, 1.04, 0.12), FilmScene.ropeBox, start: 1.9, end: 2.4, appear: 0),
                ] + (0..<3).map { n -> Part in
                    let slot = FilmScene.slot(n), tilt = FilmScene.tilt(n)
                    let hidden = Box(slot.x, slot.y - 0.42, slot.w, slot.h)
                    return Part(kind: .card(n), keys: [
                        SettingFilm.Key(0, hidden), SettingFilm.Key(1.9, hidden),
                        SettingFilm.Key(2.4, slot, angle: tilt + 5), SettingFilm.Key(2.75, slot, angle: tilt - 2),
                        SettingFilm.Key(3.1, slot, angle: tilt),
                    ])
                } + [
                 .cursor([(0.62, 0.82), (0.3, 0.395), (0.3, 0.395), (0.5, 0.015)], start: 0.1, each: 0.5),
                 .click(0.3, 0.385, at: 0.7),
            ])
        case .notDuringACall:
            // A call starts, its camera and microphone on: the line goes back up, and the pointer resting in
            // the menu bar brings nothing down.
            return SettingFilm("video.fill", [FilmScene.desktop,
                .show(.window(.browser), Box(0.5, 0.66, 0.56, 0.48), from: 0.3),
                .show(.symbol("video.fill"), Box(0.44, 0.7, 0.1, 0.16), from: 0.4),
                .show(.symbol("mic.fill"), Box(0.56, 0.7, 0.1, 0.16), from: 0.4),
                .move(.line(.rope), FilmScene.ropeBox, Box(0.5, -0.22, 1.04, 0.12), start: 1.0, end: 1.5, appear: 0),
                .move(.card(0), FilmScene.slot(0), Box(0.24, -0.14, 0.14, 0.17), start: 1.0, end: 1.5, appear: 0,
                      angles: (FilmScene.tilt(0), 0)),
                .move(.card(1), FilmScene.slot(1), Box(0.5, -0.125, 0.14, 0.17), start: 1.0, end: 1.5, appear: 0,
                      angles: (FilmScene.tilt(1), 0)),
                FilmScene.menuBar,
                Part(kind: .cursor, keys: [
                    SettingFilm.Key(0, Box(0.62, 0.035, 0.05, 0.08)), SettingFilm.Key(1.8, Box(0.62, 0.035, 0.05, 0.08)),
                    SettingFilm.Key(2.3, Box(0.5, 0.03, 0.05, 0.08)), SettingFilm.Key(2.8, Box(0.56, 0.035, 0.05, 0.08)),
                ]),
            ])
        case .lineSize:
            // The size picker goes from small to medium to large, and the photos on the line grow with it.
            return SettingFilm("ruler", [FilmScene.desktop, FilmScene.menuBar, FilmScene.rope(),
                Part(kind: .card(0), keys: [
                    SettingFilm.Key(0, Box(0.24, 0.255, 0.1, 0.12), angle: -4),
                    SettingFilm.Key(0.8, Box(0.24, 0.255, 0.1, 0.12), angle: -4),
                    SettingFilm.Key(1.2, Box(0.24, 0.28, 0.14, 0.17), angle: -4),
                    SettingFilm.Key(1.85, Box(0.24, 0.28, 0.14, 0.17), angle: -4),
                    SettingFilm.Key(2.3, Box(0.24, 0.31, 0.19, 0.23), angle: -4),
                ]),
                Part(kind: .card(1), keys: [
                    SettingFilm.Key(0, Box(0.5, 0.27, 0.1, 0.12), angle: 2),
                    SettingFilm.Key(0.8, Box(0.5, 0.27, 0.1, 0.12), angle: 2),
                    SettingFilm.Key(1.2, Box(0.5, 0.295, 0.14, 0.17), angle: 2),
                    SettingFilm.Key(1.85, Box(0.5, 0.295, 0.14, 0.17), angle: 2),
                    SettingFilm.Key(2.3, Box(0.5, 0.325, 0.19, 0.23), angle: 2),
                ]),
                Part(kind: .card(2), keys: [
                    SettingFilm.Key(0, Box(0.76, 0.255, 0.1, 0.12), angle: 5),
                    SettingFilm.Key(0.8, Box(0.76, 0.255, 0.1, 0.12), angle: 5),
                    SettingFilm.Key(1.2, Box(0.76, 0.28, 0.14, 0.17), angle: 5),
                    SettingFilm.Key(1.85, Box(0.76, 0.28, 0.14, 0.17), angle: 5),
                    SettingFilm.Key(2.3, Box(0.76, 0.31, 0.19, 0.23), angle: 5),
                ]),
                .show(.symbol("photo"), Box(0.37, 0.8, 0.08, 0.128)),
                .show(.symbol("photo"), Box(0.5, 0.8, 0.1, 0.16)),
                .show(.symbol("photo"), Box(0.65, 0.8, 0.12, 0.192)),
                Part(kind: .outline, keys: [
                    SettingFilm.Key(0, Box(0.37, 0.8, 0.105, 0.153)), SettingFilm.Key(0.8, Box(0.37, 0.8, 0.105, 0.153)),
                    SettingFilm.Key(1.2, Box(0.5, 0.8, 0.125, 0.185)), SettingFilm.Key(1.85, Box(0.5, 0.8, 0.125, 0.185)),
                    SettingFilm.Key(2.3, Box(0.65, 0.8, 0.145, 0.217)),
                ]),
            ])
        case .keepOnLine:
            // A full line takes a new photo at its newest end; the others move along and the oldest falls off.
            return SettingFilm("rectangle.split.3x1", [FilmScene.desktop, FilmScene.menuBar, FilmScene.rope(),
                Part(kind: .card(0), keys: [
                    SettingFilm.Key(0, Box(0.14, 0.266, 0.14, 0.17), angle: -4),
                    SettingFilm.Key(0.9, Box(0.14, 0.266, 0.14, 0.17), angle: -4),
                    SettingFilm.Key(1.7, Box(0.06, 1.15, 0.14, 0.17), opacity: 0.2, angle: -50),
                ]),
                .move(.card(1), Box(0.32, 0.288, 0.14, 0.17), Box(0.14, 0.266, 0.14, 0.17), start: 0.9, end: 1.45,
                      appear: 0, angles: (2, 2)),
                .move(.card(2), Box(0.5, 0.295, 0.14, 0.17), Box(0.32, 0.288, 0.14, 0.17), start: 0.9, end: 1.45,
                      appear: 0, angles: (5, 5)),
                .move(.card(0), Box(0.68, 0.288, 0.14, 0.17), Box(0.5, 0.295, 0.14, 0.17), start: 0.9, end: 1.45,
                      appear: 0, angles: (-3, -3)),
                .move(.card(1), Box(0.86, 0.266, 0.14, 0.17), Box(0.68, 0.288, 0.14, 0.17), start: 0.9, end: 1.45,
                      appear: 0, angles: (3, 3)),
                Part(kind: .card(2), keys: [
                    SettingFilm.Key(0.3, Box(0.62, 0.74, 0.2, 0.24), opacity: 0),
                    SettingFilm.Key(0.5, Box(0.62, 0.74, 0.2, 0.24)),
                    SettingFilm.Key(0.9, Box(0.62, 0.74, 0.2, 0.24)),
                    SettingFilm.Key(1.6, Box(0.86, 0.266, 0.14, 0.17), angle: 8),
                    SettingFilm.Key(2.0, Box(0.86, 0.266, 0.14, 0.17), angle: 3),
                ]),
            ])
        case .countOnTheMenuBarIcon:
            // Close to the menu bar: a new screenshot flies into Snapfly's icon, the count beside it goes from 2
            // to 3 and a small dot comes on the icon's corner; the pointer rests in the menu bar, the dot goes as
            // the line starts down, and the line comes down with its three photos, swinging.
            return SettingFilm("number.circle", [FilmScene.desktop,
                .move(.line(.rope), Box(0.5, -0.22, 1.04, 0.12), FilmScene.ropeBox, start: 1.9, end: 2.4, appear: 0),
                Part(kind: .card(0), keys: [
                    .init(0, Box(0.24, -0.14, 0.14, 0.17)), .init(1.9, Box(0.24, -0.14, 0.14, 0.17)),
                    .init(2.4, FilmScene.slot(0), angle: 1), .init(2.75, FilmScene.slot(0), angle: -6),
                    .init(3.1, FilmScene.slot(0), angle: -4),
                ]),
                Part(kind: .card(1), keys: [
                    .init(0, Box(0.5, -0.125, 0.14, 0.17)), .init(1.9, Box(0.5, -0.125, 0.14, 0.17)),
                    .init(2.4, FilmScene.slot(1), angle: 7), .init(2.75, FilmScene.slot(1), angle: 0),
                    .init(3.1, FilmScene.slot(1), angle: 2),
                ]),
                Part(kind: .card(2), keys: [
                    .init(0, Box(0.76, -0.14, 0.14, 0.17)), .init(1.9, Box(0.76, -0.14, 0.14, 0.17)),
                    .init(2.4, FilmScene.slot(2), angle: 10), .init(2.75, FilmScene.slot(2), angle: 3),
                    .init(3.1, FilmScene.slot(2), angle: 5),
                ]),
                .show(.menuBar, Box(0.5, 0.05, 1, 0.18)),
                .show(.symbol("2.circle.fill"), Box(0.955, 0.07, 0.07, 0.112), to: 1.0),
                .show(.symbol("3.circle.fill"), Box(0.955, 0.07, 0.07, 0.112), from: 1.0),
                .move(.card(2), Box(0.5, 0.6, 0.22, 0.26), Box(0.831, 0.065, 0.05, 0.06), start: 0.3, end: 0.9,
                      appear: 0.2, leave: 0.92),
                Part(kind: .symbol("circle.fill"), keys: [
                    .init(1.05, Box(0.865, 0.092, 0.03, 0.048), opacity: 0), .init(1.2, Box(0.865, 0.092, 0.069, 0.1104)),
                    .init(1.35, Box(0.865, 0.092, 0.06, 0.096)), .init(1.9, Box(0.865, 0.092, 0.06, 0.096)),
                    .init(2.1, Box(0.865, 0.092, 0.06, 0.096), opacity: 0),
                ]),
                .cursor([(0.62, 0.72), (0.55, 0.07)], start: 1.15, each: 0.45),
            ])
        case .takePhotosDownOnceSent:
            // A click on a photo's paper plane sends it into the chat's message box and it leaves the line;
            // a note rises above the Dock to say where it went.
            return SettingFilm("eye.slash", [FilmScene.desktop, FilmScene.menuBar,
                FilmScene.rope(), FilmScene.dock,
                .show(.window(.chat), Box(0.5, 0.6, 0.52, 0.36)),
                .show(.card(0), FilmScene.slot(0), angle: FilmScene.tilt(0)),
                .show(.card(2), FilmScene.slot(2), angle: FilmScene.tilt(2)),
                .move(.card(1), FilmScene.slot(1),
                      Box(0.33, FilmScene.chat(.messageBox, in: Box(0.5, 0.6, 0.52, 0.36)).y, 0.06, 0.075),
                      start: 1.0, end: 1.6, appear: 0, angles: (FilmScene.tilt(1), 0)),
                .show(.symbol("paperplane.fill"), Box(0.55, 0.355, 0.08, 0.128), to: 0.8),
                Part(kind: .cursor, keys: [
                    .init(0.15, Box(0.72, 0.62, 0.05, 0.08), opacity: 0), .init(0.3, Box(0.72, 0.62, 0.05, 0.08)),
                    .init(0.65, Box(0.555, 0.365, 0.05, 0.08)), .init(0.85, Box(0.555, 0.365, 0.05, 0.08)),
                    .init(1.05, Box(0.555, 0.365, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.55, 0.355, at: 0.75),
                Part(kind: .note, keys: [
                    .init(1.75, Box(0.5, 0.85, 0.3, 0.07), opacity: 0), .init(2.1, Box(0.5, 0.82, 0.3, 0.07)),
                ]),
            ])
        case .markPhotosSentBefore:
            // The invoice sent into the chat earlier is taken again and hangs; the sent-before paper plane
            // comes on its corner, and the pointer resting beside it brings up a tip saying where and when.
            return SettingFilm("checkmark.message.fill", [FilmScene.desktop, FilmScene.menuBar,
                FilmScene.rope(),
                .show(.window(.chat), Box(0.32, 0.66, 0.48, 0.46)),
                .show(.card(2), Box(0.46, 0.725, 0.09, 0.1)),
                .show(.card(0), FilmScene.slot(0, of: 2), angle: FilmScene.tilt(0)),
                .move(.card(2), Box(0.78, 0.66, 0.22, 0.26), FilmScene.slot(1, of: 2), start: 0.35, end: 0.95,
                      appear: 0.25, angles: (0, FilmScene.tilt(1))),
                .show(.symbol("paperplane.fill"), Box(0.715, 0.345, 0.08, 0.128), from: 1.15),
                .cursor([(0.93, 0.86), (0.745, 0.39)], start: 1.5, each: 0.5),
                .show(.bubble(mine: false), Box(0.765, 0.56, 0.22, 0.15), from: 2.15),
                .show(.text(lines: 2), Box(0.765, 0.56, 0.16, 0.07), from: 2.25),
            ])
        case .keepAHistory:
            // A photo let go from the line drops into the History, a window of the ones kept before; a click
            // on it there hangs it on the line again.
            return SettingFilm("clock.arrow.circlepath", [FilmScene.desktop, FilmScene.menuBar,
                FilmScene.rope(),
                .show(.card(0), FilmScene.slot(0, of: 2), angle: FilmScene.tilt(0)),
                .show(.window(.document), Box(0.5, 0.72, 0.3, 0.42)),
                .show(.symbol("clock.arrow.circlepath"), Box(0.33, 0.52, 0.09, 0.144)),
                .show(.card(1), Box(0.436, 0.6734, 0.124, 0.142)),
                .show(.card(0), Box(0.436, 0.8254, 0.124, 0.142)),
                .show(.card(1), Box(0.564, 0.8254, 0.124, 0.142)),
                Part(kind: .card(2), keys: [
                    .init(0, FilmScene.slot(1, of: 2), angle: FilmScene.tilt(1)),
                    .init(0.3, FilmScene.slot(1, of: 2), angle: FilmScene.tilt(1)),
                    .init(0.65, Box(0.76, 0.5, 0.14, 0.17)),
                    .init(1.15, Box(0.564, 0.6734, 0.124, 0.142)),
                    .init(1.9, Box(0.564, 0.6734, 0.124, 0.142)),
                    .init(2.45, FilmScene.slot(1, of: 2), angle: FilmScene.tilt(1)),
                ]),
                Part(kind: .cursor, keys: [
                    .init(1.15, Box(0.86, 0.9, 0.05, 0.08), opacity: 0), .init(1.3, Box(0.86, 0.9, 0.05, 0.08)),
                    .init(1.6, Box(0.564, 0.676, 0.05, 0.08)), .init(1.85, Box(0.564, 0.676, 0.05, 0.08)),
                    .init(2.05, Box(0.564, 0.676, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.564, 0.666, at: 1.75),
            ])
        case .iconsUnderPhotos:
            // The pointer rests on a photo and its row of chat icons comes up under it; the two icons make room as one
            // more chat springs in at the row's end, a click on it opens that chat, and the photo's covered copy lands
            // in its message box.
            return SettingFilm("squares.below.rectangle", FilmScene.line(cards: 2) + [
                .move(.window(.chat), Box(0.44, 0.5, 0.06, 0.096), Box(0.69, 0.66, 0.54, 0.5), start: 1.95, end: 2.4,
                      appear: 1.85),
                Part(kind: .symbol("sparkles"), keys: [
                    .init(0.45, Box(0.185, 0.41, 0.09, 0.144), opacity: 0),
                    .init(0.65, Box(0.185, 0.45, 0.09, 0.144)),
                    .init(1.0, Box(0.185, 0.45, 0.09, 0.144)),
                    .init(1.35, Box(0.13, 0.45, 0.09, 0.144)),
                ]),
                Part(kind: .symbol("envelope.fill"), keys: [
                    .init(0.45, Box(0.295, 0.41, 0.09, 0.144), opacity: 0),
                    .init(0.65, Box(0.295, 0.45, 0.09, 0.144)),
                    .init(1.0, Box(0.295, 0.45, 0.09, 0.144)),
                    .init(1.35, Box(0.24, 0.45, 0.09, 0.144)),
                ]),
                Part(kind: .symbol("bubble.left.fill"), keys: [
                    .init(1.15, Box(0.35, 0.45, 0.054, 0.0864), opacity: 0),
                    .init(1.35, Box(0.35, 0.45, 0.099, 0.1584)),
                    .init(1.5, Box(0.35, 0.45, 0.09, 0.144)),
                ]),
                .move(.card(0, covered: true), FilmScene.slot(0),
                      Box(0.513, FilmScene.chat(.messageBox, in: Box(0.69, 0.66, 0.54, 0.5)).y, 0.07, 0.09),
                      start: 2.4, end: 2.95, appear: 2.25, angles: (FilmScene.tilt(0), 0)),
                Part(kind: .cursor, keys: [
                    .init(0.1, Box(0.1, 0.62, 0.05, 0.08), opacity: 0),
                    .init(0.25, Box(0.1, 0.62, 0.05, 0.08)),
                    .init(0.45, Box(0.27, 0.29, 0.05, 0.08)),
                    .init(1.5, Box(0.27, 0.29, 0.05, 0.08)),
                    .init(1.75, Box(0.375, 0.5, 0.05, 0.08)),
                ]),
                .click(0.375, 0.49, at: 1.8),
            ])
        case .websitesOpenIn:
            // A click on the chat icon under a photo opens the chat's website in the chosen browser: the window
            // grows from the icon, the browser's globe settles on its title bar and the photo goes in.
            return SettingFilm("globe", [FilmScene.desktop, FilmScene.menuBar, FilmScene.rope(),
                .show(.card(0), FilmScene.slot(0), angle: FilmScene.tilt(0)),
                .show(.symbol("bubble.left.fill"), Box(0.5, 0.45, 0.09, 0.144), to: 0.9),
                .move(.window(.chat), Box(0.5, 0.45, 0.09, 0.144), Box(0.5, 0.66, 0.6, 0.5), start: 0.95, end: 1.45,
                      appear: 0.85),
                .move(.symbol("globe"), Box(0.5, 0.64, 0.1, 0.16), Box(0.5, 0.44, 0.08, 0.128), start: 1.45,
                      end: 1.85, appear: 1.1),
                .move(.card(1), FilmScene.slot(1),
                      Box(0.3, FilmScene.chat(.messageBox, in: Box(0.5, 0.66, 0.6, 0.5)).y, 0.07, 0.09),
                      start: 1.95, end: 2.5, appear: 0, angles: (FilmScene.tilt(1), 0)),
                Part(kind: .cursor, keys: [
                    .init(0.1, Box(0.82, 0.8, 0.05, 0.08), opacity: 0), .init(0.25, Box(0.82, 0.8, 0.05, 0.08)),
                    .init(0.6, Box(0.5, 0.46, 0.05, 0.08)), .init(0.85, Box(0.5, 0.46, 0.05, 0.08)),
                    .init(1.05, Box(0.5, 0.46, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.5, 0.46, at: 0.7),
            ])
        case .sendEachScreenshotTo:
            // A screenshot dragged on a page hangs as always, and its covered copy goes on into the AI chat,
            // where it waits in the message box beside a Return key not yet pressed.
            return SettingFilm("sparkles.rectangle.stack.fill", [FilmScene.desktop,
                FilmScene.menuBar, FilmScene.rope(),
                .show(.card(0), FilmScene.slot(0, of: 2), angle: FilmScene.tilt(0)),
                .show(.window(.browser), Box(0.32, 0.64, 0.5, 0.5)),
                .show(.window(.chat), Box(0.7, 0.68, 0.46, 0.48)),
                .show(.symbol("sparkles"), Box(0.89, 0.47, 0.09, 0.144)),
                .move(.selection, Box(0.15, 0.555, 0.02, 0.03), Box(0.26, 0.66, 0.24, 0.24), start: 0.3, end: 0.8,
                      appear: 0.3, leave: 0.95),
                Part(kind: .cursor, keys: [
                    .init(0.15, Box(0.14, 0.54, 0.05, 0.08), opacity: 0), .init(0.3, Box(0.14, 0.54, 0.05, 0.08)),
                    .init(0.8, Box(0.38, 0.78, 0.05, 0.08)), .init(0.95, Box(0.38, 0.78, 0.05, 0.08)),
                    .init(1.15, Box(0.38, 0.78, 0.05, 0.08), opacity: 0),
                ]),
                .move(.card(1), Box(0.26, 0.66, 0.24, 0.24), FilmScene.slot(1, of: 2), start: 1.15, end: 1.75,
                      appear: 1.05, angles: (0, FilmScene.tilt(1))),
                .move(.card(1, covered: true), FilmScene.slot(1, of: 2),
                      Box(0.557, FilmScene.chat(.messageBox, in: Box(0.7, 0.68, 0.46, 0.48)).y, 0.07, 0.09),
                      start: 2.0, end: 2.55, appear: 1.85, angles: (FilmScene.tilt(1), 0)),
                Part(kind: .key("↩"), keys: [
                    .init(2.55, Box(0.86, FilmScene.chat(.messageBox, in: Box(0.7, 0.68, 0.46, 0.48)).y, 0.07, 0.11),
                          opacity: 0),
                    .init(2.75, Box(0.86, FilmScene.chat(.messageBox, in: Box(0.7, 0.68, 0.46, 0.48)).y, 0.07, 0.11),
                          opacity: 0.45),
                ]),
            ])
        case .whereItGoes:
            // Three screenshots hang one by one and wait; when the AI chat comes to the front, covered copies
            // of all three go in together, beside the words already typed.
            return SettingFilm("signpost.right.fill", [FilmScene.desktop, FilmScene.menuBar,
                FilmScene.rope(),
                .move(.window(.chat), Box(0.5, 0.74, 0.6, 0.5), Box(0.5, 0.66, 0.6, 0.5), start: 1.55, end: 1.95,
                      appear: 1.45),
                .move(.symbol("sparkles"), Box(0.77, 0.52, 0.09, 0.144), Box(0.77, 0.44, 0.09, 0.144), start: 1.55,
                      end: 1.95, appear: 1.45),
                .move(.text(lines: 1), Box(0.63, FilmScene.chat(.messageBox, in: Box(0.5, 0.74, 0.6, 0.5)).y, 0.18, 0.04),
                      Box(0.63, FilmScene.chat(.messageBox, in: Box(0.5, 0.66, 0.6, 0.5)).y, 0.18, 0.04), start: 1.55,
                      end: 1.95, appear: 1.45),
                .move(.card(0), Box(0.24, 0.6, 0.18, 0.22), FilmScene.slot(0), start: 0.15, end: 0.65, appear: 0.05,
                      angles: (0, FilmScene.tilt(0))),
                .move(.card(1), Box(0.5, 0.6, 0.18, 0.22), FilmScene.slot(1), start: 0.55, end: 1.05, appear: 0.45,
                      angles: (0, FilmScene.tilt(1))),
                .move(.card(2), Box(0.76, 0.6, 0.18, 0.22), FilmScene.slot(2), start: 0.95, end: 1.45, appear: 0.85,
                      angles: (0, FilmScene.tilt(2))),
                .move(.card(0, covered: true), FilmScene.slot(0),
                      Box(0.298, FilmScene.chat(.messageBox, in: Box(0.5, 0.66, 0.6, 0.5)).y, 0.065, 0.085),
                      start: 2.2, end: 2.75, appear: 2.05, angles: (FilmScene.tilt(0), 0)),
                .move(.card(1, covered: true), FilmScene.slot(1),
                      Box(0.378, FilmScene.chat(.messageBox, in: Box(0.5, 0.66, 0.6, 0.5)).y, 0.065, 0.085),
                      start: 2.2, end: 2.75, appear: 2.05, angles: (FilmScene.tilt(1), 0)),
                .move(.card(2, covered: true), FilmScene.slot(2),
                      Box(0.458, FilmScene.chat(.messageBox, in: Box(0.5, 0.66, 0.6, 0.5)).y, 0.065, 0.085),
                      start: 2.2, end: 2.75, appear: 2.05, angles: (FilmScene.tilt(2), 0)),
            ])
        case .keepItOnTheLine:
            // A new screenshot hangs and the AI chat comes to the front; its covered copy goes into the message
            // box and is sent with Return, while the screenshot itself stays on the line, swinging a little.
            return SettingFilm("rectangle.on.rectangle", [FilmScene.desktop, FilmScene.menuBar,
                FilmScene.rope(),
                .show(.card(0), FilmScene.slot(0), angle: FilmScene.tilt(0)),
                .show(.card(2), FilmScene.slot(2), angle: FilmScene.tilt(2)),
                .move(.window(.chat), Box(0.5, 0.72, 0.6, 0.5), Box(0.5, 0.66, 0.6, 0.5), start: 0.7, end: 1.0,
                      appear: 0.6),
                .move(.symbol("sparkles"), Box(0.77, 0.5, 0.09, 0.144), Box(0.77, 0.44, 0.09, 0.144), start: 0.7,
                      end: 1.0, appear: 0.6),
                Part(kind: .card(1), keys: [
                    .init(0.05, Box(0.5, 0.6, 0.18, 0.22), opacity: 0),
                    .init(0.15, Box(0.5, 0.6, 0.18, 0.22)),
                    .init(0.65, FilmScene.slot(1), angle: FilmScene.tilt(1)),
                    .init(1.2, FilmScene.slot(1), angle: FilmScene.tilt(1)),
                    .init(1.4, FilmScene.slot(1), angle: -4),
                    .init(1.6, FilmScene.slot(1), angle: 4),
                    .init(1.8, FilmScene.slot(1), angle: FilmScene.tilt(1)),
                ]),
                Part(kind: .card(1, covered: true), keys: [
                    .init(1.05, FilmScene.slot(1), opacity: 0, angle: FilmScene.tilt(1)),
                    .init(1.2, FilmScene.slot(1), angle: FilmScene.tilt(1)),
                    .init(1.75, Box(0.32, FilmScene.chat(.messageBox, in: Box(0.5, 0.66, 0.6, 0.5)).y, 0.07, 0.09)),
                    .init(2.2, Box(0.32, FilmScene.chat(.messageBox, in: Box(0.5, 0.66, 0.6, 0.5)).y, 0.07, 0.09)),
                    .init(2.6, Box(0.69, 0.72, 0.085, 0.1)),
                ]),
                Part(kind: .key("↩"), keys: [
                    .init(1.8, Box(0.72, 0.831, 0.07, 0.11), opacity: 0),
                    .init(1.9, Box(0.72, 0.831, 0.07, 0.11)),
                    .init(1.95, Box(0.72, 0.831, 0.063, 0.099)),
                    .init(2.05, Box(0.72, 0.831, 0.07, 0.11)),
                    .init(2.1, Box(0.72, 0.831, 0.07, 0.11)),
                    .init(2.3, Box(0.72, 0.831, 0.07, 0.11), opacity: 0),
                ]),
            ])
        case .showTheScreenshotButton:
            // The round button slides in at the screen's edge; one click on it and a drag over the page
            // take a screenshot, which hangs on the line.
            return SettingFilm("camera.circle", FilmScene.line(cards: 2) + [
                .show(.window(.browser), Box(0.44, 0.64, 0.6, 0.56)),
                .move(.selection, Box(0.3, 0.5, 0.02, 0.03), Box(0.44, 0.65, 0.28, 0.3), start: 1.1, end: 1.5,
                      appear: 1.05, leave: 1.6),
                .move(.card(2), Box(0.44, 0.65, 0.28, 0.3), FilmScene.slot(2), start: 1.7, end: 2.2, appear: 1.6,
                      angles: (0, FilmScene.tilt(2))),
                Part(kind: .symbol("camera.viewfinder"), keys: [
                    .init(0.1, Box(1.0, 0.42, 0.09, 0.144), opacity: 0),
                    .init(0.5, Box(0.92, 0.42, 0.09, 0.144)),
                ]),
                .click(0.92, 0.42, at: 0.8),
                Part(kind: .cursor, keys: [
                    .init(0.3, Box(0.7, 0.86, 0.05, 0.08), opacity: 0),
                    .init(0.45, Box(0.7, 0.86, 0.05, 0.08)),
                    .init(0.72, Box(0.92, 0.43, 0.05, 0.08)),
                    .init(0.85, Box(0.92, 0.43, 0.05, 0.08)),
                    .init(1.1, Box(0.3, 0.5, 0.05, 0.08)),
                    .init(1.5, Box(0.58, 0.8, 0.05, 0.08)),
                    .init(2.2, Box(0.58, 0.8, 0.05, 0.08)),
                    .init(2.4, Box(0.58, 0.8, 0.05, 0.08), opacity: 0),
                ]),
            ])
        case .captureButtonClick:
            // Two clicks on the button, its way shown above it: the first lets you drag an area, the
            // second takes the whole screen at once.
            return SettingFilm("cursorarrow.click", [FilmScene.desktop, FilmScene.menuBar, FilmScene.rope(),
                .move(.selection, Box(0.3, 0.48, 0.02, 0.03), Box(0.45, 0.62, 0.3, 0.28), start: 0.8, end: 1.15,
                      appear: 0.75, leave: 1.25),
                .move(.card(0), Box(0.45, 0.62, 0.3, 0.28), FilmScene.slot(0), start: 1.25, end: 1.75, appear: 1.2,
                      angles: (0, FilmScene.tilt(0))),
                Part(kind: .card(1), keys: [
                    .init(1.75, Box(0.5, 0.5, 1, 1), opacity: 0),
                    .init(1.8, Box(0.5, 0.5, 1, 1), opacity: 0.5),
                    .init(2.25, FilmScene.slot(1), angle: FilmScene.tilt(1)),
                ]),
                .show(.symbol("camera.viewfinder"), Box(0.92, 0.42, 0.09, 0.144)),
                .show(.symbol("rectangle.dashed"), Box(0.92, 0.26, 0.08, 0.128), from: 0.1, to: 0.6),
                .show(.symbol("display"), Box(0.92, 0.26, 0.08, 0.128), from: 1.3, to: 1.9),
                .click(0.92, 0.42, at: 0.4),
                .click(0.92, 0.42, at: 1.7),
                Part(kind: .cursor, keys: [
                    .init(0.05, Box(0.84, 0.62, 0.05, 0.08), opacity: 0),
                    .init(0.2, Box(0.84, 0.62, 0.05, 0.08)),
                    .init(0.38, Box(0.92, 0.43, 0.05, 0.08)),
                    .init(0.45, Box(0.92, 0.43, 0.05, 0.08)),
                    .init(0.75, Box(0.3, 0.48, 0.05, 0.08)),
                    .init(0.8, Box(0.3, 0.48, 0.05, 0.08)),
                    .init(1.15, Box(0.6, 0.76, 0.05, 0.08)),
                    .init(1.25, Box(0.6, 0.76, 0.05, 0.08)),
                    .init(1.6, Box(0.92, 0.43, 0.05, 0.08)),
                    .init(1.8, Box(0.92, 0.43, 0.05, 0.08)),
                    .init(2.0, Box(0.92, 0.43, 0.05, 0.08), opacity: 0),
                ]),
            ])
        case .captureButtonIcon:
            // The button at the screen's edge takes one glyph after another,
            // each fading in with a small bounce, and keeps the last.
            return SettingFilm("square.grid.3x2", FilmScene.line(cards: 2) + [
                Part(kind: .symbol("camera.viewfinder"), keys: [
                    .init(0, Box(0.92, 0.42, 0.09, 0.144)),
                    .init(0.7, Box(0.92, 0.42, 0.09, 0.144)),
                    .init(0.9, Box(0.92, 0.42, 0.09, 0.144), opacity: 0),
                ]),
                Part(kind: .symbol("camera.aperture"), keys: [
                    .init(0.7, Box(0.92, 0.42, 0.09, 0.144), opacity: 0),
                    .init(0.9, Box(0.92, 0.42, 0.09, 0.144)),
                    .init(1.05, Box(0.92, 0.42, 0.1035, 0.1656)),
                    .init(1.2, Box(0.92, 0.42, 0.09, 0.144)),
                    .init(1.4, Box(0.92, 0.42, 0.09, 0.144)),
                    .init(1.6, Box(0.92, 0.42, 0.09, 0.144), opacity: 0),
                ]),
                Part(kind: .symbol("bolt.fill"), keys: [
                    .init(1.4, Box(0.92, 0.42, 0.09, 0.144), opacity: 0),
                    .init(1.6, Box(0.92, 0.42, 0.09, 0.144)),
                    .init(1.75, Box(0.92, 0.42, 0.1035, 0.1656)),
                    .init(1.9, Box(0.92, 0.42, 0.09, 0.144)),
                    .init(2.1, Box(0.92, 0.42, 0.09, 0.144)),
                    .init(2.3, Box(0.92, 0.42, 0.09, 0.144), opacity: 0),
                ]),
                Part(kind: .symbol("sparkles"), keys: [
                    .init(2.1, Box(0.92, 0.42, 0.09, 0.144), opacity: 0),
                    .init(2.3, Box(0.92, 0.42, 0.09, 0.144)),
                    .init(2.45, Box(0.92, 0.42, 0.1035, 0.1656)),
                    .init(2.6, Box(0.92, 0.42, 0.09, 0.144)),
                ]),
            ])
        case .captureButtonColor:
            // A ring round the button shows its colour: frosted glass, then the plain graphite badge,
            // then the accent, held; the glyph stays put.
            return SettingFilm("circle.lefthalf.filled", FilmScene.line(cards: 2) + [
                .show(.bubble(mine: false), Box(0.92, 0.42, 0.12, 0.192), from: 0.4, to: 1.1),
                .show(.bubble(mine: true), Box(0.92, 0.42, 0.12, 0.192), from: 1.8),
                .show(.symbol("camera.viewfinder"), Box(0.92, 0.42, 0.09, 0.144)),
            ])
        case .showOrHideTheLine:
            // ⌃⌥T tucks the line away above the screen, and again brings it back
            // down under the menu bar, swinging as it settles.
            return SettingFilm("menubar.arrow.down.rectangle", [FilmScene.desktop,
                Part(kind: .line(.rope), keys: [
                    .init(0, FilmScene.ropeBox),
                    .init(0.8, FilmScene.ropeBox),
                    .init(1.2, Box(0.5, -0.22, 1.04, 0.12)),
                    .init(1.9, Box(0.5, -0.22, 1.04, 0.12)),
                    .init(2.4, FilmScene.ropeBox),
                ]),
                Part(kind: .card(0), keys: [
                    .init(0, FilmScene.slot(0), angle: FilmScene.tilt(0)),
                    .init(0.8, FilmScene.slot(0), angle: FilmScene.tilt(0)),
                    .init(1.2, Box(0.24, -0.14, 0.14, 0.17), angle: FilmScene.tilt(0)),
                    .init(1.9, Box(0.24, -0.14, 0.14, 0.17), angle: FilmScene.tilt(0)),
                    .init(2.4, FilmScene.slot(0), angle: FilmScene.tilt(0) + 5),
                    .init(2.75, FilmScene.slot(0), angle: FilmScene.tilt(0) - 2),
                    .init(3.1, FilmScene.slot(0), angle: FilmScene.tilt(0)),
                ]),
                Part(kind: .card(1), keys: [
                    .init(0, FilmScene.slot(1), angle: FilmScene.tilt(1)),
                    .init(0.8, FilmScene.slot(1), angle: FilmScene.tilt(1)),
                    .init(1.2, Box(0.5, -0.125, 0.14, 0.17), angle: FilmScene.tilt(1)),
                    .init(1.9, Box(0.5, -0.125, 0.14, 0.17), angle: FilmScene.tilt(1)),
                    .init(2.4, FilmScene.slot(1), angle: FilmScene.tilt(1) + 5),
                    .init(2.75, FilmScene.slot(1), angle: FilmScene.tilt(1) - 2),
                    .init(3.1, FilmScene.slot(1), angle: FilmScene.tilt(1)),
                ]),
                FilmScene.menuBar,
                .show(.key("⌃"), Box(0.41, 0.6, 0.07, 0.11), from: 0.2, to: 0.75),
                .show(.key("⌥"), Box(0.5, 0.6, 0.07, 0.11), from: 0.3, to: 0.75),
                .show(.key("T"), Box(0.59, 0.6, 0.07, 0.11), from: 0.4, to: 0.75),
                .show(.key("⌃"), Box(0.41, 0.6, 0.07, 0.11), from: 1.3, to: 1.85),
                .show(.key("⌥"), Box(0.5, 0.6, 0.07, 0.11), from: 1.4, to: 1.85),
                .show(.key("T"), Box(0.59, 0.6, 0.07, 0.11), from: 1.5, to: 1.85),
            ])
        case .sendTheNewestPhoto:
            // ⌃⌥V and the newest photo leaves the line for the message box of the
            // chat in front.
            return SettingFilm("paperplane", FilmScene.line(cards: 2) + [
                .show(.window(.chat), Box(0.5, 0.66, 0.6, 0.5)),
                .show(.key("⌃"), Box(0.41, 0.6, 0.07, 0.11), from: 0.2, to: 0.8),
                .show(.key("⌥"), Box(0.5, 0.6, 0.07, 0.11), from: 0.3, to: 0.8),
                .show(.key("V"), Box(0.59, 0.6, 0.07, 0.11), from: 0.4, to: 0.8),
                Part(kind: .card(2), keys: [
                    .init(0, FilmScene.slot(2), angle: FilmScene.tilt(2)),
                    .init(1.0, FilmScene.slot(2), angle: FilmScene.tilt(2)),
                    .init(1.65, Box(0.3, FilmScene.chat(.messageBox, in: Box(0.5, 0.66, 0.6, 0.5)).y, 0.075, 0.096)),
                    .init(2.0, Box(0.3, FilmScene.chat(.messageBox, in: Box(0.5, 0.66, 0.6, 0.5)).y, 0.07, 0.09)),
                ]),
            ])
        case .searchScreenshots:
            // ⌃⌥F brings the search bar under the line; as a word is typed, the
            // photo that has it stays bright, marked there, and the other dims.
            return SettingFilm("magnifyingglass", [FilmScene.desktop, FilmScene.menuBar, FilmScene.rope(),
                Part(kind: .card(0), keys: [
                    .init(0, FilmScene.slot(0, of: 2), angle: FilmScene.tilt(0)),
                    .init(2.0, FilmScene.slot(0, of: 2), angle: FilmScene.tilt(0)),
                    .init(2.3, FilmScene.slot(0, of: 2), opacity: 0.3, angle: FilmScene.tilt(0)),
                ]),
                .show(.card(1), FilmScene.slot(1, of: 2), angle: FilmScene.tilt(1)),
                .show(.key("⌃"), Box(0.41, 0.6, 0.07, 0.11), from: 0.2, to: 0.75),
                .show(.key("⌥"), Box(0.5, 0.6, 0.07, 0.11), from: 0.3, to: 0.75),
                .show(.key("F"), Box(0.59, 0.6, 0.07, 0.11), from: 0.4, to: 0.75),
                Part(kind: .line(.shelf), keys: [
                    .init(0.95, Box(0.5, 0.46, 0.56, 0.13), opacity: 0),
                    .init(1.25, Box(0.5, 0.54, 0.56, 0.13)),
                ]),
                Part(kind: .symbol("magnifyingglass"), keys: [
                    .init(0.95, Box(0.27, 0.46, 0.08, 0.128), opacity: 0),
                    .init(1.25, Box(0.27, 0.54, 0.08, 0.128)),
                ]),
                .move(.text(lines: 1), Box(0.32, 0.54, 0.01, 0.06), Box(0.425, 0.54, 0.22, 0.06), start: 1.35, end: 1.95,
                      appear: 1.3),
                .show(.outline, Box(0.757, 0.275, 0.12, 0.045), from: 2.05, angle: FilmScene.tilt(1)),
            ])
        case .takeAScreenshot:
            // ⌃⌥S, the paragraph under the pointer is outlined, a click takes it
            // and it flies onto the line.
            return SettingFilm("camera.viewfinder", FilmScene.line(cards: 1) + [
                .show(.window(.browser), Box(0.38, 0.67, 0.52, 0.52)),
                .show(.key("⌃"), Box(0.41, 0.6, 0.07, 0.11), from: 0.2, to: 0.8),
                .show(.key("⌥"), Box(0.5, 0.6, 0.07, 0.11), from: 0.3, to: 0.8),
                .show(.key("S"), Box(0.59, 0.6, 0.07, 0.11), from: 0.4, to: 0.8),
                .show(.outline, Box(0.38, 0.79, 0.48, 0.17), from: 1.3, to: 1.85),
                Part(kind: .cursor, keys: [
                    .init(0.9, Box(0.8, 0.86, 0.05, 0.08), opacity: 0),
                    .init(1.05, Box(0.8, 0.86, 0.05, 0.08)),
                    .init(1.4, Box(0.46, 0.78, 0.05, 0.08)),
                    .init(1.75, Box(0.46, 0.78, 0.05, 0.08)),
                    .init(1.95, Box(0.46, 0.78, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.46, 0.77, at: 1.65),
                .move(.card(1), Box(0.38, 0.79, 0.48, 0.17), FilmScene.slot(1), start: 1.95, end: 2.5, appear: 1.85,
                      angles: (0, FilmScene.tilt(1))),
            ])
        case .captureAWholePage:
            // ⌃⌥P: the page in front scrolls itself from top to bottom, and the whole page comes out of it as one
            // long picture that hangs on the line.
            return SettingFilm("scroll", FilmScene.line(cards: 2) + [
                .show(.window(.browser), Box(0.36, 0.67, 0.46, 0.54)),
                .show(.key("⌃"), Box(0.41, 0.6, 0.07, 0.11), from: 0.2, to: 0.8),
                .show(.key("⌥"), Box(0.5, 0.6, 0.07, 0.11), from: 0.3, to: 0.8),
                .show(.key("P"), Box(0.59, 0.6, 0.07, 0.11), from: 0.4, to: 0.8),
                .move(.symbol("arrow.down"), Box(0.53, 0.56, 0.09, 0.144), Box(0.53, 0.86, 0.09, 0.144),
                      start: 1.0, end: 1.9, appear: 0.95, leave: 2.0),
                .move(.card(2), Box(0.36, 0.67, 0.2, 0.5), Box(0.76, 0.365, 0.1, 0.34), start: 2.05, end: 2.65,
                      appear: 1.95, angles: (0, FilmScene.tilt(2))),
            ])
        case .recordTheScreen:
            // ⌃⌥R and a drag choose what to record; stop waits at the bottom while it records, ⌃⌥R again stops it,
            // and the recording hangs on the line with a play button.
            return SettingFilm("record.circle", FilmScene.line(cards: 0) + [
                .show(.window(.browser), Box(0.5, 0.6, 0.6, 0.44)),
                .move(.selection, Box(0.33, 0.595, 0.02, 0.03), Box(0.5, 0.69, 0.36, 0.22), start: 1.1, end: 1.45,
                      appear: 1.0, leave: 2.3),
                Part(kind: .cursor, keys: [
                    .init(0.95, Box(0.32, 0.58, 0.05, 0.08), opacity: 0),
                    .init(1.1, Box(0.32, 0.58, 0.05, 0.08)),
                    .init(1.45, Box(0.68, 0.8, 0.05, 0.08)),
                    .init(1.55, Box(0.68, 0.8, 0.05, 0.08)),
                    .init(1.75, Box(0.68, 0.8, 0.05, 0.08), opacity: 0),
                ]),
                Part(kind: .key("⌃"), keys: [
                    .init(0.2, Box(0.41, 0.6, 0.07, 0.11), opacity: 0),
                    .init(0.4, Box(0.41, 0.6, 0.07, 0.11)),
                    .init(0.75, Box(0.41, 0.6, 0.07, 0.11)),
                    .init(0.95, Box(0.41, 0.6, 0.07, 0.11), opacity: 0),
                    .init(1.9, Box(0.41, 0.6, 0.07, 0.11), opacity: 0),
                    .init(2.0, Box(0.41, 0.6, 0.07, 0.11)),
                    .init(2.3, Box(0.41, 0.6, 0.07, 0.11)),
                    .init(2.5, Box(0.41, 0.6, 0.07, 0.11), opacity: 0),
                ]),
                Part(kind: .key("⌥"), keys: [
                    .init(0.3, Box(0.5, 0.6, 0.07, 0.11), opacity: 0),
                    .init(0.5, Box(0.5, 0.6, 0.07, 0.11)),
                    .init(0.75, Box(0.5, 0.6, 0.07, 0.11)),
                    .init(0.95, Box(0.5, 0.6, 0.07, 0.11), opacity: 0),
                    .init(2.0, Box(0.5, 0.6, 0.07, 0.11), opacity: 0),
                    .init(2.1, Box(0.5, 0.6, 0.07, 0.11)),
                    .init(2.3, Box(0.5, 0.6, 0.07, 0.11)),
                    .init(2.5, Box(0.5, 0.6, 0.07, 0.11), opacity: 0),
                ]),
                Part(kind: .key("R"), keys: [
                    .init(0.4, Box(0.59, 0.6, 0.07, 0.11), opacity: 0),
                    .init(0.6, Box(0.59, 0.6, 0.07, 0.11)),
                    .init(0.75, Box(0.59, 0.6, 0.07, 0.11)),
                    .init(0.95, Box(0.59, 0.6, 0.07, 0.11), opacity: 0),
                    .init(2.1, Box(0.59, 0.6, 0.07, 0.11), opacity: 0),
                    .init(2.2, Box(0.59, 0.6, 0.07, 0.11)),
                    .init(2.3, Box(0.59, 0.6, 0.07, 0.11)),
                    .init(2.5, Box(0.59, 0.6, 0.07, 0.11), opacity: 0),
                ]),
                .show(.symbol("stop.fill"), Box(0.5, 0.9, 0.09, 0.144), from: 1.55, to: 2.3),
                .move(.card(1), Box(0.5, 0.69, 0.36, 0.22), FilmScene.slot(1), start: 2.4, end: 2.9, appear: 2.3,
                      angles: (0, FilmScene.tilt(1))),
                .move(.symbol("play.fill"), Box(0.5, 0.69, 0.08, 0.128), Box(0.5, 0.295, 0.08, 0.128), start: 2.4,
                      end: 2.9, appear: 2.3),
            ])
        case .showItWhilePhotosHang:
            // A photo drops onto the empty line, so the send button springs in just above the chat's own; one
            // click on it pastes the photo into the message box.
            return SettingFilm("paperplane.circle.fill", [FilmScene.desktop, FilmScene.menuBar,
                FilmScene.rope(),
                .move(.card(1), Box(0.5, 0.235, 0.14, 0.17), FilmScene.slot(1), start: 0.2, end: 0.5, appear: 0.1,
                      angles: (0, FilmScene.tilt(1))),
                .show(.window(.chat), Box(0.5, 0.685, 0.64, 0.59)),
                .show(.symbol("arrow.up"), Box(0.735, 0.886, 0.055, 0.088)),
                Part(kind: .bubble(mine: false), keys: [
                    .init(0.7, Box(0.655, 0.761, 0.144, 0.084), opacity: 0),
                    .init(0.95, Box(0.655, 0.761, 0.264, 0.154)),
                    .init(1.1, Box(0.655, 0.761, 0.24, 0.14)),
                    .init(2.0, Box(0.655, 0.761, 0.24, 0.14)),
                    .init(2.2, Box(0.655, 0.761, 0.24, 0.14), opacity: 0),
                ]),
                Part(kind: .card(1), keys: [
                    .init(0.7, Box(0.613, 0.761, 0.039, 0.057), opacity: 0),
                    .init(0.95, Box(0.578, 0.761, 0.0715, 0.1045)),
                    .init(1.1, Box(0.585, 0.761, 0.065, 0.095)),
                    .init(2.0, Box(0.585, 0.761, 0.065, 0.095)),
                    .init(2.45, Box(0.3, FilmScene.chat(.messageBox, in: Box(0.5, 0.685, 0.64, 0.59)).y, 0.07, 0.09)),
                ]),
                Part(kind: .symbol("paperplane.fill"), keys: [
                    .init(0.7, Box(0.703, 0.761, 0.051, 0.0816), opacity: 0),
                    .init(0.95, Box(0.743, 0.761, 0.0935, 0.1496)),
                    .init(1.1, Box(0.735, 0.761, 0.085, 0.136)),
                    .init(2.0, Box(0.735, 0.761, 0.085, 0.136)),
                    .init(2.2, Box(0.735, 0.761, 0.085, 0.136), opacity: 0),
                ]),
                Part(kind: .cursor, keys: [
                    .init(1.3, Box(0.5, 0.97, 0.05, 0.08), opacity: 0),
                    .init(1.4, Box(0.5, 0.97, 0.05, 0.08)),
                    .init(1.8, Box(0.74, 0.775, 0.05, 0.08)),
                    .init(2.0, Box(0.74, 0.775, 0.05, 0.08)),
                    .init(2.2, Box(0.74, 0.775, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.735, 0.761, at: 1.9),
            ])
        case .inChatApps:
            // The send button springs in over a chat app's message box; when Mail comes to the front, it springs in
            // over the mail being written instead.
            return SettingFilm("message.fill", FilmScene.line(cards: 2) + [
                .show(.window(.chat), Box(0.27, 0.68, 0.44, 0.5)),
                .show(.symbol("bubble.left.and.bubble.right.fill"), Box(0.455, 0.475, 0.08, 0.128)),
                .move(.window(.mail), Box(0.74, 1.2, 0.44, 0.5), Box(0.74, 0.68, 0.44, 0.5), start: 1.1, end: 1.6,
                      appear: 1.0),
                .move(.symbol("envelope.fill"), Box(0.925, 0.995, 0.08, 0.128), Box(0.925, 0.475, 0.08, 0.128),
                      start: 1.1, end: 1.6, appear: 1.0),
                Part(kind: .bubble(mine: false), keys: [
                    .init(0.35, Box(0.35, 0.746, 0.1296, 0.0756), opacity: 0),
                    .init(0.6, Box(0.35, 0.746, 0.2376, 0.1386)),
                    .init(0.75, Box(0.35, 0.746, 0.216, 0.126)),
                    .init(1.65, Box(0.35, 0.746, 0.216, 0.126)),
                    .init(1.85, Box(0.35, 0.746, 0.1296, 0.0756), opacity: 0),
                    .init(2.0, Box(0.83, 0.832, 0.1296, 0.0756), opacity: 0),
                    .init(2.25, Box(0.83, 0.832, 0.2376, 0.1386)),
                    .init(2.4, Box(0.83, 0.832, 0.216, 0.126)),
                ]),
                Part(kind: .card(1), keys: [
                    .init(0.35, Box(0.3122, 0.746, 0.0351, 0.0513), opacity: 0),
                    .init(0.6, Box(0.2807, 0.746, 0.0644, 0.0941)),
                    .init(0.75, Box(0.287, 0.746, 0.0585, 0.0855)),
                    .init(1.65, Box(0.287, 0.746, 0.0585, 0.0855)),
                    .init(1.85, Box(0.3122, 0.746, 0.0351, 0.0513), opacity: 0),
                    .init(2.0, Box(0.7922, 0.832, 0.0351, 0.0513), opacity: 0),
                    .init(2.25, Box(0.7607, 0.832, 0.0644, 0.0941)),
                    .init(2.4, Box(0.767, 0.832, 0.0585, 0.0855)),
                ]),
                Part(kind: .symbol("paperplane.fill"), keys: [
                    .init(0.35, Box(0.3932, 0.746, 0.0459, 0.0734), opacity: 0),
                    .init(0.6, Box(0.4292, 0.746, 0.0842, 0.1346)),
                    .init(0.75, Box(0.422, 0.746, 0.0765, 0.1224)),
                    .init(1.65, Box(0.422, 0.746, 0.0765, 0.1224)),
                    .init(1.85, Box(0.3932, 0.746, 0.0459, 0.0734), opacity: 0),
                    .init(2.0, Box(0.8732, 0.832, 0.0459, 0.0734), opacity: 0),
                    .init(2.25, Box(0.9092, 0.832, 0.0842, 0.1346)),
                    .init(2.4, Box(0.902, 0.832, 0.0765, 0.1224)),
                ]),
            ])
        case .chatButtonPosition:
            // The send button hops from just above the chat's send button to the window's top corner under the
            // toolbar, then to halfway down the screen's edge.
            return SettingFilm("rectangle.inset.bottomtrailing.filled", FilmScene.line(cards: 2) + [
                .show(.window(.chat), Box(0.5, 0.685, 0.64, 0.59)),
                .show(.symbol("arrow.up"), Box(0.735, 0.886, 0.055, 0.088)),
                Part(kind: .bubble(mine: false), keys: [
                    .init(0, Box(0.655, 0.761, 0.24, 0.14)),
                    .init(0.6, Box(0.655, 0.761, 0.24, 0.14)),
                    .init(0.95, Box(0.691, 0.53, 0.24, 0.14)),
                    .init(1.05, Box(0.69, 0.537, 0.24, 0.14)),
                    .init(1.5, Box(0.69, 0.537, 0.24, 0.14)),
                    .init(1.85, Box(0.84, 0.5, 0.24, 0.14)),
                    .init(2.0, Box(0.86, 0.5, 0.24, 0.14)),
                ]),
                Part(kind: .card(1), keys: [
                    .init(0, Box(0.585, 0.761, 0.065, 0.095)),
                    .init(0.6, Box(0.585, 0.761, 0.065, 0.095)),
                    .init(0.95, Box(0.621, 0.53, 0.065, 0.095)),
                    .init(1.05, Box(0.62, 0.537, 0.065, 0.095)),
                    .init(1.5, Box(0.62, 0.537, 0.065, 0.095)),
                    .init(1.85, Box(0.77, 0.5, 0.065, 0.095)),
                    .init(2.0, Box(0.79, 0.5, 0.065, 0.095)),
                ]),
                Part(kind: .symbol("paperplane.fill"), keys: [
                    .init(0, Box(0.735, 0.761, 0.085, 0.136)),
                    .init(0.6, Box(0.735, 0.761, 0.085, 0.136)),
                    .init(0.95, Box(0.771, 0.53, 0.085, 0.136)),
                    .init(1.05, Box(0.77, 0.537, 0.085, 0.136)),
                    .init(1.5, Box(0.77, 0.537, 0.085, 0.136)),
                    .init(1.85, Box(0.92, 0.5, 0.085, 0.136)),
                    .init(2.0, Box(0.94, 0.5, 0.085, 0.136)),
                ]),
            ])
        case .chatButtonStyle:
            // The send button with the newest photo, the one before leaning behind it, drops the photos and shrinks
            // into a small capsule round a bigger glyph circle.
            return SettingFilm("capsule.fill", FilmScene.line(cards: 2) + [
                .show(.window(.chat), Box(0.5, 0.685, 0.64, 0.59)),
                .show(.symbol("arrow.up"), Box(0.735, 0.886, 0.055, 0.088)),
                Part(kind: .bubble(mine: false), keys: [
                    .init(0, Box(0.655, 0.761, 0.24, 0.14)),
                    .init(1.1, Box(0.655, 0.761, 0.24, 0.14)),
                    .init(1.5, Box(0.72, 0.761, 0.12, 0.14)),
                    .init(1.7, Box(0.72, 0.761, 0.13, 0.14)),
                ]),
                Part(kind: .card(0), keys: [
                    .init(0, Box(0.566, 0.755, 0.055, 0.078), angle: -14),
                    .init(0.9, Box(0.566, 0.755, 0.055, 0.078), angle: -14),
                    .init(1.25, Box(0.71, 0.761, 0.02, 0.03), opacity: 0, angle: -14),
                ]),
                Part(kind: .card(1), keys: [
                    .init(0, Box(0.585, 0.761, 0.065, 0.095)),
                    .init(1.0, Box(0.585, 0.761, 0.065, 0.095)),
                    .init(1.35, Box(0.715, 0.761, 0.025, 0.035), opacity: 0),
                ]),
                Part(kind: .symbol("paperplane.fill"), keys: [
                    .init(0, Box(0.735, 0.761, 0.085, 0.136)),
                    .init(1.1, Box(0.735, 0.761, 0.085, 0.136)),
                    .init(1.5, Box(0.735, 0.761, 0.105, 0.168)),
                    .init(1.7, Box(0.735, 0.761, 0.095, 0.152)),
                    .init(2.2, Box(0.735, 0.761, 0.095, 0.152)),
                ]),
            ])
        case .chatButtonIcon:
            // The glyph on the send button's circle changes from the paper plane to the share box, then to the
            // photos, and keeps the last.
            return SettingFilm("circle.grid.2x2", FilmScene.line(cards: 2) + [
                .show(.window(.chat), Box(0.5, 0.685, 0.64, 0.59)),
                .show(.symbol("arrow.up"), Box(0.735, 0.886, 0.055, 0.088)),
                .show(.bubble(mine: false), Box(0.655, 0.761, 0.24, 0.14)),
                .show(.card(1), Box(0.585, 0.761, 0.065, 0.095)),
                .show(.symbol("paperplane.fill"), Box(0.735, 0.761, 0.085, 0.136), to: 0.8),
                Part(kind: .symbol("square.and.arrow.up"), keys: [
                    .init(0.8, Box(0.735, 0.761, 0.065, 0.104), opacity: 0),
                    .init(1.1, Box(0.735, 0.761, 0.085, 0.136)),
                    .init(1.6, Box(0.735, 0.761, 0.085, 0.136)),
                    .init(1.8, Box(0.735, 0.761, 0.085, 0.136), opacity: 0),
                ]),
                Part(kind: .symbol("photo.on.rectangle.angled"), keys: [
                    .init(1.6, Box(0.735, 0.761, 0.065, 0.104), opacity: 0),
                    .init(1.9, Box(0.735, 0.761, 0.085, 0.136)),
                    .init(2.3, Box(0.735, 0.761, 0.085, 0.136)),
                ]),
            ])
        case .chatButtonColor:
            // The send button's circle is plain graphite, then an even blue ring comes round it in the capsule: the
            // colour it now takes.
            return SettingFilm("paintbrush.fill", FilmScene.line(cards: 2) + [
                .show(.window(.chat), Box(0.5, 0.685, 0.64, 0.59)),
                .show(.symbol("arrow.up"), Box(0.735, 0.886, 0.055, 0.088)),
                .show(.bubble(mine: false), Box(0.655, 0.761, 0.24, 0.14)),
                .show(.card(1), Box(0.585, 0.761, 0.065, 0.095)),
                Part(kind: .bubble(mine: true), keys: [
                    .init(0.8, Box(0.735, 0.761, 0.0875, 0.14), opacity: 0),
                    .init(1.0, Box(0.735, 0.761, 0.0875, 0.14)),
                    .init(2.2, Box(0.735, 0.761, 0.0875, 0.14)),
                ]),
                .show(.symbol("paperplane.fill"), Box(0.735, 0.761, 0.07, 0.112)),
            ])
        case .chatApps:
            // A chat app is in front while a photo hangs, and the send button stays away; the app joins the list
            // of chat apps, and the send button springs in just above the chat's own send button.
            return SettingFilm("app.badge.checkmark", FilmScene.line(cards: 1) + [
                .show(.window(.chat), Box(0.42, 0.685, 0.64, 0.59)),
                .show(.symbol("arrow.up"), Box(0.655, 0.886, 0.055, 0.088)),
                .show(.bubble(mine: false), Box(0.87, 0.63, 0.14, 0.36)),
                .show(.symbol("envelope.fill"), Box(0.87, 0.55, 0.08, 0.128)),
                Part(kind: .symbol("bubble.left.and.bubble.right.fill"), keys: [
                    .init(0.45, Box(0.71, 0.42, 0.08, 0.128), opacity: 0),
                    .init(0.5, Box(0.71, 0.42, 0.08, 0.128)),
                    .init(1.05, Box(0.87, 0.71, 0.08, 0.128)),
                ]),
                .show(.symbol("bubble.left.and.bubble.right.fill"), Box(0.71, 0.42, 0.08, 0.128)),
                Part(kind: .bubble(mine: false), keys: [
                    .init(1.2, Box(0.625, 0.761, 0.09, 0.084), opacity: 0),
                    .init(1.45, Box(0.625, 0.761, 0.165, 0.154)),
                    .init(1.6, Box(0.625, 0.761, 0.15, 0.14)),
                    .init(2.1, Box(0.625, 0.761, 0.15, 0.14)),
                ]),
                Part(kind: .symbol("paperplane.fill"), keys: [
                    .init(1.2, Box(0.643, 0.761, 0.051, 0.0816), opacity: 0),
                    .init(1.45, Box(0.658, 0.761, 0.0935, 0.1496)),
                    .init(1.6, Box(0.655, 0.761, 0.085, 0.136)),
                    .init(2.1, Box(0.655, 0.761, 0.085, 0.136)),
                ]),
            ])
        case .chatWebsites:
            // In the browser an ordinary page is open and the send button stays away; the page turns into a chat
            // website, and the send button springs in just above the chat's own send button.
            return SettingFilm("safari", FilmScene.line(cards: 1) + [
                .show(.window(.browser), Box(0.5, 0.685, 0.64, 0.59), to: 0.85),
                .show(.window(.chat), Box(0.5, 0.685, 0.64, 0.59), from: 0.65),
                .show(.symbol("arrow.up"), Box(0.735, 0.886, 0.055, 0.088), from: 0.65),
                .show(.symbol("globe"), Box(0.5, 0.423, 0.08, 0.128)),
                Part(kind: .bubble(mine: false), keys: [
                    .init(1.1, Box(0.655, 0.761, 0.144, 0.084), opacity: 0),
                    .init(1.35, Box(0.655, 0.761, 0.264, 0.154)),
                    .init(1.5, Box(0.655, 0.761, 0.24, 0.14)),
                    .init(2.05, Box(0.655, 0.761, 0.24, 0.14)),
                ]),
                Part(kind: .card(0), keys: [
                    .init(1.1, Box(0.613, 0.761, 0.039, 0.057), opacity: 0),
                    .init(1.35, Box(0.578, 0.761, 0.0715, 0.1045)),
                    .init(1.5, Box(0.585, 0.761, 0.065, 0.095)),
                    .init(2.05, Box(0.585, 0.761, 0.065, 0.095)),
                ]),
                Part(kind: .symbol("paperplane.fill"), keys: [
                    .init(1.1, Box(0.703, 0.761, 0.051, 0.0816), opacity: 0),
                    .init(1.35, Box(0.743, 0.761, 0.0935, 0.1496)),
                    .init(1.5, Box(0.735, 0.761, 0.085, 0.136)),
                    .init(2.05, Box(0.735, 0.761, 0.085, 0.136)),
                ]),
            ])
        case .hidePrivateDetails:
            // Every switch for what to cover is off; one click sets the whole list, and the recommended switches
            // come on one after another while the page on the line has those details covered.
            return SettingFilm("hand.raised", FilmScene.line(cards: 0) + [
                .show(.window(.document), Box(0.72, 0.52, 0.44, 0.62)),
                .move(.cover, Box(0.532, 0.4398, 0.01, 0.0533),
                      FilmScene.cover(line: 1, of: .window(.document), at: Box(0.72, 0.52, 0.44, 0.62), part: 0.45),
                      start: 1.05, end: 1.5, appear: 1.0),
                .move(.cover, Box(0.725, 0.6669, 0.01, 0.0533), Box(0.8166, 0.6669, 0.1931, 0.0533), start: 1.5,
                      end: 2.0, appear: 1.45),
                .show(.window(.settings), Box(0.25, 0.69, 0.36, 0.46)),
                .show(.toggle(on: false), Box(0.3509, 0.6175, 0.077, 0.063), to: 0.95),
                .show(.toggle(on: false), Box(0.3509, 0.8322, 0.077, 0.063), to: 1.4),
                .show(.symbol("hand.raised"), Box(0.25, 0.37, 0.1, 0.16), from: 0.3),
                Part(kind: .cursor, keys: [
                    .init(0.3, Box(0.05, 0.3, 0.05, 0.08), opacity: 0),
                    .init(0.45, Box(0.05, 0.3, 0.05, 0.08)),
                    .init(0.75, Box(0.25, 0.38, 0.05, 0.08)),
                    .init(0.9, Box(0.25, 0.38, 0.05, 0.08)),
                    .init(1.1, Box(0.25, 0.38, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.25, 0.37, at: 0.8),
            ])
        case .detailNames:
            // A chat hangs on the line: the name that starts each message is
            // covered, one after the other, and the rest of each message stays.
            return SettingFilm("person.fill", FilmScene.line(cards: 0) + [
                .show(.window(.chat), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.bubble(mine: false), Box(0.368, 0.58, 0.24, 0.072)),
                .show(.text(lines: 1), Box(0.379, 0.3626, 0.24, 0.03)),
                .show(.text(lines: 1), Box(0.6385, 0.4807, 0.19, 0.03)),
                .show(.text(lines: 1), Box(0.368, 0.58, 0.2, 0.03)),
                .show(.symbol("person.fill"), Box(0.11, 0.3626, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.2557, 0.3626, 0.01, 0.0393),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.379, 0.3626, 0.24, 0.03), part: 0.35),
                      start: 0.8, end: 1.2, appear: 0.75),
                .move(.cover, Box(0.5402, 0.4807, 0.01, 0.0393),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.6385, 0.4807, 0.19, 0.03), part: 0.35),
                      start: 1.3, end: 1.7, appear: 1.25),
                .move(.cover, Box(0.2647, 0.58, 0.01, 0.0393),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.368, 0.58, 0.2, 0.03), part: 0.35),
                      start: 1.8, end: 2.2, appear: 1.75),
            ])
        case .detailPatientNames:
            // A medical report hangs on the line: the patient's name after its
            // label is covered, then the same name again further down; the
            // doctor's signature at the bottom stays.
            return SettingFilm("cross.case.fill", FilmScene.line(cards: 0) + [
                .show(.pdf, Box(0.5, 0.52, 0.4, 0.62)),
                .show(.symbol("cross.case.fill"), Box(0.21, 0.4533, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.383, 0.4533, 0.01, 0.0533), Box(0.463, 0.4533, 0.17, 0.0533), start: 0.8, end: 1.35,
                      appear: 0.75),
                .move(.cover, Box(0.3835, 0.6331, 0.01, 0.0533), Box(0.4615, 0.6331, 0.166, 0.0533), start: 1.5, end: 2.05,
                      appear: 1.45),
            ])
        case .detailOtherPeople:
            // A shop's invoice and a doctor's letter hang side by side: the
            // customer's name after its label on the invoice, then the doctor's
            // name after Dr. med. on the letter, are covered; the labels stay.
            return SettingFilm("person.2.fill", FilmScene.line(cards: 0) + [
                .show(.pdf, Box(0.36, 0.52, 0.28, 0.6)),
                .show(.symbol("cart.fill"), Box(0.455, 0.29, 0.08, 0.128)),
                .show(.window(.document), Box(0.7, 0.52, 0.3, 0.6)),
                .show(.symbol("stethoscope"), Box(0.8, 0.29, 0.08, 0.128)),
                .show(.symbol("person.2.fill"), Box(0.13, 0.4555, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.297, 0.4555, 0.01, 0.0533), Box(0.383, 0.4555, 0.183, 0.0533), start: 0.8, end: 1.35,
                      appear: 0.75),
                .move(.cover, Box(0.649, 0.7356, 0.01, 0.0533), Box(0.6913, 0.7356, 0.0946, 0.0533), start: 1.5, end: 2.05,
                      appear: 1.45),
            ])
        case .detailAddresses:
            // A letter hangs on the line: the street line under the name, then
            // the postcode and town under it, are covered whole; the name above
            // and the text below stay.
            return SettingFilm("house.fill", FilmScene.line(cards: 0) + [
                .show(.window(.document), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.symbol("house.fill"), Box(0.11, 0.5155, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.2447, 0.5155, 0.01, 0.0533),
                      FilmScene.cover(line: 2, of: .window(.document), at: Box(0.5, 0.52, 0.6, 0.62)),
                      start: 0.8, end: 1.35, appear: 0.75),
                .move(.cover, Box(0.2447, 0.5912, 0.01, 0.0533),
                      FilmScene.cover(line: 3, of: .window(.document), at: Box(0.5, 0.52, 0.6, 0.62)),
                      start: 1.5, end: 2.05, appear: 1.45),
            ])
        case .detailBirthDates:
            // A form hangs on the line: only the date after the birth label is
            // covered; the other lines, and their dates, stay.
            return SettingFilm("birthday.cake", FilmScene.line(cards: 0) + [
                .show(.window(.document), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.symbol("birthday.cake"), Box(0.11, 0.4398, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.55, 0.4398, 0.01, 0.0533), Box(0.6124, 0.4398, 0.1347, 0.0533), start: 1.2, end: 2.0,
                      appear: 1.15),
            ])
        case .detailEmails:
            // An email hangs on the line: the address in its To line, then one
            // in its text, are covered; the rest of the mail stays.
            return SettingFilm("envelope.fill", FilmScene.line(cards: 0) + [
                .show(.window(.mail), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.symbol("envelope.fill"), Box(0.11, 0.4114, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.295, 0.4114, 0.01, 0.0505), Box(0.4002, 0.4114, 0.2203, 0.0505), start: 0.8, end: 1.35,
                      appear: 0.75),
                .move(.cover, Box(0.43, 0.6697, 0.01, 0.0533), Box(0.4969, 0.6697, 0.1438, 0.0533), start: 1.5, end: 2.05,
                      appear: 1.45),
            ])
        case .detailPhones:
            // An iPhone screenshot of a contact hangs on the line: both phone
            // numbers are covered, the name above them stays.
            return SettingFilm("phone.fill", FilmScene.line(cards: 0) + [
                .show(.phone, Box(0.5, 0.52, 0.26, 0.62)),
                .show(.symbol("person.crop.circle.fill"), Box(0.5, 0.37, 0.09, 0.144)),
                .show(.text(lines: 1), Box(0.5, 0.49, 0.12, 0.05)),
                .show(.text(lines: 1), Box(0.5, 0.58, 0.16, 0.05)),
                .show(.text(lines: 1), Box(0.5, 0.67, 0.16, 0.05)),
                .show(.symbol("phone.fill"), Box(0.28, 0.58, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.4167, 0.58, 0.01, 0.0477),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.5, 0.58, 0.16, 0.05)),
                      start: 0.8, end: 1.35, appear: 0.75),
                .move(.cover, Box(0.4167, 0.67, 0.01, 0.0477),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.5, 0.67, 0.16, 0.05)),
                      start: 1.5, end: 2.05, appear: 1.45),
            ])
        case .detailUsernames:
            // A page of posts hangs on the line: the @name that starts one, and
            // the @name in another's text, are covered; the posts stay.
            return SettingFilm("at", FilmScene.line(cards: 0) + [
                .show(.window(.browser), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.symbol("at"), Box(0.11, 0.383, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.2447, 0.383, 0.01, 0.0533),
                      FilmScene.cover(line: 0, of: .window(.browser), at: Box(0.5, 0.52, 0.6, 0.62), part: 0.17),
                      start: 0.8, end: 1.35, appear: 0.75),
                .move(.cover, Box(0.405, 0.6101, 0.01, 0.0533), Box(0.45, 0.6101, 0.1, 0.0533), start: 1.5, end: 2.05,
                      appear: 1.45),
            ])
        case .detailFaces:
            // A video call hangs on the line: the face in the big picture, then
            // the one in the small picture, are covered; the call stays.
            return SettingFilm("face.smiling", FilmScene.line(cards: 0) + [
                .show(.window(.chat), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.bubble(mine: false), Box(0.5, 0.553, 0.52, 0.47)),
                .show(.symbol("person.crop.circle.fill"), Box(0.43, 0.53, 0.17, 0.272)),
                .show(.bubble(mine: true), Box(0.665, 0.7, 0.13, 0.16)),
                .show(.symbol("person.crop.circle.fill"), Box(0.665, 0.7, 0.075, 0.12)),
                .show(.symbol("face.smiling"), Box(0.11, 0.53, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.345, 0.53, 0.01, 0.29), Box(0.43, 0.53, 0.18, 0.29), start: 0.8, end: 1.35,
                      appear: 0.75),
                .move(.cover, Box(0.63, 0.7, 0.01, 0.13), Box(0.665, 0.7, 0.08, 0.13), start: 1.5, end: 2.05,
                      appear: 1.45),
            ])
        case .detailOrganizations:
            // A letter hangs on the line: the insurer's name after its label,
            // then where it comes again in the text, are covered; the letter's
            // red mark and the other lines stay.
            return SettingFilm("building.2.fill", FilmScene.line(cards: 0) + [
                .show(.pdf, Box(0.5, 0.52, 0.4, 0.62)),
                .show(.symbol("building.2.fill"), Box(0.21, 0.5432, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.415, 0.5432, 0.01, 0.0533), Box(0.5109, 0.5432, 0.2017, 0.0533), start: 0.8,
                      end: 1.35, appear: 0.75),
                .move(.cover, Box(0.465, 0.723, 0.01, 0.0533), Box(0.5358, 0.723, 0.1517, 0.0533), start: 1.5,
                      end: 2.05, appear: 1.45),
            ])
        case .detailBank:
            // A bank app hangs on the line: the number on the card, then the
            // IBAN under it, are covered; the card and the other lines stay.
            return SettingFilm("creditcard.fill", FilmScene.line(cards: 0) + [
                .show(.phone, Box(0.5, 0.52, 0.26, 0.62)),
                .show(.bubble(mine: true), Box(0.5, 0.39, 0.19, 0.19)),
                .show(.bubble(mine: false), Box(0.44, 0.34, 0.035, 0.05)),
                .show(.text(lines: 1), Box(0.5, 0.415, 0.15, 0.04)),
                .show(.text(lines: 1), Box(0.5, 0.56, 0.17, 0.045)),
                .show(.text(lines: 1), Box(0.48, 0.64, 0.13, 0.045)),
                .show(.symbol("creditcard.fill"), Box(0.28, 0.415, 0.1, 0.16), from: 0.3),
                .move(.cover,
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.5, 0.415, 0.15, 0.04), part: 0.05),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.5, 0.415, 0.15, 0.04)),
                      start: 0.8, end: 1.35, appear: 0.75),
                .move(.cover,
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.5, 0.56, 0.17, 0.045), part: 0.05),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.5, 0.56, 0.17, 0.045)),
                      start: 1.5, end: 2.05, appear: 1.45),
            ])
        case .detailAmounts:
            // A shop's checkout hangs on the line: the price after each thing,
            // then the total under the rule, is covered; the names of the
            // things stay.
            return SettingFilm("eurosign", FilmScene.line(cards: 0) + [
                .show(.window(.browser), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.text(lines: 1), Box(0.718, 0.4966, 0.055, 0.065)),
                .show(.text(lines: 1), Box(0.718, 0.6101, 0.055, 0.065)),
                .show(.text(lines: 1), Box(0.718, 0.7236, 0.055, 0.065)),
                .show(.line(.wire), Box(0.5, 0.667, 0.504, 0.02)),
                .show(.symbol("eurosign"), Box(0.11, 0.4966, 0.1, 0.16), from: 0.3),
                .move(.cover,
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.718, 0.4966, 0.055, 0.065), part: 0.05),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.718, 0.4966, 0.055, 0.065)),
                      start: 0.8, end: 1.2, appear: 0.75),
                .move(.cover,
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.718, 0.6101, 0.055, 0.065), part: 0.05),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.718, 0.6101, 0.055, 0.065)),
                      start: 1.3, end: 1.7, appear: 1.25),
                .move(.cover,
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.718, 0.7236, 0.055, 0.065), part: 0.05),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.718, 0.7236, 0.055, 0.065)),
                      start: 1.8, end: 2.2, appear: 1.75),
            ])
        case .detailHealth:
            // A sick note hangs on the line: what stands after the diagnosis
            // labels, then the medicine beside its pills, is covered; the
            // labels and the pills stay.
            return SettingFilm("heart.text.square.fill", FilmScene.line(cards: 0) + [
                .show(.window(.document), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.symbol("pills.fill"), Box(0.64, 0.7426, 0.08, 0.128)),
                .show(.symbol("heart.text.square.fill"), Box(0.11, 0.5155, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.355, 0.5155, 0.01, 0.0533), Box(0.4594, 0.5155, 0.2188, 0.0533), start: 0.8,
                      end: 1.2, appear: 0.75),
                .move(.cover, Box(0.355, 0.5912, 0.01, 0.0533), Box(0.5148, 0.5912, 0.3296, 0.0533), start: 1.3,
                      end: 1.7, appear: 1.25),
                .move(.cover, Box(0.355, 0.7426, 0.01, 0.0533), Box(0.4594, 0.7426, 0.2188, 0.0533), start: 1.8,
                      end: 2.2, appear: 1.75),
            ])
        case .detailIds:
            // An ID card hangs on the line: only its number row is covered; the
            // photo and the name stay.
            return SettingFilm("person.text.rectangle.fill", FilmScene.line(cards: 0) + [
                .show(.card(1), Box(0.5, 0.47, 0.52, 0.52)),
                .show(.symbol("person.crop.square.fill"), Box(0.69, 0.345, 0.09, 0.144)),
                .show(.text(lines: 1), Box(0.49, 0.655, 0.375, 0.065)),
                .show(.symbol("person.text.rectangle.fill"), Box(0.15, 0.655, 0.1, 0.16), from: 0.3),
                .move(.cover,
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.49, 0.655, 0.375, 0.065), part: 0.05),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.49, 0.655, 0.375, 0.065)),
                      start: 1.2, end: 2.0, appear: 1.15),
            ])
        case .detailBarcodes:
            // A ticket hangs on the line: its QR code, then its barcode with the
            // number under it, are covered whole; the event's name stays.
            return SettingFilm("qrcode", FilmScene.line(cards: 0) + [
                .show(.phone, Box(0.5, 0.52, 0.26, 0.62)),
                .show(.text(lines: 1), Box(0.5, 0.315, 0.15, 0.065)),
                .show(.symbol("qrcode"), Box(0.5, 0.44, 0.105, 0.168)),
                .show(.symbol("barcode"), Box(0.5, 0.625, 0.08, 0.128)),
                .show(.text(lines: 1), Box(0.5, 0.72, 0.1, 0.04)),
                .show(.symbol("qrcode"), Box(0.28, 0.44, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.448, 0.44, 0.01, 0.18), Box(0.5, 0.44, 0.115, 0.18), start: 0.8, end: 1.35,
                      appear: 0.75),
                .move(.cover, Box(0.448, 0.65, 0.01, 0.19), Box(0.5, 0.65, 0.115, 0.19), start: 1.5, end: 2.05,
                      appear: 1.45),
            ])
        case .detailOrders:
            // An order mail with a picture of what was bought hangs on the line:
            // the order number, then the customer number, at the ends of their
            // lines are covered; the labels and the picture stay.
            return SettingFilm("bag.fill", FilmScene.line(cards: 0) + [
                .show(.window(.mail), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.card(2), Box(0.69, 0.385, 0.09, 0.11)),
                .show(.symbol("bag.fill"), Box(0.11, 0.5221, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.626, 0.5221, 0.01, 0.0533), Box(0.6906, 0.5221, 0.1392, 0.0533), start: 0.8,
                      end: 1.35, appear: 0.75),
                .move(.cover, Box(0.5526, 0.5959, 0.01, 0.0533), Box(0.6136, 0.5959, 0.132, 0.0533), start: 1.5,
                      end: 2.05, appear: 1.45),
            ])
        case .detailTracking:
            // A parcel's status card hangs on the line, the parcel on its way
            // along the track below: a cover runs the whole length of its long
            // tracking number; the status under it stays.
            return SettingFilm("shippingbox.fill", FilmScene.line(cards: 0) + [
                .show(.card(0), Box(0.5, 0.47, 0.52, 0.52)),
                .show(.line(.wire), Box(0.49, 0.65, 0.37, 0.02)),
                .show(.symbol("shippingbox.fill"), Box(0.6, 0.65, 0.08, 0.128)),
                .show(.symbol("shippingbox.fill"), Box(0.15, 0.4544, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.3, 0.4544, 0.01, 0.07), Box(0.4896, 0.4544, 0.387, 0.07), start: 1.2, end: 2.0,
                      appear: 1.15),
            ])
        case .detailDates:
            // A letter hangs on the line: the date in its top corner, beside the
            // red letterhead, is covered; the letterhead and the text below stay.
            return SettingFilm("calendar.badge.clock", FilmScene.line(cards: 0) + [
                .show(.pdf, Box(0.5, 0.52, 0.4, 0.62)),
                .show(.text(lines: 1), Box(0.615, 0.3154, 0.13, 0.06)),
                .show(.symbol("calendar.badge.clock"), Box(0.21, 0.3154, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.5467, 0.3154, 0.01, 0.0519),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.615, 0.3154, 0.13, 0.06)),
                      start: 1.2, end: 2.0, appear: 1.15),
            ])
        case .detailLinks:
            // A web page hangs on the line: a link in its text, then the address
            // in its address bar, are covered; the rest of the page stays.
            return SettingFilm("link", FilmScene.line(cards: 0) + [
                .show(.window(.browser), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.text(lines: 1), Box(0.5, 0.2433, 0.16, 0.04)),
                .show(.symbol("link"), Box(0.11, 0.4966, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.405, 0.4966, 0.01, 0.0533), Box(0.5, 0.4966, 0.2, 0.0533), start: 0.8, end: 1.35,
                      appear: 0.75),
                .move(.cover, Box(0.4167, 0.2433, 0.01, 0.0435),
                      FilmScene.cover(line: 0, of: .text(lines: 1), at: Box(0.5, 0.2433, 0.16, 0.04)),
                      start: 1.5, end: 2.05, appear: 1.45),
            ])
        case .detailIpAddresses:
            // Network settings hang on the line: the two addresses at the end of
            // the first rows are covered; their labels and the last row stay.
            return SettingFilm("network", FilmScene.line(cards: 0) + [
                .show(.window(.settings), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.symbol("network"), Box(0.11, 0.402, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.405, 0.402, 0.01, 0.0533), Box(0.4794, 0.402, 0.1587, 0.0533), start: 0.8, end: 1.35,
                      appear: 0.75),
                .move(.cover, Box(0.345, 0.5533, 0.01, 0.0533), Box(0.4494, 0.5533, 0.2187, 0.0533), start: 1.5,
                      end: 2.05, appear: 1.45),
            ])
        case .detailCodes:
            // An iPhone's messages hang on the line: the sign-in code at the end
            // of the message is covered; the message and the reply stay.
            return SettingFilm("key.fill", FilmScene.line(cards: 0) + [
                .show(.phone, Box(0.5, 0.52, 0.26, 0.62)),
                .show(.bubble(mine: false), Box(0.49, 0.4, 0.18, 0.12)),
                .show(.bubble(mine: true), Box(0.545, 0.56, 0.1, 0.08)),
                .show(.text(lines: 1), Box(0.475, 0.4, 0.13, 0.04)),
                .show(.symbol("key.fill"), Box(0.28, 0.4, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.474, 0.4, 0.01, 0.0435), Box(0.509, 0.4, 0.078, 0.0435), start: 1.2, end: 2.0,
                      appear: 1.15),
            ])
        case .detailKeys:
            // Code hangs on the line: the key after the name on one line, and
            // the token after the word before it on another, are covered; the
            // names and the rest of the code stay.
            return SettingFilm("chevron.left.forwardslash.chevron.right", FilmScene.line(cards: 0) + [
                .show(.window(.document), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.symbol("chevron.left.forwardslash.chevron.right"), Box(0.11, 0.4398, 0.1, 0.16), from: 0.3),
                .move(.cover, Box(0.425, 0.4398, 0.01, 0.0533), Box(0.5499, 0.4398, 0.2597, 0.0533), start: 0.8, end: 1.35,
                      appear: 0.75),
                .move(.cover, Box(0.365, 0.6669, 0.01, 0.0533), Box(0.5602, 0.6669, 0.4003, 0.0533), start: 1.5, end: 2.05,
                      appear: 1.45),
            ])
        case .coverLook:
            // A screenshot hangs on the line, a detail at the start of a line of
            // its text covered in ink; the ink takes a label naming what it
            // hides, then turns to square pixel tiles drawn from the colours
            // around it. The rest of the line stays plain beside it.
            return SettingFilm("checkerboard.rectangle", FilmScene.line(cards: 0) + [
                .show(.card(1), Box(0.5, 0.47, 0.52, 0.52)),
                .show(.bubble(mine: false), Box(0.4061, 0.4544, 0.22, 0.07), from: 1.2),
                .show(.cover, Box(0.4061, 0.4544, 0.22, 0.07), to: 1.5),
                .show(.text(lines: 1), Box(0.4061, 0.4544, 0.12, 0.05), from: 0.7, to: 1.5),
                Part(kind: .cover, keys: [
                    SettingFilm.Key(1.5, Box(0.3181, 0.4544, 0.044, 0.07), opacity: 0),
                    SettingFilm.Key(1.7, Box(0.3181, 0.4544, 0.044, 0.07), opacity: 0.3),
                    SettingFilm.Key(2.2, Box(0.3181, 0.4544, 0.044, 0.07), opacity: 0.3),
                ]),
                Part(kind: .cover, keys: [
                    SettingFilm.Key(1.5, Box(0.3621, 0.4544, 0.044, 0.07), opacity: 0),
                    SettingFilm.Key(1.7, Box(0.3621, 0.4544, 0.044, 0.07), opacity: 0.48),
                    SettingFilm.Key(2.2, Box(0.3621, 0.4544, 0.044, 0.07), opacity: 0.48),
                ]),
                Part(kind: .cover, keys: [
                    SettingFilm.Key(1.5, Box(0.4061, 0.4544, 0.044, 0.07), opacity: 0),
                    SettingFilm.Key(1.7, Box(0.4061, 0.4544, 0.044, 0.07), opacity: 0.6),
                    SettingFilm.Key(2.2, Box(0.4061, 0.4544, 0.044, 0.07), opacity: 0.6),
                ]),
                Part(kind: .cover, keys: [
                    SettingFilm.Key(1.5, Box(0.4501, 0.4544, 0.044, 0.07), opacity: 0),
                    SettingFilm.Key(1.7, Box(0.4501, 0.4544, 0.044, 0.07), opacity: 0.44),
                    SettingFilm.Key(2.2, Box(0.4501, 0.4544, 0.044, 0.07), opacity: 0.44),
                ]),
                Part(kind: .cover, keys: [
                    SettingFilm.Key(1.5, Box(0.4941, 0.4544, 0.044, 0.07), opacity: 0),
                    SettingFilm.Key(1.7, Box(0.4941, 0.4544, 0.044, 0.07), opacity: 0.26),
                    SettingFilm.Key(2.2, Box(0.4941, 0.4544, 0.044, 0.07), opacity: 0.26),
                ]),
            ])
        case .keepTheLastFourDigits:
            // A bank card hangs on the line: its number, in four groups, is
            // covered whole, then the cover draws back from the end and leaves
            // the last group of four digits.
            return SettingFilm("creditcard.and.123", FilmScene.line(cards: 0) + [
                .show(.bubble(mine: true), Box(0.5, 0.47, 0.52, 0.52)),
                .show(.bubble(mine: false), Box(0.34, 0.33, 0.07, 0.09)),
                .show(.text(lines: 1), Box(0.335, 0.5, 0.08, 0.07)),
                .show(.text(lines: 1), Box(0.445, 0.5, 0.08, 0.07)),
                .show(.text(lines: 1), Box(0.555, 0.5, 0.08, 0.07)),
                .show(.text(lines: 1), Box(0.665, 0.5, 0.08, 0.07)),
                .show(.symbol("creditcard.and.123"), Box(0.15, 0.5, 0.1, 0.16), from: 0.3),
                // The cover grows over all four groups, then draws back to the
                // end of the third.
                Part(kind: .cover, keys: [
                    SettingFilm.Key(0.75, Box(0.2917, 0.5, 0.01, 0.0533), opacity: 0),
                    SettingFilm.Key(0.8, Box(0.2917, 0.5, 0.01, 0.0533)),
                    SettingFilm.Key(1.35, Box(0.5, 0.5, 0.4267, 0.0533)),
                    SettingFilm.Key(1.5, Box(0.5, 0.5, 0.4267, 0.0533)),
                    SettingFilm.Key(2.05, Box(0.445, 0.5, 0.3167, 0.0533)),
                ]),
            ])
        case .strongestProtection:
            // A letter hangs on the line: a name and a number are covered as usual, then each cover
            // stretches over its whole line, a little taller, while the lines between stay readable.
            return SettingFilm("shield.lefthalf.filled", FilmScene.line(cards: 0) + [
                .show(.window(.document), Box(0.5, 0.52, 0.6, 0.62)),
                Part(kind: .cover, keys: [
                    .init(0.45, Box(0.505, 0.4398, 0.01, 0.0533), opacity: 0),
                    .init(0.5, Box(0.505, 0.4398, 0.01, 0.0533)),
                    .init(0.95, Box(0.55, 0.4398, 0.1, 0.0533)),
                    .init(1.5, Box(0.55, 0.4398, 0.1, 0.0533)),
                    .init(2.0, Box(0.4597, 0.4398, 0.4634, 0.075)),
                ]),
                Part(kind: .cover, keys: [
                    .init(0.75, Box(0.565, 0.6669, 0.01, 0.0533), opacity: 0),
                    .init(0.8, Box(0.565, 0.6669, 0.01, 0.0533)),
                    .init(1.25, Box(0.62, 0.6669, 0.12, 0.0533)),
                    .init(1.7, Box(0.62, 0.6669, 0.12, 0.0533)),
                    .init(2.2, Box(0.5, 0.6669, 0.5441, 0.075)),
                ]),
                .show(.symbol("shield.lefthalf.filled"), Box(0.11, 0.5533, 0.1, 0.16), from: 1.25),
            ])
        case .findMoreWithAppleIntelligence:
            // A letter hangs on the line with its email and IBAN covered by the patterns; sparkles read down
            // it on the Mac itself, stop on a name in mid-sentence, and a cover lands on it.
            return SettingFilm("sparkles", FilmScene.line(cards: 0) + [
                .show(.window(.document), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.cover, Box(0.66, 0.3641, 0.17, 0.0533)),
                .show(.cover, Box(0.6, 0.6669, 0.28, 0.0533)),
                Part(kind: .symbol("sparkles"), keys: [
                    .init(0.2, Box(0.3, 0.3641, 0.09, 0.144), opacity: 0),
                    .init(0.4, Box(0.3, 0.3641, 0.09, 0.144)),
                    .init(0.85, Box(0.52, 0.4398, 0.09, 0.144)),
                    .init(1.3, Box(0.3, 0.5155, 0.09, 0.144)),
                    .init(1.7, Box(0.445, 0.5912, 0.09, 0.144)),
                    .init(1.85, Box(0.445, 0.5912, 0.09, 0.144)),
                    .init(2.4, Box(0.11, 0.5912, 0.1, 0.16)),
                ]),
                .move(.cover, Box(0.4, 0.5912, 0.01, 0.0533), Box(0.445, 0.5912, 0.1, 0.0533), start: 1.95, end: 2.35,
                      appear: 1.9),
            ])
        case .findMoreWithModel:
            // The same letter: its words fly off the Mac to the AI assistant, a find comes back to a
            // name in mid-sentence, and a cover lands on it.
            return SettingFilm("sparkle.magnifyingglass", FilmScene.line(cards: 0) + [
                .show(.window(.document), Box(0.5, 0.52, 0.6, 0.62)),
                .show(.cover, Box(0.66, 0.3641, 0.17, 0.0533)),
                .show(.cover, Box(0.6, 0.6669, 0.28, 0.0533)),
                .show(.symbol("cloud.fill"), Box(0.9, 0.42, 0.1, 0.16), from: 0.2),
                .move(.bubble(mine: true), Box(0.45, 0.515, 0.14, 0.07), Box(0.9, 0.42, 0.05, 0.03), start: 0.6,
                      end: 1.2, appear: 0.4, leave: 1.25),
                .move(.outline, Box(0.9, 0.42, 0.08, 0.05), Box(0.445, 0.5912, 0.12, 0.07), start: 1.65, end: 2.15,
                      appear: 1.55, leave: 2.6),
                .move(.cover, Box(0.4, 0.5912, 0.01, 0.0533), Box(0.445, 0.5912, 0.1, 0.0533), start: 2.25, end: 2.6,
                      appear: 2.2),
            ])
        case .coverEverythingInAIChats:
            // An AI chat is in front, so Snapfly's send button over it leads with a lock; a plain photo
            // is dragged from the line into the chat, and the copy that lands there has every line covered.
            return SettingFilm("lock.fill", FilmScene.line(cards: 0) + [
                .show(.card(1), FilmScene.slot(1), angle: FilmScene.tilt(1)),
                .show(.window(.chat), Box(0.5, 0.685, 0.64, 0.59)),
                .show(.symbol("sparkles"), Box(0.79, 0.42, 0.09, 0.144)),
                .show(.bubble(mine: false), Box(0.705, 0.761, 0.15, 0.14)),
                .show(.symbol("lock.fill"), Box(0.66, 0.761, 0.06, 0.096), from: 0.3),
                .show(.symbol("paperplane.fill"), Box(0.735, 0.761, 0.085, 0.136)),
                .move(.card(1), FilmScene.slot(1), Box(0.42, 0.72, 0.17, 0.2), start: 1.0, end: 2.0, appear: 0.8,
                      angles: (FilmScene.tilt(1), 0)),
                Part(kind: .card(1, covered: true), keys: [
                    .init(2.0, Box(0.42, 0.72, 0.17, 0.2), opacity: 0),
                    .init(2.15, Box(0.42, 0.72, 0.17, 0.2)),
                    .init(2.55, Box(0.42, 0.72, 0.17, 0.2)),
                ]),
                Part(kind: .cursor, keys: [
                    .init(0.4, Box(0.52, 0.31, 0.05, 0.08), opacity: 0),
                    .init(0.55, Box(0.52, 0.31, 0.05, 0.08)),
                    .init(1.0, Box(0.52, 0.31, 0.05, 0.08)),
                    .init(2.0, Box(0.444, 0.738, 0.05, 0.08)),
                    .init(2.1, Box(0.444, 0.738, 0.05, 0.08)),
                    .init(2.3, Box(0.444, 0.738, 0.05, 0.08), opacity: 0),
                ]),
            ])
        case .checkBeforeSending:
            // A click on Snapfly's send button over a chat: before anything goes, a card comes up with
            // the photo covered as it will go; Return is pressed, and the covered photo goes into the chat.
            return SettingFilm("checkmark.shield", FilmScene.line(cards: 0) + [
                .show(.card(0), FilmScene.slot(0), angle: FilmScene.tilt(0)),
                .show(.window(.chat), Box(0.66, 0.68, 0.6, 0.6)),
                .show(.bubble(mine: false), Box(0.847, 0.757, 0.15, 0.14)),
                .show(.symbol("paperplane.fill"), Box(0.877, 0.757, 0.085, 0.136)),
                Part(kind: .cursor, keys: [
                    .init(0.2, Box(0.6, 0.78, 0.05, 0.08), opacity: 0),
                    .init(0.35, Box(0.6, 0.78, 0.05, 0.08)),
                    .init(0.7, Box(0.88, 0.767, 0.05, 0.08)),
                    .init(0.9, Box(0.88, 0.767, 0.05, 0.08)),
                    .init(1.1, Box(0.88, 0.767, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.877, 0.757, at: 0.8),
                Part(kind: .bubble(mine: false), keys: [
                    .init(0.9, Box(0.19, 0.64, 0.1, 0.12), opacity: 0),
                    .init(1.25, Box(0.19, 0.64, 0.3, 0.46)),
                    .init(2.1, Box(0.19, 0.64, 0.3, 0.46)),
                    .init(2.3, Box(0.19, 0.64, 0.3, 0.46), opacity: 0),
                ]),
                Part(kind: .card(0, covered: true), keys: [
                    .init(0.9, FilmScene.slot(0), opacity: 0, angle: FilmScene.tilt(0)),
                    .init(1.0, FilmScene.slot(0), angle: FilmScene.tilt(0)),
                    .init(1.4, Box(0.19, 0.58, 0.2, 0.24)),
                    .init(2.1, Box(0.19, 0.58, 0.2, 0.24)),
                    .init(2.5, Box(0.458, FilmScene.chat(.messageBox, in: Box(0.66, 0.68, 0.6, 0.6)).y, 0.07, 0.09)),
                ]),
                Part(kind: .key("↩"), keys: [
                    .init(1.4, Box(0.19, 0.79, 0.07, 0.11), opacity: 0),
                    .init(1.6, Box(0.19, 0.79, 0.07, 0.11)),
                    .init(1.9, Box(0.19, 0.79, 0.07, 0.11)),
                    .init(1.95, Box(0.19, 0.79, 0.063, 0.099)),
                    .init(2.05, Box(0.19, 0.79, 0.07, 0.11)),
                    .init(2.1, Box(0.19, 0.79, 0.07, 0.11)),
                    .init(2.3, Box(0.19, 0.79, 0.07, 0.11), opacity: 0),
                ]),
            ])
        case .plainFileNames:
            // A photo dragged off the line lands on the desktop as a file: its long name, with the time
            // in it, shortens to a plain one that just says it is a picture.
            return SettingFilm("doc.plaintext", FilmScene.line(cards: 2) + [
                .move(.card(1), FilmScene.slot(1), Box(0.32, 0.5, 0.16, 0.2), start: 0.7, end: 1.4, appear: 0.5,
                      angles: (FilmScene.tilt(1), 0)),
                Part(kind: .cursor, keys: [
                    .init(0.3, Box(0.52, 0.31, 0.05, 0.08), opacity: 0),
                    .init(0.45, Box(0.52, 0.31, 0.05, 0.08)),
                    .init(0.7, Box(0.52, 0.31, 0.05, 0.08)),
                    .init(1.4, Box(0.343, 0.518, 0.05, 0.08)),
                    .init(1.5, Box(0.343, 0.518, 0.05, 0.08)),
                    .init(1.7, Box(0.343, 0.518, 0.05, 0.08), opacity: 0),
                ]),
                Part(kind: .text(lines: 1), keys: [
                    .init(1.4, Box(0.36, 0.67, 0.22, 0.06), opacity: 0),
                    .init(1.6, Box(0.36, 0.67, 0.22, 0.06)),
                    .init(1.9, Box(0.36, 0.67, 0.22, 0.06)),
                    .init(2.25, Box(0.36, 0.67, 0.08, 0.06)),
                ]),
                Part(kind: .symbol("clock"), keys: [
                    .init(1.4, Box(0.475, 0.67, 0.09, 0.144), opacity: 0),
                    .init(1.6, Box(0.475, 0.67, 0.09, 0.144)),
                    .init(1.9, Box(0.475, 0.67, 0.09, 0.144)),
                    .init(2.15, Box(0.42, 0.67, 0.09, 0.144), opacity: 0),
                ]),
                .show(.symbol("photo"), Box(0.275, 0.67, 0.09, 0.144), from: 2.15),
            ])
        case .coverWhatLandsInAFolder:
            // A picture lands in the watched folder; a copy slides to the other folder, covered on its
            // way, and a note shows above the Dock.
            return SettingFilm("lock.doc.fill", [FilmScene.desktop, FilmScene.menuBar,
                FilmScene.dock,
                .show(.folder, Box(0.25, 0.52, 0.2, 0.25)),
                .show(.folder, Box(0.75, 0.52, 0.2, 0.25)),
                .show(.symbol("eye.fill"), Box(0.37, 0.39, 0.09, 0.144), from: 0.1),
                .move(.card(2), Box(0.25, 0.17, 0.12, 0.15), Box(0.25, 0.56, 0.1, 0.125), start: 0.4, end: 0.9,
                      appear: 0.2),
                .move(.card(2), Box(0.25, 0.56, 0.1, 0.125), Box(0.75, 0.56, 0.1, 0.125), start: 1.1, end: 2.0,
                      appear: 1.0),
                Part(kind: .card(2, covered: true), keys: [
                    .init(1.1, Box(0.25, 0.56, 0.1, 0.125), opacity: 0),
                    .init(2.0, Box(0.75, 0.56, 0.1, 0.125)),
                ]),
                .show(.note, Box(0.5, 0.82, 0.3, 0.07), from: 2.15),
            ])
        case .testOnASample:
            // A click on the button: a made-up order slides in, covers land on its order number, name,
            // IBAN and a last line one after another, and a check with a short list shows beside it.
            return SettingFilm("testtube.2", [FilmScene.desktop, FilmScene.menuBar,
                .show(.bubble(mine: false), Box(0.8, 0.84, 0.2, 0.08)),
                Part(kind: .cursor, keys: [
                    .init(0.2, Box(0.62, 0.9, 0.05, 0.08), opacity: 0),
                    .init(0.35, Box(0.62, 0.9, 0.05, 0.08)),
                    .init(0.7, Box(0.81, 0.85, 0.05, 0.08)),
                    .init(0.9, Box(0.81, 0.85, 0.05, 0.08)),
                    .init(1.1, Box(0.81, 0.85, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.81, 0.84, at: 0.8),
                .move(.window(.document), Box(0.4, 1.2, 0.52, 0.7), Box(0.4, 0.54, 0.52, 0.7), start: 0.9, end: 1.4,
                      appear: 0.85),
                .move(.cover, Box(0.46, 0.3561, 0.01, 0.0533), Box(0.5408, 0.3561, 0.1717, 0.0533), start: 1.55,
                      end: 1.8, appear: 1.5),
                .move(.cover, Box(0.305, 0.443, 0.01, 0.0533), Box(0.375, 0.443, 0.15, 0.0533), start: 1.8,
                      end: 2.05, appear: 1.75),
                .move(.cover, Box(0.265, 0.6168, 0.01, 0.0533), Box(0.4084, 0.6168, 0.2968, 0.0533), start: 2.05,
                      end: 2.3, appear: 2.0),
                .move(.cover, Box(0.178, 0.7906, 0.01, 0.0533),
                      FilmScene.cover(line: 5, of: .window(.document), at: Box(0.4, 0.54, 0.52, 0.7), part: 0.6),
                      start: 2.3, end: 2.5, appear: 2.25),
                .show(.symbol("checkmark.circle.fill"), Box(0.8, 0.36, 0.1, 0.16), from: 2.6),
                .show(.text(lines: 3), Box(0.8, 0.56, 0.2, 0.16), from: 2.6),
            ])
        case .bookkeepingFolder:
            // A covered receipt hangs on the line; a click on it and Save for
            // Bookkeeping drop a copy into the folder, the table beside it gains
            // a row, and the note says it is saved.
            return SettingFilm("archivebox.fill", FilmScene.line(cards: 0) + [
                .show(.card(0, covered: true), FilmScene.slot(0, of: 1), angle: FilmScene.tilt(0)),
                Part(kind: .card(0, covered: true), keys: [
                    .init(1.0, FilmScene.slot(0, of: 1), opacity: 0, angle: FilmScene.tilt(0)),
                    .init(1.05, FilmScene.slot(0, of: 1), angle: FilmScene.tilt(0)),
                    .init(1.5, Box(0.22, 0.52, 0.11, 0.13)),
                    .init(1.7, Box(0.22, 0.6, 0.07, 0.085), opacity: 0),
                ]),
                .show(.folder, Box(0.22, 0.6, 0.18, 0.25)),
                Part(kind: .window(.document), keys: [
                    .init(0, Box(0.69, 0.585, 0.3, 0.31)),
                    .init(1.75, Box(0.69, 0.585, 0.3, 0.31)),
                    .init(2.15, Box(0.69, 0.6, 0.3, 0.36)),
                ]),
                .show(.symbol("tablecells"), Box(0.84, 0.45, 0.09, 0.144)),
                .move(.outline, Box(0.567, 0.7302, 0.01, 0.05), Box(0.69, 0.7302, 0.256, 0.05), start: 2.05, end: 2.45,
                      appear: 2.0),
                Part(kind: .cursor, keys: [
                    .init(0.15, Box(0.85, 0.95, 0.05, 0.08), opacity: 0),
                    .init(0.3, Box(0.85, 0.95, 0.05, 0.08)),
                    .init(0.65, Box(0.53, 0.33, 0.05, 0.08)),
                    .init(0.95, Box(0.53, 0.33, 0.05, 0.08)),
                    .init(1.15, Box(0.53, 0.33, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.53, 0.32, at: 0.8),
                // The menu item, Save for Bookkeeping.
                Part(kind: .symbol("folder.badge.plus"), keys: [
                    .init(0.85, Box(0.62, 0.32, 0.08, 0.128), opacity: 0),
                    .init(1.05, Box(0.62, 0.32, 0.08, 0.128)),
                    .init(1.25, Box(0.62, 0.32, 0.08, 0.128), opacity: 0),
                ]),
                .show(.note, Box(0.5, 0.82, 0.3, 0.07), from: 2.5),
            ])
        case .monthlyPack:
            // A month is chosen; the covered receipts come out of the folder one
            // by one into a PDF, whose pages then fan out behind its first page.
            return SettingFilm("doc.richtext", [FilmScene.desktop, FilmScene.menuBar,
                .show(.symbol("calendar"), Box(0.24, 0.28, 0.1, 0.16), from: 0.15),
                .move(.pdf, Box(0.68, 0.56, 0.26, 0.58), Box(0.76, 0.6, 0.26, 0.58), start: 2.0, end: 2.5,
                      appear: 0.45, angles: (0, 7)),
                .move(.pdf, Box(0.68, 0.56, 0.26, 0.58), Box(0.72, 0.58, 0.26, 0.58), start: 2.0, end: 2.5,
                      appear: 0.45, angles: (0, 3.5)),
                .show(.pdf, Box(0.68, 0.56, 0.26, 0.58), from: 0.45),
                Part(kind: .card(0, covered: true), keys: [
                    .init(0.6, Box(0.24, 0.64, 0.1, 0.12), opacity: 0),
                    .init(0.8, Box(0.24, 0.5, 0.14, 0.17)),
                    .init(1.2, Box(0.68, 0.56, 0.16, 0.2)),
                    .init(1.35, Box(0.68, 0.56, 0.16, 0.2), opacity: 0),
                ]),
                Part(kind: .card(1, covered: true), keys: [
                    .init(0.9, Box(0.24, 0.64, 0.1, 0.12), opacity: 0),
                    .init(1.1, Box(0.24, 0.5, 0.14, 0.17)),
                    .init(1.5, Box(0.68, 0.56, 0.16, 0.2)),
                    .init(1.65, Box(0.68, 0.56, 0.16, 0.2), opacity: 0),
                ]),
                Part(kind: .card(2, covered: true), keys: [
                    .init(1.2, Box(0.24, 0.64, 0.1, 0.12), opacity: 0),
                    .init(1.4, Box(0.24, 0.5, 0.14, 0.17)),
                    .init(1.8, Box(0.68, 0.56, 0.16, 0.2)),
                    .init(1.95, Box(0.68, 0.56, 0.16, 0.2), opacity: 0),
                ]),
                .show(.folder, Box(0.24, 0.66, 0.2, 0.28)),
                Part(kind: .cursor, keys: [
                    .init(0.0, Box(0.42, 0.55, 0.05, 0.08), opacity: 0),
                    .init(0.12, Box(0.42, 0.55, 0.05, 0.08)),
                    .init(0.35, Box(0.25, 0.31, 0.05, 0.08)),
                    .init(0.6, Box(0.25, 0.31, 0.05, 0.08)),
                    .init(0.8, Box(0.25, 0.31, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.25, 0.3, at: 0.4),
            ])
        case .shopLogo:
            // A square picture comes out of a folder and lands in the empty
            // place at the start of the shop's white band over a covered
            // screenshot; the name moves aside for it.
            return SettingFilm("storefront.fill", [FilmScene.desktop, FilmScene.menuBar,
                // The picture that leaves: the band is the empty top of its
                // white page, the screenshot laid over the rest of it, with a
                // thin grey line between them.
                .show(.card(2), Box(0.62, 0.69, 0.44, 0.94)),
                .show(.card(1, covered: true), Box(0.62, 0.7, 0.44, 0.67)),
                .show(.text(lines: 1), Box(0.62, 0.365, 0.44, 0.01)),
                .move(.text(lines: 2), Box(0.6, 0.2925, 0.3, 0.075), Box(0.665, 0.2925, 0.3, 0.075), start: 1.7,
                      end: 2.25, appear: 0),
                Part(kind: .bubble(mine: true), keys: [
                    .init(0.95, Box(0.17, 0.66, 0.08, 0.128), opacity: 0),
                    .init(1.0, Box(0.17, 0.66, 0.08, 0.128)),
                    .init(1.35, Box(0.17, 0.42, 0.13, 0.208)),
                    .init(1.6, Box(0.17, 0.42, 0.13, 0.208)),
                    .init(2.25, Box(0.452, 0.2925, 0.07, 0.112)),
                ]),
                .show(.folder, Box(0.17, 0.68, 0.16, 0.22)),
                Part(kind: .cursor, keys: [
                    .init(0.2, Box(0.4, 0.95, 0.05, 0.08), opacity: 0),
                    .init(0.35, Box(0.4, 0.95, 0.05, 0.08)),
                    .init(0.7, Box(0.18, 0.71, 0.05, 0.08)),
                    .init(0.95, Box(0.18, 0.71, 0.05, 0.08)),
                    .init(1.15, Box(0.18, 0.71, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.18, 0.7, at: 0.85),
            ])
        case .numbersBesideTheSendButton:
            // Over an AI chat, the numbers 1 and 2 rise just above Snapfly's
            // send button; a click on 2 puts the photo, covered, into the message
            // box with the prompt after it, waiting for Return, and the button
            // and its numbers go, as nothing is left to send.
            return SettingFilm("1.circle.fill", [FilmScene.desktop, FilmScene.menuBar,
                .show(.window(.chat), Box(0.5, 0.685, 0.64, 0.59)),
                .show(.symbol("sparkles"), Box(0.79, 0.42, 0.09, 0.144)),
                .show(.bubble(mine: false), Box(0.655, 0.761, 0.24, 0.14), to: 2.0),
                .move(.card(0, covered: true), Box(0.585, 0.761, 0.065, 0.095),
                      Box(0.3, FilmScene.chat(.messageBox, in: Box(0.5, 0.685, 0.64, 0.59)).y, 0.07, 0.09),
                      start: 1.5, end: 2.0, appear: 0),
                .show(.symbol("paperplane.fill"), Box(0.735, 0.761, 0.085, 0.136), to: 2.0),
                Part(kind: .key("1"), keys: [
                    .init(0.3, Box(0.69, 0.655, 0.07, 0.11), opacity: 0),
                    .init(0.6, Box(0.69, 0.615, 0.07, 0.11)),
                    .init(2.0, Box(0.69, 0.615, 0.07, 0.11)),
                    .init(2.2, Box(0.69, 0.615, 0.07, 0.11), opacity: 0),
                ]),
                // Clicked: it gives a little.
                Part(kind: .key("2"), keys: [
                    .init(0.4, Box(0.775, 0.655, 0.07, 0.11), opacity: 0),
                    .init(0.7, Box(0.775, 0.615, 0.07, 0.11)),
                    .init(1.3, Box(0.775, 0.615, 0.07, 0.11)),
                    .init(1.35, Box(0.775, 0.615, 0.063, 0.099)),
                    .init(1.45, Box(0.775, 0.615, 0.063, 0.099)),
                    .init(1.5, Box(0.775, 0.615, 0.07, 0.11)),
                    .init(2.0, Box(0.775, 0.615, 0.07, 0.11)),
                    .init(2.2, Box(0.775, 0.615, 0.07, 0.11), opacity: 0),
                ]),
                Part(kind: .cursor, keys: [
                    .init(0.85, Box(0.97, 0.45, 0.05, 0.08), opacity: 0),
                    .init(1.0, Box(0.97, 0.45, 0.05, 0.08)),
                    .init(1.2, Box(0.78, 0.625, 0.05, 0.08)),
                    .init(1.4, Box(0.78, 0.625, 0.05, 0.08)),
                    .init(1.6, Box(0.78, 0.625, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.775, 0.615, at: 1.3),
                // The prompt, written after the photo.
                .move(.text(lines: 1),
                      Box(0.345, FilmScene.chat(.messageBox, in: Box(0.5, 0.685, 0.64, 0.59)).y, 0.01, 0.04),
                      Box(0.44, FilmScene.chat(.messageBox, in: Box(0.5, 0.685, 0.64, 0.59)).y, 0.2, 0.04),
                      start: 2.0, end: 2.45, appear: 1.95),
            ])
        case .assistant:
            // Two assistant tiles; the pointer goes to the other one and clicks,
            // and the accent edge and the checkmark move over to it.
            return SettingFilm("brain.head.profile", [FilmScene.desktop, FilmScene.menuBar,
                .show(.bubble(mine: false), Box(0.32, 0.56, 0.3, 0.52)),
                .show(.bubble(mine: false), Box(0.68, 0.56, 0.3, 0.52)),
                .show(.symbol("sparkle"), Box(0.32, 0.53, 0.14, 0.224)),
                .show(.symbol("hexagon.fill"), Box(0.68, 0.53, 0.14, 0.224)),
                .move(.outline, Box(0.32, 0.56, 0.32, 0.56), Box(0.68, 0.56, 0.32, 0.56), start: 1.6, end: 2.2,
                      appear: 0),
                .move(.symbol("checkmark"), Box(0.44, 0.35, 0.09, 0.144), Box(0.8, 0.35, 0.09, 0.144), start: 1.6,
                      end: 2.2, appear: 0),
                Part(kind: .cursor, keys: [
                    .init(0.3, Box(0.3, 0.95, 0.05, 0.08), opacity: 0),
                    .init(0.45, Box(0.3, 0.95, 0.05, 0.08)),
                    .init(1.2, Box(0.7, 0.65, 0.05, 0.08)),
                    .init(1.55, Box(0.7, 0.65, 0.05, 0.08)),
                    .init(1.75, Box(0.7, 0.65, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.7, 0.64, at: 1.45),
            ])
        case .assistantModel:
            // Three models of falling size: the largest chosen writes its
            // answer slowly; the smallest chosen writes the same answer quickly.
            return SettingFilm("cpu", [FilmScene.desktop, FilmScene.menuBar,
                .show(.symbol("sparkle"), Box(0.2, 0.3, 0.14, 0.224)),
                .show(.symbol("sparkle"), Box(0.37, 0.33, 0.1, 0.16)),
                .show(.symbol("sparkle"), Box(0.51, 0.355, 0.07, 0.112)),
                .move(.outline, Box(0.2, 0.3, 0.17, 0.27), Box(0.51, 0.355, 0.1, 0.16), start: 2.05, end: 2.3,
                      appear: 0.85),
                Part(kind: .cursor, keys: [
                    .init(0.1, Box(0.85, 0.95, 0.05, 0.08), opacity: 0),
                    .init(0.25, Box(0.85, 0.95, 0.05, 0.08)),
                    .init(0.7, Box(0.21, 0.33, 0.05, 0.08)),
                    .init(0.9, Box(0.21, 0.33, 0.05, 0.08)),
                    // It waits clear of the badges and of the growing answer.
                    .init(1.35, Box(0.66, 0.44, 0.05, 0.08)),
                    .init(1.6, Box(0.66, 0.44, 0.05, 0.08)),
                    .init(1.9, Box(0.52, 0.38, 0.05, 0.08)),
                    .init(2.1, Box(0.52, 0.38, 0.05, 0.08)),
                    .init(2.3, Box(0.52, 0.38, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.21, 0.32, at: 0.8),
                .click(0.52, 0.37, at: 2.0),
                // The large model's answer, written over a second.
                Part(kind: .bubble(mine: false), keys: [
                    .init(0.9, Box(0.2, 0.47, 0.04, 0.04), opacity: 0),
                    .init(0.95, Box(0.2, 0.47, 0.04, 0.04)),
                    .init(1.9, Box(0.47, 0.71, 0.6, 0.34)),
                    .init(2.05, Box(0.47, 0.71, 0.6, 0.34)),
                    .init(2.2, Box(0.47, 0.71, 0.6, 0.34), opacity: 0),
                ]),
                // The small model's answer, the same size, written in a moment.
                Part(kind: .bubble(mine: false), keys: [
                    .init(2.25, Box(0.51, 0.43, 0.04, 0.04), opacity: 0),
                    .init(2.3, Box(0.51, 0.43, 0.04, 0.04)),
                    .init(2.6, Box(0.47, 0.71, 0.6, 0.34)),
                ]),
                // The answer's lines, grown with each bubble.
                Part(kind: .text(lines: 3), keys: [
                    .init(0.9, Box(0.2, 0.47, 0.03, 0.02), opacity: 0),
                    .init(0.95, Box(0.2, 0.47, 0.03, 0.02)),
                    .init(1.9, Box(0.47, 0.71, 0.5, 0.22)),
                    .init(2.05, Box(0.47, 0.71, 0.5, 0.22)),
                    .init(2.2, Box(0.47, 0.71, 0.5, 0.22), opacity: 0),
                    .init(2.25, Box(0.51, 0.43, 0.03, 0.02), opacity: 0),
                    .init(2.3, Box(0.51, 0.43, 0.03, 0.02)),
                    .init(2.6, Box(0.47, 0.71, 0.5, 0.22)),
                ]),
            ])
        case .writeAReply:
            // A click on a customer's message on the line and Write a Reply: the
            // reply is written beside it, and a click on it puts it in the
            // chat's message box.
            return SettingFilm("arrowshape.turn.up.left.fill", FilmScene.line(cards: 0) + [
                .show(.card(0, covered: true), FilmScene.slot(2), angle: FilmScene.tilt(2)),
                .show(.window(.chat), Box(0.36, 0.66, 0.56, 0.6)),
                // The menu item, Write a Reply.
                Part(kind: .symbol("arrowshape.turn.up.left"), keys: [
                    .init(0.8, Box(0.655, 0.3, 0.08, 0.128), opacity: 0),
                    .init(1.0, Box(0.655, 0.3, 0.08, 0.128)),
                    .init(1.2, Box(0.655, 0.3, 0.08, 0.128), opacity: 0),
                ]),
                Part(kind: .bubble(mine: true), keys: [
                    .init(1.1, Box(0.8, 0.42, 0.04, 0.04), opacity: 0),
                    .init(1.15, Box(0.8, 0.42, 0.04, 0.04)),
                    .init(1.45, Box(0.8, 0.6, 0.24, 0.28)),
                    .init(2.15, Box(0.8, 0.6, 0.24, 0.28)),
                    .init(2.6, Box(0.36, FilmScene.chat(.messageBox, in: Box(0.36, 0.66, 0.56, 0.6)).y, 0.3, 0.06)),
                    .init(2.7, Box(0.36, FilmScene.chat(.messageBox, in: Box(0.36, 0.66, 0.56, 0.6)).y, 0.3, 0.06),
                          opacity: 0),
                ]),
                // The reply's lines, written from the left, then going with it
                // into the message box.
                Part(kind: .text(lines: 3), keys: [
                    .init(1.35, Box(0.715, 0.6, 0.01, 0.18), opacity: 0),
                    .init(1.4, Box(0.715, 0.6, 0.01, 0.18)),
                    .init(1.9, Box(0.8, 0.6, 0.18, 0.18)),
                    .init(2.15, Box(0.8, 0.6, 0.18, 0.18)),
                    .init(2.6, Box(0.36, FilmScene.chat(.messageBox, in: Box(0.36, 0.66, 0.56, 0.6)).y, 0.3, 0.05)),
                ]),
                .show(.symbol("sparkles"), Box(0.71, 0.455, 0.09, 0.144), from: 1.05, to: 2.15),
                Part(kind: .cursor, keys: [
                    .init(0.1, Box(0.9, 0.72, 0.05, 0.08), opacity: 0),
                    .init(0.25, Box(0.9, 0.72, 0.05, 0.08)),
                    .init(0.65, Box(0.77, 0.31, 0.05, 0.08)),
                    .init(1.6, Box(0.77, 0.31, 0.05, 0.08)),
                    .init(2.0, Box(0.82, 0.63, 0.05, 0.08)),
                    .init(2.2, Box(0.82, 0.63, 0.05, 0.08)),
                    .init(2.4, Box(0.82, 0.63, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.77, 0.3, at: 0.75),
                .click(0.82, 0.62, at: 2.1),
            ])
        case .explainWith:
            // A click on a covered screenshot and Explain: the assistant's
            // answer about it is written in a bubble beside it.
            return SettingFilm("bubble.left.and.text.bubble.right.fill", FilmScene.line(cards: 0) + [
                .show(.card(1, covered: true), FilmScene.slot(0), angle: FilmScene.tilt(0)),
                // The menu item, Explain.
                Part(kind: .symbol("bubble.left.and.text.bubble.right"), keys: [
                    .init(0.8, Box(0.36, 0.3, 0.08, 0.128), opacity: 0),
                    .init(1.0, Box(0.36, 0.3, 0.08, 0.128)),
                    .init(1.2, Box(0.36, 0.3, 0.08, 0.128), opacity: 0),
                ]),
                .move(.bubble(mine: false), Box(0.46, 0.33, 0.04, 0.04), Box(0.66, 0.42, 0.42, 0.22), start: 1.2,
                      end: 1.6, appear: 1.15),
                .move(.text(lines: 3), Box(0.48, 0.42, 0.01, 0.14), Box(0.66, 0.42, 0.34, 0.14), start: 1.55, end: 2.1,
                      appear: 1.5),
                .show(.symbol("sparkles"), Box(0.4, 0.33, 0.09, 0.144), from: 1.15),
                Part(kind: .cursor, keys: [
                    .init(0.15, Box(0.5, 0.95, 0.05, 0.08), opacity: 0),
                    .init(0.3, Box(0.5, 0.95, 0.05, 0.08)),
                    .init(0.65, Box(0.25, 0.31, 0.05, 0.08)),
                    .init(0.85, Box(0.25, 0.31, 0.05, 0.08)),
                    .init(1.05, Box(0.25, 0.31, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.25, 0.3, at: 0.75),
            ])
        case .orderDetails:
            // A click on the order hanging on the line, then Order Details from its menu: the number and
            // the total come off the card into rows, each with its kind, and the assistant's row slides in.
            return SettingFilm("list.bullet.rectangle", FilmScene.line(cards: 0) + [
                .show(.card(2), FilmScene.slot(1), angle: FilmScene.tilt(1)),
                .move(.text(lines: 1), Box(0.497, 0.29, 0.1, 0.02), Box(0.55, 0.47, 0.3, 0.05), start: 0.7, end: 1.1,
                      appear: 0.6, angles: (FilmScene.tilt(1), 0)),
                .show(.symbol("number"), Box(0.3, 0.47, 0.09, 0.144), from: 1.0),
                .move(.text(lines: 1), Box(0.482, 0.324, 0.07, 0.02), Box(0.54, 0.64, 0.28, 0.05), start: 1.0,
                      end: 1.5, appear: 0.9, angles: (FilmScene.tilt(1), 0)),
                .show(.symbol("banknote"), Box(0.3, 0.64, 0.09, 0.144), from: 1.4),
                .move(.symbol("sparkles"), Box(1.06, 0.81, 0.09, 0.144), Box(0.3, 0.81, 0.09, 0.144), start: 1.8,
                      end: 2.4),
                .move(.text(lines: 1), Box(1.25, 0.81, 0.26, 0.05), Box(0.53, 0.81, 0.26, 0.05), start: 1.8, end: 2.4),
                Part(kind: .symbol("list.bullet.rectangle"), keys: [
                    .init(0.6, Box(0.62, 0.3, 0.08, 0.128), opacity: 0),
                    .init(0.8, Box(0.62, 0.3, 0.08, 0.128)),
                    .init(1.0, Box(0.62, 0.3, 0.08, 0.128), opacity: 0),
                ]),
                Part(kind: .cursor, keys: [
                    .init(0.05, Box(0.62, 0.9, 0.05, 0.08), opacity: 0),
                    .init(0.2, Box(0.62, 0.9, 0.05, 0.08)),
                    .init(0.5, Box(0.51, 0.31, 0.05, 0.08)),
                    .init(0.65, Box(0.51, 0.31, 0.05, 0.08)),
                    .init(0.85, Box(0.51, 0.31, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.5, 0.3, at: 0.55),
            ])
        case .keepScreenshotsInAWorkspaceFolder:
            // Turned on, a folder shows on the Desktop with a folder for each kind inside; a new
            // screenshot hangs on the line and, at the same moment, a copy goes into Unsorted, the last.
            return SettingFilm("square.grid.3x1.folder.fill.badge.plus",
                                                              FilmScene.line(cards: 2) + [
                .move(.card(2), Box(0.67, 0.49, 0.17, 0.21), Box(0.82, 0.65, 0.07, 0.09), start: 1.5, end: 2.2,
                      appear: 1.2),
                .move(.folder, Box(0.16, 0.66, 0.06, 0.08), Box(0.4, 0.72, 0.11, 0.14), start: 0.65, end: 1.1,
                      appear: 0.6),
                .move(.folder, Box(0.16, 0.66, 0.06, 0.08), Box(0.54, 0.72, 0.11, 0.14), start: 0.75, end: 1.2,
                      appear: 0.7),
                .move(.folder, Box(0.16, 0.66, 0.06, 0.08), Box(0.68, 0.72, 0.11, 0.14), start: 0.85, end: 1.3,
                      appear: 0.8),
                .move(.folder, Box(0.16, 0.66, 0.06, 0.08), Box(0.82, 0.72, 0.11, 0.14), start: 0.95, end: 1.4,
                      appear: 0.9),
                .move(.folder, Box(0.16, 0.66, 0.05, 0.065), Box(0.16, 0.66, 0.2, 0.26), start: 0.2, end: 0.6,
                      appear: 0.1),
                .move(.card(2), Box(0.67, 0.49, 0.17, 0.21), FilmScene.slot(2), start: 1.5, end: 2.2, appear: 1.2,
                      angles: (0, FilmScene.tilt(2))),
            ])
        case .workspaceFolder:
            // The workspace folder is dragged from the Desktop into a Finder window, where it shows
            // selected; the photos on the line stay as they are.
            return SettingFilm("mappin", FilmScene.line(cards: 2) + [
                .show(.window(.finder), Box(0.75, 0.685, 0.44, 0.57), from: 0.3),
                .move(.folder, Box(0.16, 0.66, 0.2, 0.26), Box(0.6114, 0.8789, 0.0739, 0.1183), start: 1.0, end: 1.8,
                      appear: 0),
                .show(.outline, Box(0.6114, 0.8789, 0.1, 0.15), from: 1.95),
                Part(kind: .cursor, keys: [
                    .init(0.4, Box(0.32, 0.92, 0.05, 0.08), opacity: 0),
                    .init(0.55, Box(0.32, 0.92, 0.05, 0.08)),
                    .init(0.9, Box(0.164, 0.668, 0.05, 0.08)),
                    .init(1.0, Box(0.164, 0.668, 0.05, 0.08)),
                    .init(1.8, Box(0.615, 0.888, 0.05, 0.08)),
                    .init(2.0, Box(0.615, 0.888, 0.05, 0.08)),
                    .init(2.2, Box(0.615, 0.888, 0.05, 0.08), opacity: 0),
                ]),
            ])
        case .newScreenshotsGoTo:
            // The highlight moves from the last folder, Unsorted, to the first; a new screenshot hangs
            // on the line and its copy goes into that first folder.
            return SettingFilm("tray.and.arrow.down.fill", FilmScene.line(cards: 2) + [
                .move(.card(2), Box(0.67, 0.49, 0.17, 0.21), Box(0.4, 0.65, 0.07, 0.09), start: 1.5, end: 2.2,
                      appear: 1.2),
                .show(.folder, Box(0.4, 0.72, 0.11, 0.14)),
                .show(.folder, Box(0.54, 0.72, 0.11, 0.14)),
                .show(.folder, Box(0.68, 0.72, 0.11, 0.14)),
                .show(.folder, Box(0.82, 0.72, 0.11, 0.14)),
                .move(.outline, Box(0.82, 0.715, 0.135, 0.19), Box(0.4, 0.715, 0.135, 0.19), start: 0.4, end: 1.0,
                      appear: 0),
                .move(.card(2), Box(0.67, 0.49, 0.17, 0.21), FilmScene.slot(2), start: 1.5, end: 2.2, appear: 1.2,
                      angles: (0, FilmScene.tilt(2))),
            ])
        case .orderAndVisibility:
            // Folders out of place, two of them faded; a click on restore puts them back in a row, all
            // shown again, and the highlight goes back to the last one, Unsorted.
            return SettingFilm("arrow.counterclockwise", [FilmScene.desktop, FilmScene.menuBar,
                .show(.folder, Box(0.16, 0.66, 0.2, 0.26)),
                .move(.folder, Box(0.5, 0.79, 0.11, 0.14), Box(0.4, 0.72, 0.11, 0.14), start: 1.1, end: 1.7,
                      appear: 0, angles: (-10, 0)),
                Part(kind: .folder, keys: [
                    .init(0, Box(0.85, 0.66, 0.11, 0.14), opacity: 0.3, angle: 8),
                    .init(1.1, Box(0.85, 0.66, 0.11, 0.14), opacity: 0.3, angle: 8),
                    .init(1.7, Box(0.54, 0.72, 0.11, 0.14)),
                ]),
                .move(.folder, Box(0.36, 0.86, 0.11, 0.14), Box(0.68, 0.72, 0.11, 0.14), start: 1.1, end: 1.7,
                      appear: 0, angles: (6, 0)),
                Part(kind: .folder, keys: [
                    .init(0, Box(0.68, 0.86, 0.11, 0.14), opacity: 0.3, angle: -6),
                    .init(1.1, Box(0.68, 0.86, 0.11, 0.14), opacity: 0.3, angle: -6),
                    .init(1.7, Box(0.82, 0.72, 0.11, 0.14)),
                ]),
                Part(kind: .outline, keys: [
                    .init(0, Box(0.5, 0.785, 0.135, 0.19), angle: -10),
                    .init(1.1, Box(0.5, 0.785, 0.135, 0.19), angle: -10),
                    .init(1.7, Box(0.4, 0.715, 0.135, 0.19)),
                    .init(1.8, Box(0.4, 0.715, 0.135, 0.19)),
                    .init(2.4, Box(0.82, 0.715, 0.135, 0.19)),
                ]),
                .show(.symbol("arrow.counterclockwise"), Box(0.6, 0.42, 0.09, 0.144)),
                Part(kind: .cursor, keys: [
                    .init(0.2, Box(0.3, 0.47, 0.05, 0.08), opacity: 0),
                    .init(0.35, Box(0.3, 0.47, 0.05, 0.08)),
                    .init(0.8, Box(0.6, 0.43, 0.05, 0.08)),
                    .init(1.0, Box(0.6, 0.43, 0.05, 0.08)),
                    .init(1.2, Box(0.6, 0.43, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.6, 0.42, at: 0.9),
            ])
        case .deleteTheWorkspace:
            // The workspace holds screenshots and a document of its own; after a question is answered,
            // the screenshots go to the Trash one by one and the document stays in the folder.
            return SettingFilm("trash.fill", [FilmScene.desktop, FilmScene.menuBar,
                Part(kind: .card(0), keys: [
                    .init(0, Box(0.11, 0.52, 0.1, 0.1), angle: -6),
                    .init(1.4, Box(0.11, 0.52, 0.1, 0.1), angle: -6),
                    .init(1.75, Box(0.5, 0.36, 0.1, 0.1), angle: 6),
                    .init(2.05, Box(0.84, 0.76, 0.05, 0.05), angle: 12),
                    .init(2.15, Box(0.84, 0.76, 0.05, 0.05), opacity: 0, angle: 12),
                ]),
                .show(.pdf, Box(0.19, 0.45, 0.07, 0.21)),
                Part(kind: .card(1), keys: [
                    .init(0, Box(0.27, 0.52, 0.1, 0.1), angle: 6),
                    .init(1.75, Box(0.27, 0.52, 0.1, 0.1), angle: 6),
                    .init(2.1, Box(0.58, 0.36, 0.1, 0.1), angle: 10),
                    .init(2.4, Box(0.84, 0.76, 0.05, 0.05), angle: 14),
                    .init(2.5, Box(0.84, 0.76, 0.05, 0.05), opacity: 0, angle: 14),
                ]),
                .show(.folder, Box(0.16, 0.66, 0.2, 0.26)),
                .show(.symbol("trash.fill"), Box(0.84, 0.8, 0.09, 0.144)),
                .move(.bubble(mine: false), Box(0.6, 0.3, 0.34, 0.26), Box(0.6, 0.42, 0.34, 0.26), start: 0.3, end: 0.6,
                      appear: 0.15, leave: 1.2),
                .move(.bubble(mine: true), Box(0.68, 0.38, 0.12, 0.06), Box(0.68, 0.5, 0.12, 0.06), start: 0.3, end: 0.6,
                      appear: 0.15, leave: 1.2),
                Part(kind: .cursor, keys: [
                    .init(0.5, Box(0.5, 0.9, 0.05, 0.08), opacity: 0),
                    .init(0.65, Box(0.5, 0.9, 0.05, 0.08)),
                    .init(1.0, Box(0.68, 0.51, 0.05, 0.08)),
                    .init(1.15, Box(0.68, 0.51, 0.05, 0.08)),
                    .init(1.35, Box(0.68, 0.51, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.68, 0.5, at: 1.05),
            ])
        case .syncWithYourIPhone:
            // A copy of the screenshot on the line is covered on its way to the
            // iPhone; then a screenshot tapped on the iPhone flies back and hangs
            // on the line beside it.
            return SettingFilm("laptopcomputer.and.iphone", FilmScene.line(cards: 1) + [
                .show(.phone, Box(0.82, 0.655, 0.22, 0.58)),
                .move(.card(0), FilmScene.slot(0), Box(0.52, 0.5, 0.14, 0.17), start: 0.5, end: 1.0, appear: 0.3,
                      leave: 1.05, angles: (FilmScene.tilt(0), 0)),
                .move(.card(0, covered: true), Box(0.52, 0.5, 0.14, 0.17), Box(0.82, 0.73, 0.13, 0.155),
                      start: 1.3, end: 1.8, appear: 1.0),
                .show(.card(2, covered: true), Box(0.82, 0.52, 0.13, 0.155), from: 1.95),
                .click(0.82, 0.52, at: 2.2),
                .move(.card(2, covered: true), Box(0.82, 0.52, 0.13, 0.155), FilmScene.slot(1), start: 2.4, end: 3.0,
                      appear: 2.25, angles: (0, FilmScene.tilt(1))),
            ])
        case .originalsToo:
            // A new screenshot is taken and hangs on the line, then goes to the
            // iPhone twice, covered and as it was taken; the older one only ever
            // went covered.
            return SettingFilm("lock.open.fill", FilmScene.line(cards: 1) + [
                .show(.phone, Box(0.82, 0.655, 0.22, 0.58)),
                .show(.card(0, covered: true), Box(0.82, 0.505, 0.115, 0.14)),
                .show(.window(.browser), Box(0.42, 0.64, 0.4, 0.5), to: 1.2),
                .move(.selection, Box(0.3, 0.525, 0.02, 0.03), Box(0.42, 0.66, 0.26, 0.3), start: 0.2, end: 0.6,
                      appear: 0.1, leave: 0.7),
                Part(kind: .cursor, keys: [
                    SettingFilm.Key(0.05, Box(0.29, 0.51, 0.05, 0.08), opacity: 0),
                    SettingFilm.Key(0.2, Box(0.29, 0.51, 0.05, 0.08)),
                    SettingFilm.Key(0.6, Box(0.55, 0.81, 0.05, 0.08)),
                    SettingFilm.Key(0.7, Box(0.55, 0.81, 0.05, 0.08)),
                    SettingFilm.Key(0.9, Box(0.55, 0.81, 0.05, 0.08), opacity: 0),
                ]),
                .move(.card(1), Box(0.42, 0.66, 0.26, 0.3), FilmScene.slot(1), start: 0.8, end: 1.3, appear: 0.7,
                      angles: (0, FilmScene.tilt(1))),
                Part(kind: .card(1, covered: true), keys: [
                    SettingFilm.Key(1.45, FilmScene.slot(1), opacity: 0, angle: FilmScene.tilt(1)),
                    SettingFilm.Key(1.7, Box(0.6, 0.42, 0.13, 0.155), angle: 1),
                    SettingFilm.Key(2.05, Box(0.82, 0.665, 0.115, 0.14)),
                ]),
                Part(kind: .card(1), keys: [
                    SettingFilm.Key(2.05, FilmScene.slot(1), opacity: 0, angle: FilmScene.tilt(1)),
                    SettingFilm.Key(2.3, Box(0.6, 0.5, 0.13, 0.155), angle: 1),
                    SettingFilm.Key(2.65, Box(0.82, 0.825, 0.115, 0.14)),
                ]),
            ])
        case .thisMac:
            // A covered copy waits beside a clock; a click on the sync button
            // sends it to the iPhone, and the clock turns into a check.
            return SettingFilm("arrow.clockwise.icloud", FilmScene.line(cards: 1) + [
                .show(.phone, Box(0.82, 0.655, 0.22, 0.58)),
                .show(.symbol("clock"), Box(0.14, 0.6, 0.1, 0.16), to: 2.0),
                .move(.card(0, covered: true), Box(0.3, 0.6, 0.13, 0.155), Box(0.82, 0.6, 0.13, 0.155),
                      start: 1.3, end: 1.9, appear: 0),
                Part(kind: .symbol("arrow.triangle.2.circlepath"), keys: [
                    SettingFilm.Key(0, Box(0.3, 0.84, 0.1, 0.16)),
                    SettingFilm.Key(1.05, Box(0.3, 0.84, 0.1, 0.16)),
                    SettingFilm.Key(1.85, Box(0.3, 0.84, 0.1, 0.16), angle: 360),
                ]),
                Part(kind: .cursor, keys: [
                    SettingFilm.Key(0.3, Box(0.12, 0.98, 0.05, 0.08), opacity: 0),
                    SettingFilm.Key(0.45, Box(0.12, 0.98, 0.05, 0.08)),
                    SettingFilm.Key(0.85, Box(0.3, 0.85, 0.05, 0.08)),
                    SettingFilm.Key(1.1, Box(0.3, 0.85, 0.05, 0.08)),
                    SettingFilm.Key(1.3, Box(0.3, 0.85, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.3, 0.84, at: 1.0),
                .show(.symbol("checkmark"), Box(0.14, 0.6, 0.1, 0.16), from: 2.1),
            ])
        case .connectWithACode:
            // The Mac shows the code and the iPhone types it in; a click on the
            // Mac's yes, and a screenshot from the iPhone hangs on the line.
            return SettingFilm("123.rectangle", FilmScene.line(cards: 1) + [
                .show(.phone, Box(0.82, 0.655, 0.22, 0.58)),
                .show(.key("481"), Box(0.22, 0.6, 0.12, 0.12)),
                .show(.key("305"), Box(0.36, 0.6, 0.12, 0.12)),
                .show(.key("481"), Box(0.82, 0.5, 0.16, 0.11), from: 0.5),
                .show(.key("305"), Box(0.82, 0.63, 0.16, 0.11), from: 0.9),
                .show(.symbol("checkmark"), Box(0.5, 0.6, 0.1, 0.16), from: 1.3),
                Part(kind: .cursor, keys: [
                    SettingFilm.Key(1.15, Box(0.4, 0.95, 0.05, 0.08), opacity: 0),
                    SettingFilm.Key(1.3, Box(0.4, 0.95, 0.05, 0.08)),
                    SettingFilm.Key(1.6, Box(0.51, 0.62, 0.05, 0.08)),
                    SettingFilm.Key(1.8, Box(0.51, 0.62, 0.05, 0.08)),
                    SettingFilm.Key(2.0, Box(0.51, 0.62, 0.05, 0.08), opacity: 0),
                ]),
                .click(0.51, 0.62, at: 1.7),
                .move(.card(2, covered: true), Box(0.82, 0.8, 0.13, 0.155), FilmScene.slot(1), start: 2.1, end: 2.7,
                      appear: 1.85, angles: (0, FilmScene.tilt(1))),
            ])
        }
    }
}

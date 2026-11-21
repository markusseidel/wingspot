# Plan: a native iPad app

Status: plan only, nothing is built. Goal: the same Wingspot app, with the same bundle ID and the same App Store listing
(universal purchase is not involved, the app is free), running as a real iPad app: full screen, all orientations, Split
View and Stage Manager, and a layout that uses the space instead of stretching the phone layout.

## Where we start

- iPhone only: `TARGETED_DEVICE_FAMILY: "1"`, portrait only, iOS 18 minimum (`ios/project.yml`). On an iPad the app now runs
  as a small iPhone window. On Apple Silicon Macs it runs as an iPhone app.
- Navigation: one `TabView` with five `Tab`s in `RootView` (Feed, Explore, Check in, Badges, Profile). The Check-in tab is
  not a destination: it opens a sheet. 13 `NavigationStack`s, 15 sheets or full-screen covers.
- Phone-shaped layouts: lists and forms everywhere, a fixed 360 x 450 share card, a full-width map in Explore.
- Things that behave differently on an iPad: the share sheet (`UIActivityViewController` in `ShareSheet`, fine inside a
  sheet, but a crash if ever shown as a popover without an anchor), the camera for boarding passes (`BoardingPassScanning`),
  location (Wi-Fi iPads have no GPS, so "nearby airport" may be coarse or missing), full-screen covers for onboarding.
- Nothing in the backend, the contracts or the Swift packages changes. Push, Sign in with Apple, SwiftData, MapKit and the
  photo picker work on iPad as they are.

## Decisions to take first

1. **Android parity.** The rule is that iOS and Android get the same change. For tablets that means adaptive layouts on
   Android too (navigation rail from 600 dp, list and detail side by side from 840 dp). Proposal: do the iPad work first
   and put Android large screens in a second plan with the same phases, so the apps do not drift for long.
2. **Mac.** Today the app is available on Apple Silicon Macs as an iPhone app. Once iPad is added it becomes an iPad app
   there. Keep that (cheap, no extra work) or opt out of Mac availability in App Store Connect. Proposal: keep it, test once.
3. **Minimum iOS** stays 18. It has what we need (`Tab`, sidebar-adaptable tab bars, `NavigationSplitView`).
4. **Multitasking.** Proposal: support it (no `UIRequiresFullScreen`), because testers use Slide Over next to a
   flight tracker. That needs all four orientations and layouts based on size classes, not on the device type.

## Phases (each is its own small PR, the app stays shippable after each)

### Phase 1: runs well as an iPad app (about 1 day)
- `TARGETED_DEVICE_FAMILY: "1,2"`, add all orientations for iPad (`UISupportedInterfaceOrientations_iPad`), keep the
  iPhone portrait only.
- Click through every screen on a 13-inch and an 11-inch iPad in both orientations and fix what breaks: forms and lists
  stretched edge to edge (cap the readable width, about 700 pt), sheets that open full height (use form sheet sizing for
  Check-in, Add a place, Review places), alerts, popovers, the photo viewer, the celebration sheet.
- Share sheet and any menu or confirmation dialog get an anchor (`confirmationDialog` and `ShareLink` do this by
  themselves, the `UIViewControllerRepresentable` ones need a check).
- Boarding pass scanner: check `DataScannerViewController.isSupported`, fall back to manual entry when not.
- Location: handle "no or coarse location" on a Wi-Fi iPad (the airport list simply shows without a nearest one).
- CI: add an iPad simulator build to the iOS job (compile check only).

### Phase 2: adaptive navigation (about 2 to 3 days)
- `TabView` with `.tabViewStyle(.sidebarAdaptable)`: a top tab bar or a sidebar on iPad, the tab bar on iPhone. The
  Check-in entry stays an action that opens the sheet (also in the sidebar).
- Feed: `NavigationSplitView` with the feed on the left and the check-in on the right in regular width.
- Explore: map and list side by side in regular width, a bigger map, the airport, type and registration pages in the detail
  column.
- Profile, Badges, Settings: grids (`LazyVGrid` with adaptive columns) for badges and collections instead of one long
  column.
- Everything decided by `horizontalSizeClass`, never by `UIDevice.current.userInterfaceIdiom`, so Split View and
  Stage Manager windows work like a phone when they are narrow.

### Phase 3: iPad polish (about 1 to 2 days)
- Hardware keyboard: command-N for a new check-in, command-F for search, return to submit forms, tab order, escape closes
  sheets. Pointer hover effects on rows and buttons.
- Drag and drop of photos into a check-in; drag a registration or airport out as text.
- Share cards and the invite QR code sized for the larger screen; the share card keeps its fixed export size.
- Larger Dynamic Type sizes and German text checked in the wide layouts.

### Phase 4: release (about 1 day)
- Required App Store Connect iPad screenshots (13-inch; 11-inch is optional) in English and German, new App Review
  notes (nothing new: same demo account), TestFlight group for iPad testers, the tester text says what to try.
- Version and build number bump as usual, one iPhone, iPad and Android build at the end.

## How we test

- Simulators: iPad Pro 13-inch and 11-inch, iPad mini; portrait and landscape; Split View at one third, one half and two
  thirds; Slide Over; Stage Manager with a resized window; light and dark; German; the largest Dynamic Type.
- Click through the same flows as on the iPhone: sign in, check-in (airport, spotted, flown, scan), feed and comments,
  explore and the map, badges and the celebration, people and compare, spotting places (suggest, review for the founder),
  settings and data export (share sheet).
- A real iPad before the first TestFlight: camera scan, location, push, the share sheet.
- Unit tests do not change; the packages are platform independent.

## Risks

- Once an iPad is supported in a release, dropping it later is awkward, and every later UI change has to work at both
  sizes. That is the main cost, not the first build.
- Screens that assume portrait (fixed frames, `GeometryReader` heights) will need work; the first full click-through
  (phase 1) is what tells us how much.
- Sidebar-adaptable tab bars and the Check-in action tab need testing on every iPadOS 18 and 26 size; the fallback is the
  plain top tab bar.
- App Review looks at iPad separately: screenshots and a working demo account on iPad are mandatory.

## Open questions for the owner

1. Is Android tablet support part of the same release, or a second step (proposal: second step, same phases)?
2. Keep the app available on Mac as an iPad app?
3. Is Split View and Stage Manager support wanted from the first iPad release (proposal: yes)?
4. Who has an iPad for the real-device test?

# PocketCasts UI fixes:

## Need to spec social

1. Show the Debug menu in TestFlight
2. Add detailed descriptions below each Beta Feature toggle
3. Give me lots of ideas for features based on universal transcript availability
4. Fix broken fast forward / rewind icons on playing episode view
5. Make bottom bar on playing episode view liquid glass
6. Option on playing episode view for blurred image background (like feed
7. **Several Discover entry points still route to Library instead of the new Explore tab.** Deep links and empty-state CTAs in [AppDelegate+UrlHandling.swift (line 126)](/Users/haroldmartin/projects/pocket-casts-ios/podcasts/AppDelegate+UrlHandling.swift:126) use the former tab mapping; some CTAs therefore become no-ops or open the wrong surface.
8. All transcript should be posted to backend sync server (even with no account), include details about the source of the transcript
9. Ensure that local transcription happens serially (one episode at a time)
10. skipChapterTitles should be a feature flag that defaults off
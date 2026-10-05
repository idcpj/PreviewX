# PreviewX — Reference Links

## Apple

- Quick Look UI: https://developer.apple.com/documentation/quicklookui/
- Quick Look Preview Extensions: https://developer.apple.com/documentation/quicklookui/
- QLPreviewingController: https://developer.apple.com/documentation/quicklook/qlpreviewingcontroller
- QLPreviewProvider: https://developer.apple.com/documentation/quicklook/qlpreviewprovider
- Uniform Type Identifiers: https://developer.apple.com/documentation/uniformtypeidentifiers
- QLPreviewController: https://developer.apple.com/documentation/quicklook/qlpreviewcontroller

## Notes

These references are starting points for implementation agents. Apple API behavior and supported system types can vary by macOS release, so CI must test the target deployment versions.

The architecture intentionally avoids assuming that every file type must be implemented by PreviewX: macOS already provides Quick Look support for many standard types. PreviewX should focus on developer-oriented gaps and enhanced representations. citeturn0search0turn0search6
